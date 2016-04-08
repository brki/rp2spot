//
//  UserSetting.swift
//  rp2spot
//
//  Created by Brian on 27/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

class UserSetting {
	static let sharedInstance = UserSetting()

	lazy var settings = NSUserDefaults.standardUserDefaults()

	var spotifyStreamingQuality: SPTBitrate {
		get {
			// Use objectForKey instead of integerForKey since integerForKey returns 0 when nothing set.
			guard let quality = settings.objectForKey("spotifyStreamingQuality") as? UInt else {
				let bitRate = SPTBitrate.Normal
				settings.setInteger(Int(bitRate.rawValue), forKey: "spotifyStreamingQuality")
				return bitRate
			}
			guard let bitRate = SPTBitrate.init(rawValue: quality) else {
				print("Unable to initialize SPTBitrate enum from user default setting")
				return SPTBitrate.Normal
			}
			return bitRate
		}
		set {
			settings.setInteger(Int(newValue.rawValue), forKey: "spotifyStreamingQuality")
		}
	}

	// How many songs should be fetched in a history request:
	var historyFetchSongCount: Int {
		get {
			let count = settings.integerForKey("historyFetchSongCount")
			guard count != 0 else {
				settings.setInteger(20, forKey: "historyFetchSongCount")
				return 20
			}
			return count
		}
		set {
			settings.setInteger(newValue, forKey: "historyFetchSongCount")
		}
	}

	// How many song items, at most, should be stored locally:
	var maxLocalSongHistoryCount: Int {
		get {
			let count = settings.integerForKey("maxLocalSongHistoryCount")
			guard count != 0 else {
				settings.setInteger(200, forKey: "maxLocalSongHistoryCount")
				return 200
			}
			return count
		}
		set {
			guard newValue >= historyFetchSongCount else {
				// Enforce that maxLocalSongHistoryCount >= historyFetchSongCount
				return
			}
			settings.setInteger(newValue, forKey: "maxLocalSongHistoryCount")
		}
	}

	// User's Spotify region
	var spotifyRegion: String? {
		get {
			return settings.stringForKey("spotifyRegion")
		}
		set {
			settings.setObject(newValue, forKey: "spotifyRegion")
		}
	}

	var defaultSpotifyRegion = "US"

	// Non-optional value that can be used when fetching RP history.
	var spotifyRegionValue: String {
		get {
			return spotifyRegion ?? defaultSpotifyRegion
		}
	}

	var canStreamSpotifyTracks: Bool? {
		get {
			return settings.objectForKey("canStreamSpotifyTracks") as? Bool
		}
		set {
			if newValue == nil {
				settings.removeObjectForKey("canStreamSpotifyTracks")
			} else {
				settings.setObject(newValue, forKey: "canStreamSpotifyTracks")
			}
		}
	}

	var historyBrowserTopVisibleRow: Int {
		get {
			return settings.integerForKey("historyBrowserTopVisibleRow")
		}
		set {
			settings.setInteger(newValue, forKey: "historyBrowserTopVisibleRow")
		}
	}
}