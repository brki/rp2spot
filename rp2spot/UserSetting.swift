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

	// TODO: make these configurable variables

	// How many songs should be fetched in a history request:
	var historyFetchSongCount = 20

	// TODO: when configurable, ensure that historyFetchSongCount <= maxLocalSongHistoryCount
	// How many song items, at most, should be stored locally:
	var maxLocalSongHistoryCount = 90

	// User's spotifyRegion (autodetected, but configurable)
	var spotifyRegion = "CH"

	var spotifyStreamingQuality = SPTBitrate.High
}