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

	init(tableView: UITableView) {
		tableView.backgroundView = backgroundView
	}

	init(collectionView: UICollectionView) {
		collectionView.backgroundView = backgroundView
	}

	func addRefreshControl(position: RefreshControlView.Position, target: AnyObject, refreshAction: Selector, readyToRefreshText: String? = "Pull to refresh", currentlyRefreshingText: String? = "Refreshing ...") {

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

		if position == .Top {
			topRefreshControl = refreshControl
		} else {
			bottomRefreshControl = refreshControl
		}
	}

	func viewForPosition(position: RefreshControlView.Position) -> RefreshControlView {
		let frame = CGRectMake(
			0,
			position == .Top ? 0 : backgroundView.bounds.height - refreshControlViewHeight,
			backgroundView.bounds.width,
			refreshControlViewHeight
		)
		let refreshControlView = RefreshControlView(position: position, frame: frame)

		if position == .Top {
			refreshControlView.autoresizingMask = [.FlexibleWidth, .FlexibleBottomMargin]
		} else {
			refreshControlView.autoresizingMask = [.FlexibleWidth, .FlexibleTopMargin]
		}

		return refreshControlView
	}

	func didEndDragging(scrollView: UIScrollView) {
		topRefreshControl?.didEndDragging(scrollView)
		bottomRefreshControl?.didEndDragging(scrollView)
	}
}