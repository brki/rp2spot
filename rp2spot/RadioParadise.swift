//
//  RadioParadise.swift
//  rp2spot
//
//  Created by Brian on 14/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation
import Alamofire


typealias RPFetchHandler = (_ playedSongs: [PlayedSongData]?, _ error: NSError?, _ response: HTTPURLResponse?) -> Void

struct RadioParadise {

	enum ImageSize: String {
		case Small = "s"
		case Medium = "m"
		case Large = "l"
	}

	static let DEFAULT_FETCH_COUNT = 100

	static let userSettings = UserSetting.sharedInstance

	static func fetchNewer(_ region: String, newerThan: Foundation.Date, count: Int = DEFAULT_FETCH_COUNT, handler: RPFetchHandler? = nil) -> Request {
		return fetchHistory(region, date: newerThan, vectorCount: count, handler: handler)
	}

	static func fetchOlder(_ region: String, olderThan: Foundation.Date, count: Int = DEFAULT_FETCH_COUNT, handler: RPFetchHandler? = nil) -> Request {
		return fetchHistory(region, date: olderThan, vectorCount: -count, handler: handler)
	}

	/**
	Fetch history from the RP history web service.
	
	- Parameters:
	  - region: two-letter region code
	  - date: base date for history
	  - vectorCount: Int - if positive, fetch this many songs after the base date; if negative fetch abs(vectorCount) songs before the base date
	  - handler: completion handler
	*/
	static func fetchHistory(_ region: String, date: Foundation.Date, vectorCount: Int, handler: RPFetchHandler? = nil) -> Request {

		let params: [String: Any] = [
			"base_time": Date.sharedInstance.toUTCString(date),
			"count_vector": vectorCount,
		]

		let url = Constant.RADIO_PARADISE_HISTORY_URL_BASE + region + "/"

		let request = Alamofire.request(url, parameters: params).responseCollection() { (response: Response<[PlayedSongData], NSError>) in
			switch response.result {
			case .success(let playedSongs):
				handler?(playedSongs: playedSongs, error:nil, response: response.response)
			case .failure(let error):
				handler?(playedSongs: nil, error:error, response: response.response)
			}
		}
		return request
	}

	static func imageURLText(_ asin: String, size: ImageSize) -> String {
		return Constant.RADIO_PARADISE_IMAGE_URL_BASE + "\(size.rawValue)/\(asin).jpg"
	}

	static func songInfoURL(_ RPSongId: NSNumber) -> URL? {
		let URLString = Constant.RADIO_PARADISE_SONG_INFO_URL_TEMPLATE.replacingOccurrences(of: "{songid}", with: String(describing: RPSongId))
		return URL(string: URLString)
	}
}
