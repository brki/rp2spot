//
//  ConcurrentOperation.swift
//  rp2spot
//
//  Created by Brian King on 24/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//


// This is based on https://gist.github.com/calebd/93fa347397cec5f88233


/// An abstract class that makes building simple asynchronous operations easy.
/// Subclasses must implement `execute()` to perform any work and call
/// `finish()` when they are done. All `NSOperation` work will be handled
/// automatically.
open class ConcurrentOperation: Foundation.Operation {

	// MARK: - Properties
	private let stateQueue = DispatchQueue(
		label: "com.calebd.operation.state",
		attributes: .concurrent)

	private var rawState = OperationState.ready

	@objc private dynamic var state: OperationState {
		get {
			return stateQueue.sync(execute: { rawState })
		}
		set {
			willChangeValue(forKey: "state")
			stateQueue.sync(
				flags: .barrier,
				execute: { rawState = newValue })
			didChangeValue(forKey: "state")
		}
	}

	public final override var isReady: Bool {
		return state == .ready && super.isReady
	}

	public final override var isExecuting: Bool {
		return state == .executing
	}

	public final override var isFinished: Bool {
		return state == .finished
	}


	// MARK: - NSObject
	@objc private dynamic class func keyPathsForValuesAffectingIsReady() -> Set<String> {
		return ["state"]
	}

	@objc private dynamic class func keyPathsForValuesAffectingIsExecuting() -> Set<String> {
		return ["state"]
	}

	@objc private dynamic class func keyPathsForValuesAffectingIsFinished() -> Set<String> {
		return ["state"]
	}


	// MARK: - Foundation.Operation
	public override final func start() {
		super.start()

		if isCancelled {
			wasCancelledBeforeStarting()
			finish()
			return
		}

		state = .executing
		execute()
	}

	open func wasCancelledBeforeStarting() {}

	// MARK: - Public
	/// Subclasses must implement this to perform their work and they must not
	/// call `super`. The default implementation of this function throws an
	/// exception.
	open func execute() {
		fatalError("Subclasses must implement `execute`.")
	}

	/// Call this function after any work is done or after a call to `cancel()`
	/// to move the operation into a completed state.
	public final func finish() {
		state = .finished
	}

	func firstCancelledDependency() -> Operation? {
		for operation in dependencies {
			if operation.isCancelled {
				return operation
			}
		}
		return nil
	}
}

@objc private enum OperationState: Int {
	case ready
	case executing
	case finished
}
