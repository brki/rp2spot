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
		case bottom = 0, top
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
		guard let position = Position.init(rawValue: aDecoder.decodeInteger(forKey: "refreshControlPosition")) else {
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
		activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
		activityIndicator.isHidden = false
		activityIndicator.hidesWhenStopped = false
		activityIndicator.frame = CGRect(
			x: self.bounds.midX - activityIndicator.frame.width / 2.0,
			y: refreshControlPosition == .top ? 10 : self.bounds.height - 10 - activityIndicator.bounds.height,
			width: activityIndicator.bounds.width,
			height: activityIndicator.bounds.height
		).integral
		activityIndicator.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]

		self.addSubview(activityIndicator)
	}

	func setupLabel() {
		activityLabel = UILabel()
		activityLabel.textAlignment = .center
		let labelHeight = CGFloat(25)
		activityLabel.frame = CGRect(
			x: 0,
			y: refreshControlPosition == .top ? 50 : self.bounds.height - 50 - labelHeight,
			width: self.bounds.width,
			height: labelHeight
		).integral
		activityLabel.autoresizingMask = .flexibleWidth
		activityLabel.text = "Pull to refresh"
		self.addSubview(activityLabel)
	}
}
