//
//  String+extension.swift
//  rp2spot
//
//  Created by Brian on 19/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

extension String
{
	func trim() -> String
	{
		return self.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
	}
}