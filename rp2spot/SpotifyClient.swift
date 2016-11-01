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

	let auth = SPTAuth.defaultInstance()!

	let trackInfo = SpotifyTrackInfoManager.sharedInstance

	var refreshSessionTimeoutBuffer = TimeInterval(60.0 * 10)  // 10 minutes

	let sessionRenewalOperationQueue: OperationQueue = {
		let queue = OperationQueue()
		queue.maxConcurrentOperationCount = 1
		return queue
	}()

	lazy var player: SPTAudioStreamingController = {
		let player = SPTAudioStreamingController(clientId: self.auth.clientID)!
		player.setTargetBitrate(UserSetting.sharedInstance.spotifyStreamingQuality, callback: nil)
		player.`repeat` = false
		return player
	}()

	/**
	The players current (playing or not) track ID, if any.
	*/
	var playerCurrentTrackId: String? {
		let currentURI: URL? = player.currentTrackURI
		guard currentURI != nil else {
			return nil
		}
		return SPTTrack.identifier(fromURI: currentURI)
	}

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
			SPTAuthUserReadPrivateScope,			// Needed to know territory for non-premium Spotify accounts
		]
	}

	static func fullSpotifyTrackId(_ shortId: String) -> String {
		return "spotify:track:\(shortId)"
	}

	static func shortSpotifyTrackId(_ fullId: String) -> String {
		return fullId.replacingOccurrences(of: "spotify:track:", with: "")
	}

	/**
	Post a session-updated notification to the default notification center.

	This is called when the app delegate opens in response to an authentication URL.
	*/
	func postSessionUpdateNotification(_ authError: NSError? = nil) {
		var userInfo = [String: AnyObject]()
		if let error = authError {
			userInfo["authError"] = error
		}

		NotificationCenter.default.post(
			name: Notification.Name(rawValue: SpotifyClient.SESSION_UPDATE_NOTIFICATION),
			object: self,
			userInfo: userInfo
		)
	}

	func triggerSafariLogin() {
		UIApplication.shared.openURL((auth.loginURL)!)
	}

	/**
	Renew session.
	
	Only allows one active session renewal process at a time, adding others to a queue.

	If forceRefresh is true, the session renewal request will be made even if a fresh session exists.
	Otherwise, if a fresh session already exists when the session renewal block starts executing, then
	no request for refreshing the session will be made.
	*/
	func renewSession(_ forceRenew: Bool = false, completionHandler:((_ error: NSError?) -> Void)? = nil) {
		let renewalOperation = SpotifyAuthRenewalOperation(forceRenew: forceRenew, authCompletionHandler: completionHandler)
		sessionRenewalOperationQueue.addOperation(renewalOperation)
	}

	func loginOrRenewSession(_ handler: @escaping (_ willTriggerLogin: Bool, _ sessionValid: Bool, _ error: NSError?) -> Void) {
		guard auth.session != nil else {
			handler(true, false, nil)
			triggerSafariLogin()
			return
		}

		guard (auth.session.isValid()) else {
			renewSession() { error in
				handler(false, (self.auth.session.isValid()), error)
			}
			return
		}

		// Already have a valid session, we're good to go.
		handler(false, true, nil)

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
		guard let session = auth.session, session.isValid() else {
			return true
		}

		let expirationDateMinusBuffer = Foundation.Date(timeInterval: -refreshSessionTimeoutBuffer, since: session.expirationDate)
		return (expirationDateMinusBuffer as NSDate).earlierDate(Foundation.Date()) == expirationDateMinusBuffer
	}

	func trackURI(_ trackId: String) -> URL? {
		return URL(string: SpotifyClient.fullSpotifyTrackId(trackId))
	}

	/**
	Gets NSURLS for the provided (short form) Spotify track ids.
	*/
	func URIsForTrackIds(_ trackIds: [String]) -> [URL] {
		var URIs = [URL]()
		for id in trackIds {
			if let URI = trackURI(id) {
				URIs.append(URI)
			}
		}
		return URIs
	}

	func playTracks(_ URIs: [URL], fromIndex: Int = 0, trackStartTime: TimeInterval, handler: ((NSError?) -> Void)? = nil) {

		func startPlaying() {
			// Stop player and clear track list before starting playback of new track list.
			self.player.stop() { error in
				guard error == nil else {
					print("playTracks: error while attempting to stop playing")
					handler?(error as NSError?)
					return
				}
				let options = SPTPlayOptions()
				options.trackIndex = Int32(fromIndex)
				options.startTime = trackStartTime
				self.player.playURIs(URIs, with: options) { error in
					if error != nil {
						print("playTracks: Error while initiating playback")
					}
					handler?(error as NSError?)
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
			player.login(with: auth.session) { error in
				guard error == nil else {
					print("playTracks: error while logging in: \(error!)")
					handler?(error as NSError?)
					return
				}
				startPlaying()
			}
		}
	}

	func createPlaylistWithTracks(_ playlistName: String, trackIds: [String], publicFlag: Bool,
		handler: @escaping (_ playlistSnapshot: SPTPlaylistSnapshot?, _ willTriggerLogin: Bool, _ error: NSError?) -> Void) {

		let trackURIs = URIsForTrackIds(trackIds)

		loginOrRenewSession() { willTriggerLogin, sessionValid, error in
			guard error == nil && !willTriggerLogin else {
				handler(nil, willTriggerLogin, error)
				return
			}

			// create a new playlist
			SPTPlaylistList.createPlaylist(withName: playlistName, publicFlag: publicFlag, session: self.auth.session, callback: { error, playlist in
				guard error == nil else {
					handler(nil, false, error! as NSError?)
					return
				}

				self.addTracksToPlaylist(playlist!, trackURIs: trackURIs, processedCount: 0) { error, processedCount in
					if error != nil {
						print("createPlaylistWithTracks: error adding tracks: processedCount: \(processedCount), error: \(error!)")
					}
					handler(playlist, false, error)
				}
			})

		}
	}

	func addTracksToPlaylist(_ playlist: SPTPlaylistSnapshot, trackURIs: [URL], processedCount: Int = 0,
	                         handler: @escaping (_ error: NSError?, _ processedCount: Int) -> Void) {
		var alreadyProcessedCount = processedCount
		var tracksToProcess: [URL]
		var leftoverTracks: [URL]?
		if trackURIs.count > Constant.SPOTIFY_MAX_PLAYLIST_ADD_TRACKS {
			let maxIndex = Constant.SPOTIFY_MAX_PLAYLIST_ADD_TRACKS - 1
			tracksToProcess = Array(trackURIs[0 ... maxIndex])
			leftoverTracks = Array(trackURIs[(maxIndex + 1) ... (trackURIs.count - 1)])
		} else {
			tracksToProcess = trackURIs
			leftoverTracks = nil
		}
		playlist.addTracks(toPlaylist: tracksToProcess, with: self.auth.session) { error in

			// If there was an error, or if there are no more tracks to process, call the completion handler:
			guard error == nil else {
				handler(error as NSError?, alreadyProcessedCount)
				return
			}

			alreadyProcessedCount += tracksToProcess.count
			guard let tracks = leftoverTracks else {
				handler(nil, alreadyProcessedCount)
				return
			}

			// Otherwise, continue processing tracks:
			self.addTracksToPlaylist(playlist, trackURIs: tracks, processedCount: alreadyProcessedCount, handler: handler)
		}
	}

	func getUserInfo(_ handler: @escaping (_ territory: String?, _ canStream: Bool?) -> Void) {

		guard auth.session != nil else {
			print("getUserTerritory: No valid session, can not get user territory")
			handler(nil, nil)
			return
		}

		SPTUser.requestCurrentUser(withAccessToken: auth.session.accessToken) { userInfoError, user in

			guard userInfoError == nil else {
				print("getUserTerritory: Error when trying to get user information: \(userInfoError!)")
				handler(nil, nil)
				return
			}

			guard let userInfo = user as? SPTUser else {
				print("getUserTerritory: no userInfo present in handler for SPTUser.requestCurrentUserWithAccessToken")
				handler(nil, nil)
				return
			}

			let canStream = (userInfo.product == SPTProduct.premium)

			guard userInfo.territory != nil else {
				print("getUserTerritory: no userInfo.territory present in handler for SPTUser.requestCurrentUserWithAccessToken")
				handler(nil, canStream)
				return
			}

			guard userInfo.territory.characters.count == 2 else {
				print("getUserTerritory: unexpected territory value in handler for SPTUser.requestCurrentUserWithAccessToken: \(userInfo.territory)")
				handler(nil, canStream)
				return
			}

			handler(userInfo.territory, canStream)
		}
	}
}
