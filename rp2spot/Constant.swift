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
	static let RADIO_PARADISE_IMAGE_URL_BASE = "https://www.radioparadise.com/graphics/covers/"
	static let RADIO_PARADISE_MINIMUM_HISTORY_DATE = Date.sharedInstance.dateFromRPDateString("2015-02-24T16:45:00+00:00")!


	enum Color: UInt {
		case SageGreen = 0xEEFFEC
		case LightGrey = 0xD8DBE0
		case LightOrange = 0xFFF4EC

		func color(alpha: CGFloat = 1.0) -> UIColor {
			return UIColor.colorWithRGB(self.rawValue, alpha: alpha)
		}
	}
}