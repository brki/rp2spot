//
//  SpotifyAuthRenewalOperation.swift
//  rp2spot
//
//  Created by Brian King on 22/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

//
// The skeleton of this concurrent NSOperation subclass is based on https://gist.github.com/calebd/93fa347397cec5f88233
//

import Foundation

class SpotifyAuthRenewalOperation: NSOperation {

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

	var forceRenew: Bool
	var authCompletionHandler: ((error: NSError?) -> Void)?

	init(forceRenew: Bool, authCompletionHandler: ((error: NSError?) -> Void)? = nil) {
		self.forceRenew = forceRenew
		self.authCompletionHandler = authCompletionHandler
	}

	override func start() {
		guard !cancelled else {
			state = .Finished
			return
		}
		state = .Executing
		main()
	}

	override func main() {

		let spotify = SpotifyClient.sharedInstance
		guard forceRenew || spotify.sessionShouldBeRenewedSoon() else {
			// Force renew requested, or a session that will not expire soon already exists.
			authCompletionHandler?(error: nil)
			state = .Finished
			return
		}
		spotify.auth.renewSession(spotify.auth.session) { error, session in
			if session != nil {
				spotify.auth.session = session
			}
			self.authCompletionHandler?(error: error)
			self.state = .Finished
		}
	}
}