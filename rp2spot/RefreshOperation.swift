//
//  RefreshOperation.swift
//  rp2spot
//
//  Created by Brian on 27/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

class RefreshOperation: ConcurrentOperation {

	weak var target: AnyObject?
	var selector: Selector

	init(target: AnyObject, selector: Selector) {
		self.target = target
		self.selector = selector
		super.init()
	}

	override func main() {
		if isCancelled {
			state = .Finished
			return
		}
		_ = target?.perform(selector)
	}

	/**
	When the refresh operation has finished, this method will be called.
	
	Move the operation to the finished state, so that it can be removed from it's queue.
	*/
	override func cancel() {
		super.cancel()
		state = .Finished
	}
}
