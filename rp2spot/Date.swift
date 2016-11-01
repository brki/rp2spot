//
//  Date.swift
//  rp2spot
//
//  Created by Brian on 14/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation


class Date {
	static let sharedInstance = Date()
	
	static let RADIO_PARADISE_DATETIME_FORMAT = "yyyy-MM-dd'T'HH:mm:ssZ"

	// A UTC date formatter that has the format expected by the radio paradise history endpoint.
	lazy var UTCDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = RADIO_PARADISE_DATETIME_FORMAT
		formatter.timeZone = TimeZone(identifier: "UTC")
		return formatter
	}()

	// A UTC date formatter that can convert the  format produced by the radio paradise history endpoint into a NSDate object.
	lazy var RPDateParser: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = RADIO_PARADISE_DATETIME_FORMAT
		// According to Apple recommendations, always use the en_US_POSIX locale when parsing dates:
		formatter.locale = Locale(identifier: "en_US_POSIX")
		return formatter
	}()

	lazy var calendar = Calendar.current

	func toUTCString(_ date: Foundation.Date) -> String {
		return UTCDateFormatter.string(from: date)
	}

	func dateFromRPDateString(_ date: String) -> Foundation.Date? {
		return RPDateParser.date(from: date)
	}

	// Returns a compact representation of the date / time.
	func shortLocalizedString(_ date: Foundation.Date) -> String {
		return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
	}

	func oneDayAgo() -> Foundation.Date {
		// First try the correct way:
		if let date = (calendar as NSCalendar).date(byAdding: NSCalendar.Unit.day, value: -1, to: Foundation.Date(), options: NSCalendar.Options(rawValue: 0)) {
			return date
		} else {
			// If that for some reason fails, return the 24 hours ago time:
			return Foundation.Date(timeInterval: -24 * 60 * 60, since: Foundation.Date())
		}
	}

	func timeWithHourDifference(_ date: Foundation.Date, hours: Double) -> Foundation.Date {
		return Foundation.Date(timeInterval: hours * 60 * 60, since: date)
	}
}
