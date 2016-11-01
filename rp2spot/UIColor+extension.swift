//
//  UIColor+extension.swift
//  rp2spot
//
//  Created by Brian on 23/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

extension UIColor {

	/**
	Create a UIColor passed a hex RGB value and alpha value.

	Based on https://gist.github.com/mbigatti/c6be210a6bbc0ff25972 .
	*/
	class func colorWithRGB(_ rgbValue : UInt, alpha : CGFloat = 1.0) -> UIColor {
		let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255
		let green = CGFloat((rgbValue & 0xFF00) >> 8) / 255
		let blue = CGFloat(rgbValue & 0xFF) / 255

		return UIColor(red: red, green: green, blue: blue, alpha: alpha)
	}
}
