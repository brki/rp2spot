//
//  UIGestureRecognizer+extension.swift
//  rp2spot
//
//  Created by Brian on 08/05/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

extension UIGestureRecognizer {

	/**
	Disable and re-enable the gesture recognizer to cancel any current active gesture.
	*/
	func cancel() {
		if isEnabled {
			isEnabled = false
			isEnabled = true
		}
	}
}
