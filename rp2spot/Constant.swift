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
	static let SPOTIFY_APPSTORE_URL = NSURL(string: "itms-apps://itunes.apple.com/app/id324684580")!

	// The maximum number of tracks that can be added to a playlist in one API call:
	static let SPOTIFY_MAX_PLAYLIST_ADD_TRACKS = 100

	// The maximum number of tracks that the Spotify player accepts as it's current playlist:
	static let SPOTIFY_MAX_PLAYER_TRACKS = 100

	// The Spotify web service limits to a maximum of 50 URIs when fetching track information.
	static let SPOTIFY_MAX_TRACKS_FOR_INFO_FETCH = 50

	static let CACHE_SPOTIFY_TRACK_INFO_MAX_COUNT = 500

	static let RADIO_PARADISE_HISTORY_URL_BASE = Secrets.RADIO_PARADISE_HISTORY_URL_BASE
	static let RADIO_PARADISE_IMAGE_URL_BASE = "https://www.radioparadise.com/graphics/covers/"
	static let RADIO_PARADISE_MINIMUM_HISTORY_DATE = Date.sharedInstance.dateFromRPDateString("2015-02-24T16:45:00+00:00")!
	static let RADIO_PARADISE_SONG_INFO_URL_TEMPLATE="https://www.radioparadise.com/mx-content.php?name=Music&file=songinfo&song_id={songid}"

	enum Color: UInt {
		case SageGreen = 0xEEFFEC
		case LightGrey = 0xD8DBE0
		case LightOrange = 0xFFF4EC
		case SpotifyGreen = 0x23CF5F

		func color(alpha: CGFloat = 1.0) -> UIColor {
			return UIColor.colorWithRGB(self.rawValue, alpha: alpha)
		}
	}
}