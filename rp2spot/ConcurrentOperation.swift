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
class ConcurrentOperation: Operation {
	enum State: String {
		case Ready = "isReady"
		case Executing = "isExecuting"
		case Finished = "isFinished"
	}

	override var isAsynchronous: Bool {
		return true
	}

	var state = State.Ready {
		willSet {
			willChangeValue(forKey: newValue.rawValue)
			willChangeValue(forKey: state.rawValue)
		}
		didSet {
			didChangeValue(forKey: oldValue.rawValue)
			didChangeValue(forKey: state.rawValue)
		}
	}

	override var isReady: Bool {
		return super.isReady && state == .Ready
	}

	override var isExecuting: Bool {
		return state == .Executing
	}

	override var isFinished: Bool {
		return state == .Finished
	}

	func wasCancelledBeforeStarting() {
		// Override as necessary
	}

	override func start() {
		guard !isCancelled else {
			state = .Finished
			wasCancelledBeforeStarting()
			return
		}
		state = .Executing
		main()
	}
}
