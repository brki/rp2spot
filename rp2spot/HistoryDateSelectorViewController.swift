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
		datePicker.minimumDate = Constant.RADIO_PARADISE_MINIMUM_HISTORY_DATE
		datePicker.maximumDate = NSDate()

		// Make the control have rounded edges and a border:
		let layer = backgroundView.layer
		layer.cornerRadius = 30
		layer.borderColor = UIColor.blackColor().CGColor
		layer.borderWidth = 1.5
	}

	override func viewDidAppear(animated: Bool) {
		super.viewDidAppear(animated)
	}

	@IBAction func dateSelected(sender: UIButton) {
		delegate.dateSelected(datePicker.date)
		dismissViewControllerAnimated(true, completion: nil)
	}

	@IBAction func setDateToToday(sender: UIButton) {
		datePicker.date = NSDate()
	}
	
	@IBAction func cancel(sender: UIButton) {
		dismissViewControllerAnimated(true, completion: nil)
	}
}