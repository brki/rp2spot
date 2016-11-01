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

	lazy var settings = UserDefaults.standard

	var spotifyStreamingQuality: SPTBitrate {
		get {
			// Use objectForKey instead of integerForKey since integerForKey returns 0 when nothing set.
			guard let quality = settings.object(forKey: "spotifyStreamingQuality") as? UInt else {
				let bitRate = SPTBitrate.normal
				settings.set(Int(bitRate.rawValue), forKey: "spotifyStreamingQuality")
				return bitRate
			}
			guard let bitRate = SPTBitrate.init(rawValue: quality) else {
				print("Unable to initialize SPTBitrate enum from user default setting")
				return SPTBitrate.normal
			}
			return bitRate
		}
		set {
			settings.set(Int(newValue.rawValue), forKey: "spotifyStreamingQuality")
		}
	}

	// How many songs should be fetched in a history request:
	var historyFetchSongCount: Int {
		get {
			let count = settings.integer(forKey: "historyFetchSongCount")
			guard count != 0 else {
				settings.set(20, forKey: "historyFetchSongCount")
				return 20
			}
			return count
		}
		set {
			settings.set(newValue, forKey: "historyFetchSongCount")
		}
	}

	// How many song items, at most, should be stored locally:
	var maxLocalSongHistoryCount: Int {
		get {
			let count = settings.integer(forKey: "maxLocalSongHistoryCount")
			guard count != 0 else {
				settings.set(200, forKey: "maxLocalSongHistoryCount")
				return 200
			}
			return count
		}
		set {
			guard newValue >= historyFetchSongCount else {
				// Enforce that maxLocalSongHistoryCount >= historyFetchSongCount
				return
			}
			settings.set(newValue, forKey: "maxLocalSongHistoryCount")
		}
	}

	// User's Spotify region
	var spotifyRegion: String? {
		get {
			return settings.string(forKey: "spotifyRegion")
		}
		set {
			settings.set(newValue, forKey: "spotifyRegion")
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
			return settings.object(forKey: "canStreamSpotifyTracks") as? Bool
		}
		set {
			if newValue == nil {
				settings.removeObject(forKey: "canStreamSpotifyTracks")
			} else {
				settings.set(newValue, forKey: "canStreamSpotifyTracks")
			}
		}
	}

	var historyBrowserTopVisibleRow: Int {
		get {
			return settings.integer(forKey: "historyBrowserTopVisibleRow")
		}
		set {
			settings.set(newValue, forKey: "historyBrowserTopVisibleRow")
		}
	}
}
