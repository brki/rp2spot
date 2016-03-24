//
//  SpotifyClient.swift
//  rp2spot
//
//  Created by Brian on 13/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

class SpotifyClient {
	static let SESSION_UPDATE_NOTIFICATION = "sessionUpdated"
	static let MAX_PLAYER_TRACK_COUNT = 100 // Spotify player accepts maximum 100 tracks

	static let sharedInstance = SpotifyClient()

	let auth = SPTAuth.defaultInstance()

	let trackInfo = SpotifyTrackInfoManager.sharedInstance

	var refreshSessionTimeoutBuffer = NSTimeInterval(60.0 * 10)  // 10 minutes

	let sessionRenewalOperationQueue: NSOperationQueue = {
		let queue = NSOperationQueue()
		queue.maxConcurrentOperationCount = 1
		return queue
	}()

	lazy var player: SPTAudioStreamingController = {
		let player = SPTAudioStreamingController(clientId: self.auth.clientID)
		player.setTargetBitrate(UserSetting.sharedInstance.spotifyStreamingQuality, callback: nil)
		player.`repeat` = false
		return player
	}()

	init() {
		// Set up shared authentication information
		auth.clientID = Constant.SPOTIFY_CLIENT_ID;
		auth.redirectURL = Constant.SPOTIFY_AUTH_CALLBACK_URL
		auth.tokenSwapURL = Constant.SPOTIFY_TOKEN_SWAP_URL
		auth.tokenRefreshURL = Constant.SPOTIFY_TOKEN_REFRESH_URL
		auth.sessionUserDefaultsKey = Constant.SPOTIFY_SESSION_USER_DEFAULTS_KEY;

		auth.requestedScopes = [
			SPTAuthStreamingScope,					// Allow streaming music
			SPTAuthPlaylistReadPrivateScope,		// Allow reading user's private plalists
			SPTAuthPlaylistModifyPublicScope,		// Allow creating / modifying user's public playlists
			SPTAuthPlaylistModifyPrivateScope,		// Allow creating / modifying user's private playlists
		]
	}

	static func fullSpotifyTrackId(shortId: String) -> String {
		return "spotify:track:\(shortId)"
	}

	static func shortSpotifyTrackId(fullId: String) -> String {
		return fullId.stringByReplacingOccurrencesOfString("spotify:track:", withString: "")
	}

	/**
	Post a session-updated notification to the default notification center.

	This is called when the app delegate opens in response to an authentication URL.
	*/
	func postSessionUpdateNotification(authError: NSError? = nil) {
		var userInfo = [String: AnyObject]()
		if let error = authError {
			userInfo["authError"] = error
		}

		NSNotificationCenter.defaultCenter().postNotificationName(
			SpotifyClient.SESSION_UPDATE_NOTIFICATION,
			object: self,
			userInfo: userInfo
		)
	}

	func triggerSafariLogin() {
		UIApplication.sharedApplication().openURL(auth.loginURL)
	}

	/**
	Renew session.
	
	Only allows one active session renewal process at a time, adding others to a queue.

	If forceRefresh is true, the session renewal request will be made even if a fresh session exists.
	Otherwise, if a fresh session already exists when the session renewal block starts executing, then
	no request for refreshing the session will be made.
	*/
	func renewSession(forceRenew: Bool = false, completionHandler:((error: NSError?) -> Void)? = nil) {
		let renewalOperation = SpotifyAuthRenewalOperation(forceRenew: forceRenew, authCompletionHandler: completionHandler)
		sessionRenewalOperationQueue.addOperation(renewalOperation)
	}

	func loginOrRenewSession(handler: (willTriggerLogin: Bool, sessionValid: Bool, error: NSError?) -> Void) {
		guard auth.session != nil else {
			handler(willTriggerLogin: true, sessionValid: false, error: nil)
			triggerSafariLogin()
			return
		}

		guard auth.session.isValid() else {
			renewSession() { error in
				handler(willTriggerLogin: false, sessionValid:self.auth.session.isValid(), error: error)
			}
			return
		}

		// Already have a valid session, we're good to go.
		handler(willTriggerLogin: false, sessionValid: true, error: nil)

		// Try to renew a session that's getting near it's timeout before it expires.
		if sessionShouldBeRenewedSoon() {
			renewSession()
		}
	}

	/**
	Checks if the session should be refreshed.

	Will return true if the session is invalid or is nearing it's expiration time.
	*/
	func sessionShouldBeRenewedSoon() -> Bool {
		guard let session = auth.session where session.isValid() else {
			return true
		}

		let expirationDateMinusBuffer = NSDate(timeInterval: -refreshSessionTimeoutBuffer, sinceDate: session.expirationDate)
		return expirationDateMinusBuffer.earlierDate(NSDate()) == expirationDateMinusBuffer
	}
	

	func trackURI(trackId: String) -> NSURL? {
		return NSURL(string: SpotifyClient.fullSpotifyTrackId(trackId))
	}

