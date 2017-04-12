//
//  SpotifyAudioController.swift
//  rp2spot
//
//  Created by Brian on 26.03.17.
//  Copyright © 2017 truckin'. All rights reserved.
//

import Foundation
import CleanroomLogger
import Reachability


class LoginOperation: ConcurrentOperation, ErrorRecordingOperation {
	var error: NSError? = nil
	var loginRequestTime: Foundation.Date?
	var isObservingNotification = false

	override func execute() {
		// If any dependency was cancelled, cancel this operation too.
		if let cancelledOp = firstCancelledDependency() {
			if let op = cancelledOp as? ErrorRecordingOperation {
				error = op.error
			} else {
				error = SpotifyAudioController.SACError.dependentOperationCancelled.asNSError()
			}
			cancel()
		}
		guard SpotifyAudioController.sharedInstance.auth.session == nil else {
			finish()
			return
		}
		loginRequestTime = Foundation.Date()

		// Register to be notified when the session is updated.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(self.spotifySessionUpdated(_:)),
			name: NSNotification.Name(rawValue: SpotifyClient.SESSION_UPDATE_NOTIFICATION),
			object: nil)
		isObservingNotification = true

		UIApplication.shared.openURL(SpotifyClient.sharedInstance.auth.spotifyWebAuthenticationURL())
	}

	override func cancel() {
		stopObservingNotification()
		super.cancel()
		finish()
	}

	func spotifySessionUpdated(_ notification: NSNotification) {
		stopObservingNotification()
		finish()
	}

	func stopObservingNotification() {
		if isObservingNotification {
			isObservingNotification = false
			NotificationCenter.default.removeObserver(self)
		}
	}
}

class EnsureFreshSession: ConcurrentOperation, ErrorRecordingOperation {
	var error: NSError? = nil
	let refreshSessionTimeoutBuffer = TimeInterval(60.0 * 10)  // 10 minutes

	override func execute() {
		// If any dependency was cancelled, cancel this operation too.
		if let cancelledOp = firstCancelledDependency() {
			if let op = cancelledOp as? ErrorRecordingOperation {
				error = op.error
			} else {
				error = SpotifyAudioController.SACError.dependentOperationCancelled.asNSError()
			}
			cancel()
		}

		let auth = SpotifyAudioController.sharedInstance.auth
		guard let session = auth.session else {
			error = SpotifyAudioController.SACError.noValidSession.asNSError()
			cancel()
			return
		}

		guard !session.isValid() || sessionShouldBeRenewedSoon(session: session) else {
			finish()
			return
		}

		auth.renewSession(session) { error, session in
			if !self.isCancelled {
				if session != nil {
					SpotifyAudioController.sharedInstance.auth.session = session
				}
				if let err = error as NSError? {
					self.error = err
				}
			}
			self.finish()
		}
	}

	/**
	Checks if the session should be refreshed.

	Will return true if the session is invalid or is nearing it's expiration time.
	*/
	func sessionShouldBeRenewedSoon(session: SPTSession) -> Bool {
		let expirationDateMinusBuffer = Foundation.Date(timeInterval: -refreshSessionTimeoutBuffer, since: session.expirationDate)
		return (expirationDateMinusBuffer as NSDate).earlierDate(Foundation.Date()) == expirationDateMinusBuffer
	}
}


class StopPlaybackOperation: ConcurrentOperation, ErrorRecordingOperation {
	var error: NSError? = nil
	override func execute() {
		if let cancelledOp = firstCancelledDependency() {
			if let op = cancelledOp as? ErrorRecordingOperation {
				error = op.error
			} else {
				error = SpotifyAudioController.SACError.dependentOperationCancelled.asNSError()
			}
			cancel()
			finish()
		}

		guard let player = SpotifyAudioController.sharedInstance.player else {
			error = SpotifyAudioController.SACError.noPlayerAvailable.asNSError()
			cancel()
			finish()
			return
		}
		guard player.playbackState.isPlaying else {
			finish()
			return
		}

		player.setIsPlaying(false) { error in
			if !self.isCancelled {
				if error != nil {
					self.error = error! as NSError
					self.cancel()
				}
			}
			self.finish()
		}
	}
}

class LogoutOperation: ConcurrentOperation, ErrorRecordingOperation {
	var error: NSError? = nil
	var isObservingNotification = false

	override func execute() {
		if let cancelledOp = firstCancelledDependency() {
			if let op = cancelledOp as? ErrorRecordingOperation {
				error = op.error
			} else {
				error = SpotifyAudioController.SACError.dependentOperationCancelled.asNSError()
			}
			cancel()
		}
		guard let player = SpotifyAudioController.sharedInstance.player else {
			error = SpotifyAudioController.SACError.noPlayerAvailable.asNSError()
			cancel()
			return
		}
		guard player.loggedIn else {
			finish()
			return
		}
		isObservingNotification = true
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(self.loggedOut(_:)),
			name: NSNotification.Name(rawValue: SpotifyAudioController.NOTIFICATION_LOGGED_OUT),
			object: nil)

