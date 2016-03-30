//
//  RefreshControlView.swift
//  rp2spot
//
//  Created by Brian on 27/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

class RefreshControlView: UIView {

	enum Position: Int {
		case Bottom = 0, Top
	}

	var activityIndicator: UIActivityIndicatorView!
	var activityLabel: UILabel!
	var refreshControlPosition: Position

	init(position: Position, frame: CGRect) {
		refreshControlPosition = position
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder aDecoder: NSCoder) {
		guard let position = Position.init(rawValue: aDecoder.decodeIntegerForKey("refreshControlPosition")) else {
			return nil
		}
		refreshControlPosition = position
		super.init(coder: aDecoder)
		commonInit()
	}

	func commonInit() {
		setupActivityIndicator()
		setupLabel()
	}

	func setupActivityIndicator() {
		activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .Gray)
		activityIndicator.hidden = false
		activityIndicator.hidesWhenStopped = false
		activityIndicator.frame = CGRectMake(
			self.bounds.midX - activityIndicator.frame.width / 2.0,
			refreshControlPosition == .Top ? 10 : self.bounds.height - 10 - activityIndicator.bounds.height,
			activityIndicator.bounds.width,
			activityIndicator.bounds.height
		).integral
		activityIndicator.autoresizingMask = [.FlexibleLeftMargin, .FlexibleRightMargin]

		self.addSubview(activityIndicator)
	}

	func setupLabel() {
		activityLabel = UILabel()
		activityLabel.textAlignment = .Center
		let labelHeight = CGFloat(25)
		activityLabel.frame = CGRectMake(
			0,
			refreshControlPosition == .Top ? 50 : self.bounds.height - 50 - labelHeight,
			self.bounds.width,
			labelHeight
		).integral
		activityLabel.autoresizingMask = .FlexibleWidth
		activityLabel.text = "Pull to refresh"
		self.addSubview(activityLabel)
	}
}
