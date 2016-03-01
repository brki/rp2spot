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

	static let DEFAULT_FETCH_COUNT = 100

	static let userSettings = UserSetting.sharedInstance

	static func fetchNewer(region: String, newerThan: NSDate, count: Int = DEFAULT_FETCH_COUNT, handler: RPFetchHandler? = nil) -> Request {
		return fetchPeriod(region, date: newerThan, vectorCount: count, handler: handler)
	}

	static func fetchOlder(region: String, olderThan: NSDate, count: Int = DEFAULT_FETCH_COUNT, handler: RPFetchHandler? = nil) -> Request {
		return fetchPeriod(region, date: olderThan, vectorCount: -count, handler: handler)
	}

	static func fetchPeriod(region: String, date: NSDate, vectorCount: Int, handler: RPFetchHandler? = nil) -> Request {

		let params: [String: AnyObject] = [
			"base_time": Date.sharedInstance.toUTCString(date),
			"count_vector": vectorCount,
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
		return Constant.RADIO_PARADISE_IMAGE_URL_BASE + "\(size.rawValue)/\(asin).jpg"
	}
}