		player.logout()
	}

	override func cancel() {
		stopObservingNotification()
		super.cancel()
		finish()
	}

	func loggedOut(_ notification: NSNotification) {
		stopObservingNotification()
		finish()
	}

	func stopObservingNotification() {
		if isObservingNotification {
			isObservingNotification = false
			NotificationCenter.default.removeObserver(self)
		}
	}
}

//class PlayOperation: ConcurrentOperation {
//
//
//	override func execute() {
//		let spotify = SpotifyClient.sharedInstance
//		guard spotify.sessionShouldBeRenewedSoon() else {
//			// Force renew requested, or a session that will not expire soon already exists.
//			authCompletionHandler?(nil)
//			finish()
//			return
//		}
//		spotify.auth.renewSession(spotify.auth.session) { error, session in
//			if !self.isCancelled {
//				if session != nil {
//					spotify.auth.session = session
//				}
//				self.authCompletionHandler?(error as NSError?)
//			}
//			self.finish()
//		}
//
//
//
//		let spotify = SpotifyClient.sharedInstance
//		spotify.loginOrRenewSession { willTriggerLogin, sessionValid, error in
//			if self.isCancelled {
//				return
//			}
//			guard sessionValid else {
//				// TODO: how to communicate this to initial caller?
//				Log.warning?.message("Unable to renew session in PlayOperation: willTriggerLogin: \(willTriggerLogin), error: \(error)")
//				return
//			}
//			guard let player = spotify.player else {
//				// TODO: how to communicate this to initial caller?
//				Log.warning?.message("startPlaying: no player available")
//				return
//			}
//
//			player.setIsPlaying(true) { error in
//				if self.isCancelled {
//					return
//				}
//				if let err = error {
//					Utility.presentAlert("Unable to start playing", message: err.localizedDescription)
//					return
//				}
//			}
//		}
//	}
//}


class SpotifyAudioController: NSObject {

	static let NOTIFICATION_LOGGED_OUT = "SpotifyAudioController.loggedOut"

	enum SACError: Int {
		case
		noPlaylist = 1,
		noCurrentTrack = 2,
		noPlayerAvailable = 3,
		dependentOperationCancelled = 4,
		noValidSession = 5

		func asNSError() -> NSError {
			let domain = "rp2spot.SpotifyAudioController"
			
			switch self {
			case .noPlaylist:
				return NSError(
					domain: domain,
					code: self.rawValue,
					userInfo: [
						NSLocalizedDescriptionKey: "The audio controller currently has no playlist",
						NSLocalizedFailureReasonErrorKey: "playlist is unset"
					]
				)
			case .noCurrentTrack:
				return NSError(
					domain: domain,
					code: self.rawValue,
					userInfo: [
						NSLocalizedDescriptionKey: "The audio controller has no current track set",
						NSLocalizedFailureReasonErrorKey: "currentTrackIndex is unset"
					]
				)
			case .noPlayerAvailable:
				return NSError(
					domain: domain,
					code: self.rawValue,
					userInfo: [
						NSLocalizedDescriptionKey: "No Spotify player available",
						NSLocalizedFailureReasonErrorKey: "Spotify player is unavailable"
					]
				)
			case .dependentOperationCancelled:
				return NSError(
					domain: domain,
					code: self.rawValue,
					userInfo: [
						NSLocalizedDescriptionKey: "A dependent operation was cancelled",
						NSLocalizedFailureReasonErrorKey: "A dependent operation was cancelled with unknown reason"
					]
				)
			case .noValidSession:
				return NSError(
					domain: domain,
					code: self.rawValue,
					userInfo: [
						NSLocalizedDescriptionKey: "No valid Spotify session",
						NSLocalizedFailureReasonErrorKey: "No valid spotify session available"
					]
				)
			}
		}
	}

	// TODO: send Notifications:
	// * is last track
	// * is first track
	// * player is restarting

	static let sharedInstance = SpotifyAudioController()

	let spotify = SpotifyClient.sharedInstance
	let reachability = Reachability()!
	let audioOperationQueue: OperationQueue
	var playlist: [URL]? = nil
	var currentTrackIndex: Int? = nil
	var currentTrackPosition: TimeInterval = 0.0
	let auth = SPTAuth.defaultInstance()!

	var _player: SPTAudioStreamingController?

	var logoutAction: ((SPTAudioStreamingController?) -> Void)?

	var player: SPTAudioStreamingController? {
		if self._player == nil {
			let SPTSharedInstance = SPTAudioStreamingController.sharedInstance()
			guard SPTSharedInstance != nil else {
				Log.error?.message("SpotifyAudioController.player: unable to get SPTAudioStreamingController.sharedInstance")
				return nil
			}
			_player = SPTSharedInstance
		}
		guard !_player!.initialized else {
			return _player
		}
		do {
			try _player!.start(withClientId: self.auth.clientID)
		} catch {
			Log.warning?.message("SpotifyAudioController.player: unable to start spotify player")
			return nil
		}
		_player!.setTargetBitrate(UserSetting.sharedInstance.spotifyStreamingQuality, callback: nil)
		_player!.setRepeat(.off, callback: nil)
		return _player
	}

