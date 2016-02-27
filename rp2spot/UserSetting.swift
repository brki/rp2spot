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
	var historyFetchPeriodInHours = 0.5
	var spotifyRegion = "CH"
}