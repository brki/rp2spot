//
//  ConcurrentOperation.swift
//  rp2spot
//
//  Created by Brian King on 24/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

//
// The skeleton of this concurrent NSOperation subclass is based on https://gist.github.com/calebd/93fa347397cec5f88233
//
class ConcurrentOperation: NSOperation {
	enum State: String {
		case Ready = "isReady"
		case Executing = "isExecuting"
		case Finished = "isFinished"
	}

	override var asynchronous: Bool {
		return true
	}

	var state = State.Ready {
		willSet {
			willChangeValueForKey(newValue.rawValue)
			willChangeValueForKey(state.rawValue)
		}
		didSet {
			didChangeValueForKey(oldValue.rawValue)
			didChangeValueForKey(state.rawValue)
		}
	}

	override var ready: Bool {
		return super.ready && state == .Ready
	}

	override var executing: Bool {
		return state == .Executing
	}

	override var finished: Bool {
		return state == .Finished
	}

	func wasCancelledBeforeStarting() {
		// Override as necessary
	}

	override func start() {
		guard !cancelled else {
			state = .Finished
			wasCancelledBeforeStarting()
			return
		}
		state = .Executing
		main()
	}
}