//
//  Constant.swift
//  rp2spot
//
//  Created by Brian on 13/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

struct Constant {
	static let SPOTIFY_CLIENT_ID = Secrets.SPOTIFY_CLIENT_ID
	static let SPOTIFY_AUTH_CALLBACK_URL = NSURL(string: Secrets.SPOTIFY_AUTH_CALLBACK_URL)!
	static let SPOTIFY_TOKEN_SWAP_URL = NSURL(string: Secrets.SPOTIFY_TOKEN_SWAP_URL)!
	static let SPOTIFY_TOKEN_REFRESH_URL = NSURL(string: Secrets.SPOTIFY_TOKEN_REFRESH_URL)!
	static let SPOTIFY_SESSION_USER_DEFAULTS_KEY = "SpotifySession"

	static let RADIO_PARADISE_HISTORY_URL_BASE = Secrets.RADIO_PARADISE_HISTORY_URL_BASE
}