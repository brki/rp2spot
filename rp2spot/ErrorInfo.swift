//
//  ErrorInfo.swift
//  rp2spot
//
//  Created by Brian on 24/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

class ErrorInfo {
	static func isRequestTimedOut(error: NSError) -> Bool {
		return error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut
	}
}