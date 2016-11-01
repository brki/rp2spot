//
//  Utilities.swift
//  rp2spot
//
//  Created by Brian on 24/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation


class Utility {

	static func presentAlert(_ title: String?, message: String?, ommitOKButton: Bool = false) {

		let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
		if !ommitOKButton {
			alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
		}

		presentAlertControllerOnFrontController(alertController)
	}

	static func presentAlertControllerOnFrontController(_ alertController: UIAlertController, iteration: Int = 0) {

		guard iteration < 8 else {
			print("presentAlertControllerOnFrontController: After 8 iterations, still not able to get a stable front view controller, giving up.")
			return
		}

		DispatchQueue.main.async {
			guard var controller = UIApplication.shared.keyWindow?.rootViewController else {
				print("presentAlertControllerOnFrontController: Unable to get rootViewController")
				return
			}

			while let presentedController = controller.presentedViewController {
				controller = presentedController
			}

			// If view controller is being dismissed or presented, delay presentation a bit.
			if controller.isBeingDismissed || controller.isBeingPresented {
				DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(0.37 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)) {
					presentAlertControllerOnFrontController(alertController, iteration: iteration + 1)
				}
				return
			}

			controller.present(alertController, animated: true, completion: nil)
		}
	}
}
