//
//  SpotifyAuth.swift
//  rp2spot
//
//  Created by Brian on 13/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

class SpotifyAuth {
	static let sharedInstance = SpotifyAuth()

	let auth = SPTAuth.defaultInstance()

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
}