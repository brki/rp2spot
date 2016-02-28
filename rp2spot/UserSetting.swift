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

	// How big should the chunks of history that are grabbed in a request be:
	var historyFetchPeriodInHours = 1

	// How many hours, at most, should be stored locally:
	var maxLocalSongHistoryInHours = 4

	// User's spotifyRegion (autodetected, but configurable)
	var spotifyRegion = "CH"
}