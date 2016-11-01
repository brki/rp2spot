//
//  HistoryDateSelectorViewController.swift
//  rp2spot
//
//  Created by Brian on 02/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

class HistoryDateSelectorViewController: UIViewController {

	var startingDate: Foundation.Date!
	var delegate: DateSelectionAcceptingProtocol!

	@IBOutlet weak var datePicker: UIDatePicker!
	@IBOutlet weak var backgroundView: UIView!

	override func viewDidLoad() {
		super.viewDidLoad()
		datePicker.date = startingDate
		datePicker.minimumDate = Constant.RADIO_PARADISE_MINIMUM_SELECTABLE_HISTORY_DATE
		datePicker.maximumDate = Foundation.Date()

		// Make the control have rounded edges and a border:
		let layer = backgroundView.layer
		let borderColor = Constant.Color.lightGrey.color().cgColor
		layer.cornerRadius = 30
		layer.borderColor = borderColor
		layer.borderWidth = 0.5

		// Add a dropshadow:
		layer.shadowColor = borderColor
		layer.shadowOpacity = 0.8
		layer.shadowRadius = 3.0
		layer.shadowOffset = CGSize(width: 2.0, height: 2.0)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
	}

	@IBAction func setDateToToday(_ sender: UIButton) {
		datePicker.date = Foundation.Date()
	}
	
	@IBAction func cancel(_ sender: UIButton) {
		dismiss()
	}

	@IBAction func OuterViewTapped(_ sender: UITapGestureRecognizer) {
		dismissNotifyingDelegateIfChanged()
	}

	func dismissNotifyingDelegateIfChanged() {
		if startingDate.compare(datePicker.date) != ComparisonResult.orderedSame {
			delegate.dateSelected(datePicker.date)
		}
		dismiss()
	}

	func dismiss() {
		self.dismiss(animated: true, completion: nil)
	}
}
