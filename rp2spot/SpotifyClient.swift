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

	static let sharedInstance = SpotifyClient()

	let auth = SPTAuth.defaultInstance()

	lazy var player: SPTAudioStreamingController = {
		return SPTAudioStreamingController(clientId: self.auth.clientID)
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
		return NSURL(string: "spotify:track:\(trackId)")
	}

	func playTrack(trackId: String) {
		player.loginWithSession(auth.session) { error in
			guard error == nil else {
				print("playTrack: error while logging in: \(error!)")
				return
			}
		}

		guard let URI = trackURI(trackId) else {
			print("Unable to generate URI from track id: \(trackId)")
			return
		}

		player.playURIs([URI], fromIndex:0) { error in
			if error != nil {
				print("Error while initiating playback")
			}
		}
	}
}