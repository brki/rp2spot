//
//  RadioParadise.swift
//  rp2spot
//
//  Created by Brian on 14/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation
import Alamofire

struct RadioParadise {

	enum ImageSize: String {
		case Small = "s"
		case Medium = "m"
		case Large = "l"
	}
	
	static func fetchPeriod(region: String, fromDate: NSDate? = nil, toDate: NSDate? = nil,
		handler: ((playedSongs: [PlayedSongData]?, error: NSError?, response: NSHTTPURLResponse?) -> Void)? = nil) -> Request {

		var params = [String: String]()
		if let from = fromDate {
			// Get the 24-hour period beginning at ``from``.
			params["start_time"] = Date.sharedInstance.toUTCString(from)
		} else if let to = toDate {
			// Get the 24-hour period ending at ``to``.
			params["end_time"] = Date.sharedInstance.toUTCString(to)
		} else {
			// Get the 24-hour period ending now.
			params["end_time"] = Date.sharedInstance.toUTCString(NSDate())
		}

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