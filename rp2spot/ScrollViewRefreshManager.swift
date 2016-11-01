//
//  ScrollViewViewRefreshManager.swift
//  rp2spot
//
//  Created by Brian on 27/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

class ScrollViewRefreshManager {

	let backgroundView = UIView()
	var topRefreshControl: ScrollViewRefreshControl?
	var bottomRefreshControl: ScrollViewRefreshControl?
	var refreshControlViewHeight = CGFloat(100)

	var currentlyRefreshing: Bool {
		return topRefreshControl?.refreshing == true || bottomRefreshControl?.refreshing == true || false
	}

	var inactiveControlsEnabled = true {
		didSet {
			if let topControl = topRefreshControl, !topControl.refreshing {
				topControl.enabled = inactiveControlsEnabled
			}
			if let bottomControl = bottomRefreshControl, !bottomControl.refreshing {
				bottomControl.enabled = inactiveControlsEnabled
			}
		}
	}

	init(tableView: UITableView) {
		tableView.backgroundView = backgroundView
	}

	init(collectionView: UICollectionView) {
		collectionView.backgroundView = backgroundView
	}

	func addRefreshControl(_ position: RefreshControlView.Position, target: AnyObject, refreshAction: Selector, readyToRefreshText: String? = "Pull to refresh", currentlyRefreshingText: String? = "Refreshing ...") {

		let refreshControlView = viewForPosition(position)
		backgroundView.addSubview(refreshControlView)
		let refreshControl = ScrollViewRefreshControl(
			position: position,
			view: refreshControlView,
			target: target,
			refreshAction: refreshAction,
			readyToRefreshText: readyToRefreshText,
			currentlyRefreshingText: currentlyRefreshingText
		)
		refreshControl.view.activityLabel.textColor = Constant.Color.spotifyGreen.color()

		// Make the control initially hidden, so that it won't be visible underneath
		// a table view cell when the cell is selected.
		refreshControl.hidden = true

		if position == .top {
			topRefreshControl = refreshControl
		} else {
			bottomRefreshControl = refreshControl
		}
	}

	func viewForPosition(_ position: RefreshControlView.Position) -> RefreshControlView {
		let frame = CGRect(
			x: 0,
			y: position == .top ? 0 : backgroundView.bounds.height - refreshControlViewHeight,
			width: backgroundView.bounds.width,
			height: refreshControlViewHeight
		)
		let refreshControlView = RefreshControlView(position: position, frame: frame)

		if position == .top {
			refreshControlView.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
		} else {
			refreshControlView.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
		}

		return refreshControlView
	}

	/**
	This is the decision point for whether or not a refresh operation
	should be started (e.g. if the pull past the limits has exceeded
	the threshoold).

	If a refresh was not started, then the control should be hidden.
	*/
	func didEndDragging(_ scrollView: UIScrollView) {
		// If either control is currently refreshing, do not pass the message through to them.
		guard !currentlyRefreshing else {
			return
		}
		if let topControl = topRefreshControl {
			topControl.didEndDragging(scrollView)
			if !topControl.refreshing {
				topControl.hidden = true
			}
		}
		if let bottomControl = bottomRefreshControl {
			bottomControl.didEndDragging(scrollView)
			if !bottomControl.refreshing {
				bottomControl.hidden = true
			}
		}
	}

	/**
	Dragging has started; the controls should be visible if
	the user pulls the table view beyond it's end.
	*/
	func willBeginDragging(_ scrollView: UIScrollView) {
		topRefreshControl?.hidden = false
		bottomRefreshControl?.hidden = false
	}

	/**
	Scrolling has stopped.  This can be one of the following situations:

	- The user has started a refresh.  In this case the control should remain
	  visible.
	- The user has simply stopped scrolling.  The control should be hidden so
	  that it is not visible underneath a table view cell when it is selected.
	*/
	func didEndDecelerating(_ scrollView: UIScrollView) {
		if let topControl = topRefreshControl {
			if !topControl.refreshing {
				topControl.hidden = true
			}
		}
		if let bottomControl = bottomRefreshControl {
			if !bottomControl.refreshing {
				bottomControl.hidden = true
			}
		}
	}
}
