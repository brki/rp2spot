//
//  Constant.swift
//  rp2spot
//
//  Created by Brian on 13/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

struct Constant {
	static var SPOTIFY_CLIENT_ID = Secrets.SPOTIFY_CLIENT_ID
	static var SPOTIFY_AUTH_CALLBACK_URL = NSURL(string: Secrets.SPOTIFY_AUTH_CALLBACK_URL)!
	static var SPOTIFY_TOKEN_SWAP_URL = NSURL(string: Secrets.SPOTIFY_TOKEN_SWAP_URL)!
	static var SPOTIFY_TOKEN_REFRESH_URL = NSURL(string: Secrets.SPOTIFY_TOKEN_REFRESH_URL)!
	static var SPOTIFY_SESSION_USER_DEFAULTS_KEY = "SpotifySession"
}