//
//  ScrollViewRefreshControl.swift
//  rp2spot
//
//  Created by Brian on 27/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

class ScrollViewRefreshControl {

	enum Style {
		case Bottom, Top
	}

	var style: Style
	weak var target: AnyObject?
	var refreshAction: Selector
	weak var activityIndicator: UIActivityIndicatorView?
	weak var activityLabel: UILabel?

	var activityLabelReadyToRefreshText: String?
	var activityLabelCurrentlyRefreshingText: String?

	// How far beyond the table view limit must the first / last cell be pulled before the refresh operation is triggered:
	var overPullTriggerHeight = CGFloat(125)
	var refreshingViewHeight = CGFloat(100)
	var refreshViewAnimationDuration = 0.3

	var refreshing: Bool {
		return operationQueue.operations.count > 0
	}

	init(style: Style,
	     target: AnyObject,
	     refreshAction: Selector,
	     activityIndicator: UIActivityIndicatorView? = nil,
	     activityLabel: UILabel? = nil,
	     readyToRefreshText: String? = "Pull to refresh",
	     currentlyRefreshingText: String? = "Refreshing" ) {

		self.style = style
		self.target = target
		self.refreshAction = refreshAction
		self.activityIndicator = activityIndicator
		self.activityLabel = activityLabel
		self.activityLabelReadyToRefreshText = readyToRefreshText
		self.activityLabelCurrentlyRefreshingText = currentlyRefreshingText

		self.activityLabel?.text = self.activityLabelReadyToRefreshText
	}

	lazy var operationQueue: NSOperationQueue = {
		let queue = NSOperationQueue()
		queue.maxConcurrentOperationCount = 1
		return queue
	}()

	func didEndDragging(scrollView: UIScrollView) {
		// Ignore if a refresh operation is already in progress.
		guard !refreshing else {
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
			self.activityIndicator?.startAnimating()
			UIView.animateWithDuration(self.refreshViewAnimationDuration) {
				scrollView.contentInset = inset
				self.activityLabel?.text = self.activityLabelCurrentlyRefreshingText
			}
		}

	}

	func refreshShouldBeTriggered(scrollView: UIScrollView) -> Bool {
		let pullHeight = style == .Bottom ? bottomPullHeight(scrollView) : topPullHeight(scrollView)
		return pullHeight >= overPullTriggerHeight
	}

	func bottomPullHeight(scrollView: UIScrollView) -> CGFloat {
		return scrollView.contentOffset.y + scrollView.frame.size.height -  (scrollView.contentSize.height + scrollView.contentInset.bottom)
	}

	func topPullHeight(scrollView: UIScrollView) -> CGFloat {
		return scrollView.contentInset.top - scrollView.contentOffset.y
	}

	func adjustedContentInset(scrollView: UIScrollView) -> UIEdgeInsets {
		let adjustment = refreshing ? refreshingViewHeight : -refreshingViewHeight

		return UIEdgeInsetsMake(
			style == .Top ? scrollView.contentInset.top + adjustment : scrollView.contentInset.top,
			scrollView.contentInset.left,
			style == .Bottom ? scrollView.contentInset.bottom + adjustment : scrollView.contentInset.bottom,
			scrollView.contentInset.right
		)
	}


	func didFinishRefreshing(scrollView: UIScrollView) {
		guard refreshing else {
			return
		}

		operationQueue.cancelAllOperations()

		let inset = adjustedContentInset(scrollView)
		async_main {
			self.activityIndicator?.stopAnimating()
			UIView.animateWithDuration(self.refreshViewAnimationDuration) {
				scrollView.contentInset = inset
				self.activityLabel?.text = self.activityLabelReadyToRefreshText
			}
		}
	}
}