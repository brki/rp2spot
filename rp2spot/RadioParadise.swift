//
//  RadioParadise.swift
//  rp2spot
//
//  Created by Brian on 14/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation
import Alamofire


typealias RPFetchHandler = (playedSongs: [PlayedSongData]?, error: NSError?, response: NSHTTPURLResponse?) -> Void

struct RadioParadise {

	enum ImageSize: String {
		case Small = "s"
		case Medium = "m"
		case Large = "l"
	}

	static let userSettings = UserSetting.sharedInstance

	static func fetchNewer(region: String, newerThan: NSDate, handler: RPFetchHandler? = nil) -> Request {
		let from = newerThan ?? NSDate()
		let to = Date.sharedInstance.timeWithHourDifference(from, hours: Double(userSettings.historyFetchPeriodInHours))
		return fetchPeriod(region, fromDate: from, toDate: to, handler: handler)
	}

	static func fetchOlder(region: String, olderThan: NSDate, handler: RPFetchHandler? = nil) -> Request {
		let from = Date.sharedInstance.timeWithHourDifference(olderThan, hours: -Double(userSettings.historyFetchPeriodInHours))
		return fetchPeriod(region, fromDate: from, toDate: olderThan, handler: handler)
	}

	static func fetchPeriod(region: String, fromDate: NSDate, toDate: NSDate, handler: RPFetchHandler? = nil) -> Request {

		let params = [
			"start_time": Date.sharedInstance.toUTCString(fromDate),
			"end_time": Date.sharedInstance.toUTCString(toDate),
		]

		let url = Constant.RADIO_PARADISE_HISTORY_URL_BASE + region + "/"

		let request = Alamofire.request(.GET, url, parameters: params).responseCollection() { (response: Response<[PlayedSongData], NSError>) in
			switch response.result {
			case .Success(let playedSongs):
				handler?(playedSongs: playedSongs, error:nil, response: response.response)
			case .Failure(let error):
				handler?(playedSongs: nil, error:error, response: response.response)
			}
		}
		return request
	}

	static func imageURLText(asin: String, size: ImageSize) -> String {
		return "https://www.radioparadise.com/graphics/covers/\(size.rawValue)/\(asin).jpg"
	}
}