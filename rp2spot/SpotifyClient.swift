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

	func renewSession(completionHandler:(error: NSError?) -> Void) {

		auth.renewSession(auth.session) { error, session in
			self.auth.session = session
			// or post a notification here? (instead of having a completion handler)
			completionHandler(error: error)
		}
	}

	func loginOrRenewSession(handler: (willTriggerNotification: Bool, error: NSError?) -> Void) {
		// TODO: cleanup these prints:
		guard auth.session != nil else {

			print("will trigger login")
			handler(willTriggerNotification: true, error: nil)
			triggerSafariLogin()
			return
		}

		if auth.session.isValid() {
			print("already have a valid session, nothing to do")
			handler(willTriggerNotification: false, error: nil)
			return
		}

		print("will renew session")
		renewSession() { error in
			handler(willTriggerNotification: false, error: error)
		}
	}

	func trackURI(trackId: String) -> NSURL? {
		return NSURL(string: SpotifyClient.fullSpotifyTrackId(trackId))
	}

	func URIsForTrackIds(trackIds: [String]) -> [NSURL] {
		var URIs = [NSURL]()
		for id in trackIds {
			if let URI = trackURI(id) {
				URIs.append(URI)
			}
		}
		return URIs
	}

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
}