	override init() {
		audioOperationQueue = OperationQueue()
		audioOperationQueue.maxConcurrentOperationCount = 1


		// TODO: make auth info configurable or overrideable in a subclass.

		// Set up shared authentication information
		auth.clientID = Constant.SPOTIFY_CLIENT_ID;
		auth.redirectURL = Constant.SPOTIFY_AUTH_CALLBACK_URL
		auth.tokenSwapURL = Constant.SPOTIFY_TOKEN_SWAP_URL
		auth.tokenRefreshURL = Constant.SPOTIFY_TOKEN_REFRESH_URL
		auth.sessionUserDefaultsKey = Constant.SPOTIFY_SESSION_USER_DEFAULTS_KEY;

		auth.requestedScopes = [
			SPTAuthStreamingScope,					// Allow streaming music
			SPTAuthPlaylistReadPrivateScope,		// Allow reading user's private plalists
			SPTAuthPlaylistModifyPublicScope,		// Allow creating / modifying user's public playlists
			SPTAuthPlaylistModifyPrivateScope,		// Allow creating / modifying user's private playlists
			SPTAuthUserReadPrivateScope,			// Needed to know territory for non-premium Spotify accounts
		]
		super.init()

	}

	func restartPlayer(handler: ((Error?) -> Void)? = nil) {
		guard let spotifyPlayer = player else {
			Log.warning?.message("Unable to get player in restartPlayer")
			handler?(SACError.noPlayerAvailable.asNSError())
			return
		}
		let stop = StopPlaybackOperation()
		let logout = LogoutOperation()
		logout.addDependency(stop)
		let login = LoginOperation()
		login.addDependency(logout)
		login.completionBlock = {
			handler?(login.error)
		}

		// TODO: how to determine if any existing operations in the queue should be cancelled before enqueueing these ops?
		audioOperationQueue.addOperations([stop, logout, login], waitUntilFinished: false)
	}

	// TODO: this may not belong in this class, at least not with this logic:
	func updateDesiredBitRate(handler: ((Error?) -> Void)? = nil) {
		let connectionType: UserSetting.NetworkType = reachability.isReachableViaWiFi ? .wifi : .cellular
		let bitRate = UserSetting.sharedInstance.spotifyStreamingQuality(forType: connectionType)
		player?.setTargetBitrate(bitRate) { error in
			if error == nil {
				Log.debug?.message("Player bit rate set to: \(bitRate)")
			}
			handler?(error)
		}
	}

	func play(handler: ((Error?) -> Void)? = nil) {
		guard let playlist = self.playlist else {
			handler?(SACError.noPlaylist.asNSError())
			return
		}
		guard let currentTrackIndex = self.currentTrackIndex else {
			handler?(SACError.noPlaylist.asNSError())
			return
		}

		// TODO: check what happens when willTriggerLogin
		spotify.loginOrRenewSession { willTriggerLogin, sessionValid, error in
			guard sessionValid else {
				Log.warning?.message("Unable to renew session in startPlaying(): willTriggerLogin: \(willTriggerLogin), error: \(String(describing: error))")
				if let err = error {
					handler?(err)
				} else {
					handler?(SACError.noValidSession.asNSError())
				}
				return
			}
			guard let player = self.spotify.player else {
				Log.warning?.message("startPlaying: no player available")
				handler?(SACError.noPlayerAvailable.asNSError())
				return
			}

			player.setIsPlaying(true) { error in
				handler?(error)
			}
		}

	}

	func playTrack(_ trackURIString: String, trackStartTime: TimeInterval, handler: ((NSError?) -> Void)? = nil) {
		guard let player = self.player else {
			print("SpotifyClient.playTracks: player not available")
			return
		}
		if player.loggedIn {
			player.playSpotifyURI(trackURIString, startingWith: 0, startingWithPosition: trackStartTime) { error in
				if error != nil {
					print("playTracks: Error while initiating playback: \(String(describing: error))")
				}
				handler?(error as NSError?)
			}
		} else {
			// TODO: handle this with auth delegates (start playback if appropriate).
			player.login(withAccessToken: self.auth.session.accessToken)
		}
	}

}

// MARK: Login notification handling
extension SpotifyAudioController {
	// TODO (perhaps not here): start playback if appropriate after login / session creation
}


extension SpotifyAudioController: SPTAudioStreamingDelegate {
	func audioStreamingDidLogout(_ audioStreaming: SPTAudioStreamingController!) {
		NotificationCenter.default.post(name: NSNotification.Name(rawValue: SpotifyAudioController.NOTIFICATION_LOGGED_OUT), object: self)
	}
}
