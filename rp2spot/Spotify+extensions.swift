//
//  Spotify+extensions.swift
//  rp2spot
//
//  Created by Brian on 19.03.17.
//  Copyright © 2017 truckin'. All rights reserved.
//

extension SPTBitrate: CustomStringConvertible {
	public var description: String {
		switch self {
		case .low:
			return "low"
		case .normal:
			return "normal"
		case .high:
			return "high"
		}
	}
}
