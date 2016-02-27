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
	lazy var UTCDateFormatter: NSDateFormatter = {
		let formatter = NSDateFormatter()
		formatter.dateFormat = RADIO_PARADISE_DATETIME_FORMAT
		formatter.timeZone = NSTimeZone(name: "UTC")
		return formatter
	}()

	// A UTC date formatter that can convert the  format produced by the radio paradise history endpoint into a NSDate object.
	lazy var RPDateParser: NSDateFormatter = {
		let formatter = NSDateFormatter()
		formatter.dateFormat = RADIO_PARADISE_DATETIME_FORMAT
		// According to Apple recommendations, always use the en_US_POSIX locale when parsing dates:
		formatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")
		return formatter
	}()

	lazy var calendar = NSCalendar.currentCalendar()

	func toUTCString(date: NSDate) -> String {
		return UTCDateFormatter.stringFromDate(date)
	}

	func dateFromRPDateString(date: String) -> NSDate? {
		return RPDateParser.dateFromString(date)
	}

	// Returns a compact representation of the date / time.
	func shortLocalizedString(date: NSDate) -> String {
		return NSDateFormatter.localizedStringFromDate(date, dateStyle: .ShortStyle, timeStyle: .ShortStyle)
	}

	func oneDayAgo() -> NSDate {
		// First try the correct way:
		if let date = calendar.dateByAddingUnit(NSCalendarUnit.Day, value: -1, toDate: NSDate(), options: NSCalendarOptions(rawValue: 0)) {
			return date
		} else {
			// If that for some reason fails, return the 24 hours ago time:
			return NSDate(timeInterval: -24 * 60 * 60, sinceDate: NSDate())
		}
	}

	func timeWithHourDifference(date: NSDate, hours: Double) -> NSDate {
		return NSDate(timeInterval: hours * 60 * 60, sinceDate: date)
	}

}