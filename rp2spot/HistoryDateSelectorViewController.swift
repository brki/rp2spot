//
//  HistoryDateSelectorViewController.swift
//  rp2spot
//
//  Created by Brian on 02/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

class HistoryDateSelectorViewController: UIViewController {

	var startingDate: NSDate!
	var delegate: DateSelectionAcceptingProtocol!

	@IBOutlet weak var datePicker: UIDatePicker!
	@IBOutlet weak var backgroundView: UIView!

	override func viewDidLoad() {
		super.viewDidLoad()
		datePicker.date = startingDate
		datePicker.minimumDate = Constant.RADIO_PARADISE_MINIMUM_SELECTABLE_HISTORY_DATE
		datePicker.maximumDate = NSDate()

		// Make the control have rounded edges and a border:
		let layer = backgroundView.layer
		let borderColor = Constant.Color.LightGrey.color().CGColor
		layer.cornerRadius = 30
		layer.borderColor = borderColor
		layer.borderWidth = 0.5

		// Add a dropshadow:
		layer.shadowColor = borderColor
		layer.shadowOpacity = 0.8
		layer.shadowRadius = 3.0
		layer.shadowOffset = CGSizeMake(2.0, 2.0)
	}

	override func viewDidAppear(animated: Bool) {
		super.viewDidAppear(animated)
	}

	@IBAction func setDateToToday(sender: UIButton) {
		datePicker.date = NSDate()
	}
	
	@IBAction func cancel(sender: UIButton) {
		dismiss()
	}

	@IBAction func OuterViewTapped(sender: UITapGestureRecognizer) {
		dismissNotifyingDelegateIfChanged()
	}

	func dismissNotifyingDelegateIfChanged() {
		if startingDate.compare(datePicker.date) != NSComparisonResult.OrderedSame {
			delegate.dateSelected(datePicker.date)
		}
		dismiss()
	}

	func dismiss() {
		dismissViewControllerAnimated(true, completion: nil)
	}
}