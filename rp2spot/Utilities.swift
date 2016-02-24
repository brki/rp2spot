//
//  Utilities.swift
//  rp2spot
//
//  Created by Brian on 24/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

func async_main(block: () -> Void) {
	dispatch_async(dispatch_get_main_queue(), block)
}

class Utility {

	static func presentAlert(title: String?, message: String?) {

		let alertController = UIAlertController(title: title, message: message, preferredStyle: .Alert)
		alertController.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))

		presentAlertControllerOnFrontController(alertController)
	}

	static func presentAlertControllerOnFrontController(alertController: UIAlertController, var iteration: Int = 0) {
		iteration += 1
		guard iteration <= 8 else {
			print("presentAlertControllerOnFrontController: After 8 iterations, still not able to get a stable front view controller, giving up.")
			return
		}

		async_main {
			guard var controller = UIApplication.sharedApplication().keyWindow?.rootViewController else {
				print("presentAlertControllerOnFrontController: Unable to get rootViewController")
				return
			}

			while let presentedController = controller.presentedViewController {
				controller = presentedController
			}

			// If view controller is being dismissed or presented, delay presentation a bit.
			if controller.isBeingDismissed() || controller.isBeingPresented() {
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(0.37 * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
					presentAlertControllerOnFrontController(alertController, iteration: iteration)
				}
				return
			}

			controller.presentViewController(alertController, animated: true, completion: nil)
		}
	}
}