	/**
	Gets NSURLS for the provided (short form) Spotify track ids.
	*/
	func URIsForTrackIds(trackIds: [String]) -> [NSURL] {
		var URIs = [NSURL]()
		for id in trackIds {
			if let URI = trackURI(id) {
				URIs.append(URI)
			}
		}
		return URIs
	}

	// TODO: adapt to allow specifying a time in the track to start playing.
	func playTracks(URIs: [NSURL], fromIndex: Int = 0, handler: ((NSError?) -> Void)? = nil) {

		func startPlaying() {
			// Stop player and clear track list before starting playback of new track list.
			self.player.stop() { error in
				guard error == nil else {
					print("playTracks: error while attempting to stop playing")
					handler?(error)
					return
				}
				self.player.playURIs(URIs, fromIndex:Int32(fromIndex)) { error in
					if error != nil {
						print("playTracks: Error while initiating playback")
					}
					handler?(error)
				}
			}
		}

		guard URIs.count > 0 else {
			print("playTracks: No spotify tracks URIs provided")
			return
		}

		if player.loggedIn {
			startPlaying()
		} else {
			player.loginWithSession(auth.session) { error in
				guard error == nil else {
					print("playTracks: error while logging in: \(error!)")
					handler?(error)
					return
				}
				startPlaying()
			}
		}
	}

	func trackInfo(trackId: String, handler: (trackMetadata: [NSObject: AnyObject]?, error: NSError?) -> Void) {
		guard let URI = trackURI(trackId) else {
			handler(trackMetadata: nil, error: NSError(domain: "SpotifyClient", code: 1,
				userInfo: [NSLocalizedDescriptionKey: "Unable to generate spotify URL from provided trackId (\(trackId))"]))
			return
		}
		SPTTrack.trackWithURI(URI, session: auth.session) { error, trackMetadata in
			guard error == nil else {
				handler(trackMetadata: nil, error:  error)
				return
			}
			guard let metadata = trackMetadata as? [NSObject: AnyObject] else {
				handler(trackMetadata: nil, error: NSError(domain: "SpotifyClient", code: 2,
					userInfo: [NSLocalizedDescriptionKey: "Unexpected track metadata format"]))
				return
			}
			handler(trackMetadata: metadata, error: nil)
		}
	}

	func createPlaylistWithTracks(playlistName: String, trackIds: [String], publicFlag: Bool,
		handler: (playlistSnapshot: SPTPlaylistSnapshot?, willTriggerLogin: Bool, error: NSError?) -> Void) {

		let trackURIs = URIsForTrackIds(trackIds)

		loginOrRenewSession() { willTriggerLogin, sessionValid, error in
			guard error == nil && !willTriggerLogin else {
				handler(playlistSnapshot: nil, willTriggerLogin: willTriggerLogin, error: error)
				return
			}

			// create a new playlist
			SPTPlaylistList.createPlaylistWithName(playlistName, publicFlag: publicFlag, session: self.auth.session, callback: { error, playlist in
				guard error == nil else {
					handler(playlistSnapshot: nil, willTriggerLogin: false, error: error!)
					return
				}

				self.addTracksToPlaylist(playlist, trackURIs: trackURIs, processedCount: 0) { error, processedCount in
					if error != nil {
						print("createPlaylistWithTracks: error adding tracks: processedCount: \(processedCount), error: \(error!)")
					}
					handler(playlistSnapshot: playlist, willTriggerLogin: false, error: error)
				}

			})

		}
	}

	func addTracksToPlaylist(playlist: SPTPlaylistSnapshot, trackURIs: [NSURL], processedCount: Int = 0,
	                         handler: (error: NSError?, processedCount: Int) -> Void) {
		var alreadyProcessedCount = processedCount
		var tracksToProcess: [NSURL]
		var leftoverTracks: [NSURL]?
		if trackURIs.count > Constant.SPOTIFY_MAX_PLAYLIST_ADD_TRACKS {
			let maxIndex = Constant.SPOTIFY_MAX_PLAYLIST_ADD_TRACKS - 1
			tracksToProcess = Array(trackURIs[0 ... maxIndex])
			leftoverTracks = Array(trackURIs[(maxIndex + 1) ... (trackURIs.count - 1)])
		} else {
			tracksToProcess = trackURIs
			leftoverTracks = nil
		}
		playlist.addTracksToPlaylist(tracksToProcess, withSession: self.auth.session) { error in

			// If there was an error, or if there are no more tracks to process, call the completion handler:
			guard error == nil else {
				handler(error: error, processedCount: alreadyProcessedCount)
				return
			}

			alreadyProcessedCount += tracksToProcess.count
			guard let tracks = leftoverTracks else {
				handler(error: nil, processedCount: alreadyProcessedCount)
				return
			}

			// Otherwise, continue processing tracks:
			self.addTracksToPlaylist(playlist, trackURIs: tracks, processedCount: alreadyProcessedCount, handler: handler)
		}
	}
}