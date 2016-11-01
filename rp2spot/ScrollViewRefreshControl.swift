//
//  ScrollViewRefreshControl.swift
//  rp2spot
//
//  Created by Brian on 27/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

class ScrollViewRefreshControl {

	var view: RefreshControlView!
	var position: RefreshControlView.Position
	weak var target: AnyObject?
	var refreshAction: Selector
	var activityLabelReadyToRefreshText: String?
	var activityLabelCurrentlyRefreshingText: String?
	// How far beyond the table view limit must the first / last cell be pulled before the refresh operation is triggered:
	lazy var overPullTriggerHeight: CGFloat = self.refreshingViewHeight + 25
	lazy var refreshingViewHeight: CGFloat = self.view.bounds.height
	var refreshViewAnimationDuration = 0.3
	var enabled = true {
		didSet {
			if enabled {
				view.activityIndicator.color = Constant.Color.spotifyGreen.color()
			} else {
				view.activityIndicator.color = Constant.Color.lightGrey.color()
			}
			view.activityLabel.isHidden = !enabled
		}
	}
	var hidden = false {
		didSet {
			if hidden != oldValue {
				view.isHidden = hidden
			}
		}
	}

	lazy var operationQueue: OperationQueue = {
		let queue = OperationQueue()
		queue.maxConcurrentOperationCount = 1
		return queue
	}()

	var refreshing: Bool {
		return operationQueue.operations.count > 0
	}

	init(position: RefreshControlView.Position,
	     view: RefreshControlView,
	     target: AnyObject,
	     refreshAction: Selector,
	     readyToRefreshText: String? = "Pull to refresh",
	     currentlyRefreshingText: String? = "Refreshing" ) {

		self.position = position
		self.view = view
		self.target = target
		self.refreshAction = refreshAction
		self.activityLabelReadyToRefreshText = readyToRefreshText
		self.activityLabelCurrentlyRefreshingText = currentlyRefreshingText

		self.view.activityLabel?.text = self.activityLabelReadyToRefreshText
	}


	func didEndDragging(_ scrollView: UIScrollView) {
		// Ignore if not enabled or refresh operation is already in progress.
		guard enabled && !refreshing else {
			return
		}

		// Ignore if not pulling far enough past the beginning / end of the table view.
		guard refreshShouldBeTriggered(scrollView) else {
			return
		}

		// Ignore if the sender has been de-allocated.
		guard let actionTarget = target else {
			return
		}

		// Start a refresh operation.
		let operation = RefreshOperation(target: actionTarget, selector: refreshAction)
		operationQueue.addOperation(operation)

		let inset = adjustedContentInset(scrollView)
		async_main {
			self.view.activityIndicator?.startAnimating()
			UIView.animate(withDuration: self.refreshViewAnimationDuration, animations: {
				scrollView.contentInset = inset
				self.view.activityLabel?.text = self.activityLabelCurrentlyRefreshingText
			}) 
		}
	}

	func refreshShouldBeTriggered(_ scrollView: UIScrollView) -> Bool {
		let pullHeight = position == .bottom ? bottomPullHeight(scrollView) : topPullHeight(scrollView)
		return pullHeight >= overPullTriggerHeight
	}

	func bottomPullHeight(_ scrollView: UIScrollView) -> CGFloat {
		return scrollView.contentOffset.y + scrollView.frame.size.height -  (scrollView.contentSize.height + scrollView.contentInset.bottom)
	}

	func topPullHeight(_ scrollView: UIScrollView) -> CGFloat {
		return scrollView.contentInset.top - scrollView.contentOffset.y
	}

	func adjustedContentInset(_ scrollView: UIScrollView) -> UIEdgeInsets {
		let adjustment = refreshing ? refreshingViewHeight : -refreshingViewHeight

		return UIEdgeInsetsMake(
			position == .top ? scrollView.contentInset.top + adjustment : scrollView.contentInset.top,
			scrollView.contentInset.left,
			position == .bottom ? scrollView.contentInset.bottom + adjustment : scrollView.contentInset.bottom,
			scrollView.contentInset.right
		)
	}

	func didFinishRefreshing(_ scrollView: UIScrollView) {
		guard refreshing else {
			return
		}

		operationQueue.cancelAllOperations()

		let inset = adjustedContentInset(scrollView)
		async_main {
			self.view.activityIndicator?.stopAnimating()
			UIView.animate(withDuration: self.refreshViewAnimationDuration,
				animations: {
					scrollView.contentInset = inset
				},
				completion: { finished in
					self.view.activityLabel?.text = self.activityLabelReadyToRefreshText
			})
		}
	}
}
