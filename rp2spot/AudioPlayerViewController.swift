//
//  AudioPlayerViewController.swift
//  rp2spot
//
//  Created by Brian King on 07/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit
import AVFoundation
import MediaPlayer

class AudioPlayerViewController: UIViewController {

	enum PlayerStatus {
		case
		active,		// Player is active an presumably visible
		disabled	// Player is non-active, and presumably invisible
	}

	@IBOutlet weak var playPauseButton: UIButton!
	@IBOutlet weak var nextTrackButton: UIButton!
	@IBOutlet weak var previousTrackButton: UIButton!
	@IBOutlet weak var activityIndicator: UIActivityIndicatorView!

	@IBOutlet weak var progressIndicator: UISlider!
	@IBOutlet weak var progressIndicatorContainer: UIView!
	@IBOutlet weak var trackDurationLabel: UILabel!
	@IBOutlet weak var elapsedTrackTimeLabel: UILabel!

	var progressIndicatorPanGestureRecognizer: UIPanGestureRecognizer?

	var playlist = AudioPlayerPlaylist(list:[])

	var spotify = SpotifyClient.sharedInstance

	var sessionUpdateRequestTime: Foundation.Date?

	var pausedDueToAudioInterruption = false

	// ``nowPlayingCenter`` is used to set current song information, this will
	// be displayed in the control center.
	var nowPlayingCenter = MPNowPlayingInfoCenter.default()

	var status: PlayerStatus = .disabled {
		didSet {
			if status != oldValue {
				delegate?.playerStatusChanged(status)
			}
		}
	}

	var progressIndicatorAnimating = false
	var progressIndicatorAnimationRequested = false
	var progressIndicatorPanGestureInvalid = false
	var elapsedTimeTimer: Timer?

	var delegate: AudioStatusObserver?

	override func viewDidLoad() {
		super.viewDidLoad()

		// Set a smaller-than-default thumbnail image, and disable user interaction
		// (user interaction will be handled by a gesture recognizer so that it works
		// well while the thumb image is animating).
		progressIndicator.setThumbImage(UIImage(named: "slider-thumb"), for: UIControlState())
		self.progressIndicator.isUserInteractionEnabled = false

		spotify.player?.delegate = self
		spotify.player?.playbackDelegate = self

		// Listen for a notification so that we can tell when
		// a user has unplugged their headphones.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(self.audioRouteChanged(_:)),
			name: NSNotification.Name.AVAudioSessionRouteChange,
			object: nil)

		// Listen for Audio Session Interruptions (e.g. incoming phone calls),
		// so that the player can pause playing.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(self.audioSessionInterruption(_:)),
			name: NSNotification.Name.AVAudioSessionInterruption,
			object: nil)

		// Listen for remote control events.
		registerForRemoteEvents()

		initprogressIndicator()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		guard let player = spotify.player else {
			return
		}
		updateUI(isPlaying: player.playbackState?.isPlaying ?? false)
		setProgress()
	}

	override func viewWillDisappear(_ animated: Bool) {
		setProgressIndicatorPosition()
		stopProgressUpdating()
		super.viewWillDisappear(animated)
	}

	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {

		// No special treatment needed unless the progress indicator is currently animating.
		guard self.progressIndicatorAnimating else {
			return
		}

		// If the progress is not stopped before animation, the animation does odd things.
		// For example:
		// * vertical -> horizontal rotation: progress jumps too far forward (e.g. where
		//   it should be 1/4 finished, it appears as if it's 1/2 finished).
		// * horizontal -> vertical rotation: the progress sometimes jumps backwards, even
		//   to the point where the progress indicator is outside of the bounds of the
		//   progress indicator.

		// The progress point is currently 1.0, and the thumb/bar are animating towards that
		// position.  Stop the animation and set the progress indicator position to the current
		// progress point according to the position in the track.
		// If layoutIfNeeded() is not called, the progress appears to be 100% complete at
		// the beginning of the rotation animation, and animates backwards to the real 
		// current progress point.
		setProgressIndicatorPosition()
		progressIndicator.layoutIfNeeded()

 		coordinator.animate(
			alongsideTransition: nil,
			completion: { context in
				// Restart the progress animation.
				self.setProgress()
		})

		super.viewWillTransition(to: size, with: coordinator)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
		removeMPRemoteCommandCenterEventListeners()
	}

	@IBAction func togglePlayback(_ sender: AnyObject) {
		guard let player = spotify.player else {
			print("togglePlayback: no player available")
			return
		}
		if player.playbackState.isPlaying {
			pausePlaying()
		} else {
			self.startPlaying()
		}
	}

	func startPlaying(_ sender: AnyObject? = nil) {
		guard status == .active else {
			// This may be triggered by a remote control when the player is disabled.  If that
			// is the case, then the tracklist and index will need to be communicated to the
			// Spotify player controller again.
			self.playTracks()
			return
		}
		showActivityIndicator()
		spotify.loginOrRenewSession { willTriggerLogin, sessionValid, error in
			guard sessionValid else {
				print("Unable to renew session in startPlaying(): willTriggerLogin: \(willTriggerLogin), error: \(error)")
				self.hideActivityIndicator()
				return
			}
			guard let player = self.spotify.player else {
				print("startPlaying: no player available")
				return
			}
			player.setIsPlaying(true) { error in
				self.hideActivityIndicator()
				if let err = error {
					Utility.presentAlert("Unable to start playing", message: err.localizedDescription)
					return
				}
			}
		}
	}

	func pausePlaying(_ sender: AnyObject? = nil) {
		setPlaylistTrackPosition()
		guard let player = self.spotify.player else {
			print("pausePlaying: no player available")
			return
		}
		player.setIsPlaying(false) { error in
			if let err = error {
				print("pausePlaying: error while trying to pause player: \(err)")
				return
			}
		}
	}

	@IBAction func skipToNextTrack(_ sender: AnyObject) {
		guard status == .active && !playlist.windowNeedsAdjustment() else {
			// This may be triggered by a remote control when the player is disabled.  If that
			// is the case, then the tracklist and index will need to be communicated to the
			// Spotify player controller again.
			self.playlist.incrementIndex()
			self.playTracks()
			return
		}

		guard !self.playlist.currentTrackIsLastTrack() else {
			// We do not want to wrap around  to the other side, which is what would
			// happen if we're at the end and player.skipNext() is called.
			// Instead, just start that last song playing again.
			self.startPlaying()
			return
		}

		// This is normal case, when the player is active and we're not at the first track.

		// (added incrementIndex here temporarily)
		// TODO perhaps: rework this function so that it checks if metadata.nextTrack is nil, and if so, queues a track, with a callback to start playing it
		//  (or, if nil, perhaps it should just call playTracks() with the appropriate index).
		// Also TODO: skiptoPrevious should check if there's a previous in metadata.  If not, call playTracks().
		self.playlist.incrementIndex()



		showActivityIndicator()
		spotify.loginOrRenewSession { willTriggerLogin, sessionValid, error in
			guard sessionValid else {
				print("Unable to renew session in skipToNextTrack(): willTriggerLogin: \(willTriggerLogin), error: \(error)")
				self.hideActivityIndicator()
				return
			}
			guard let player = self.spotify.player else {
				print("skipToNextTrack: no player available")
				return
			}
			player.skipNext() { error in
				self.hideActivityIndicator()
				self.updateNowPlayingInfo()
				if let err = error {
					print("Error when trying to skip to next track: \(err)")
				}
			}
		}
	}
	
	@IBAction func skipToPreviousTrack(_ sender: AnyObject) {
		guard status == .active && !playlist.windowNeedsAdjustment() else {
			// This may be triggered by a remote control when the player is disabled.  If that
			// is the case, then the tracklist and index will need to be communicated to the
			// Spotify player controller again.
			playlist.decrementIndex()
			playTracks()
			return
		}

		guard !playlist.currentTrackIsFirstTrack() else {
			// We do not want to wrap around  to the other side, which is what would
			// happen if we're at the first track and player.skipPrevious() is called.
			// Instead, just start that last song playing again.
			startPlaying()
			return
		}

		// This is normal case, when the player is active and we're not at the first track.
		spotify.loginOrRenewSession { willTriggerLogin, sessionValid, error in
			guard sessionValid else {
				print("Unable to renew session in skipToPreviousTrack(): willTriggerLogin: \(willTriggerLogin), error: \(error)")
				self.hideActivityIndicator()
				return
			}
			guard let player = self.spotify.player else {
				print("skipToPreviousTrack: no player available")
				return
			}
			player.skipPrevious() { error in
				self.hideActivityIndicator()
				self.updateNowPlayingInfo()
				if let err = error {
					print("Error when trying to skip to previous track: \(err)")
				}
			}
		}
	}

	@IBAction func stopPlaying(_ sender: AnyObject) {
		guard let player = self.spotify.player else {
			print("stopPlaying: no player available")
			return
		}
		guard spotify.isPlaying() || status == .active else {
			return
		}

		// Do not start playing audio after interruption if user has pressed the stop button.
		pausedDueToAudioInterruption = false

		setPlaylistTrackPosition()
		// Pause music before stopping, to avoid a split second of leftover audio
		// from the currently playing track being played when the audio player
		// starts playing again (it could be a different song that start, or a different
		// position in the same song).
		player.setIsPlaying(false) { error in
			if let pauseError = error {
				print("stopPlaying: error while trying to pause playback: \(pauseError)")
			}
			player.setIsPlaying(false) { error in
				guard error == nil else {
					print("stopPlaying: error while trying to stop player: \(error!)")
					return
				}
				self.updateNowPlayingInfo()
				self.status = .disabled
			}
		}
	}

	func playTracks(_ withPlaylist: AudioPlayerPlaylist? = nil) {

		if let newPlaylist = withPlaylist {
			playlist = newPlaylist
			// Set any already cached metadata for the playlist.
			let (cachedMetadata, _) = spotify.trackInfo.getCachedTrackInfo(playlist.trackURIs())
			playlist.setTrackMetadata(cachedMetadata)
		}

		guard let (index, trackURIs) = playlist.currentWindowTrackURIs() else {
			print("playTracks: No currentIndex, so can not start playing.")
			return
		}

		status = .active
		showActivityIndicator()

		spotify.loginOrRenewSession() { willTriggerLogin, sessionValid, error in
			guard error == nil else {
				Utility.presentAlert(
					"Unable to start playing",
					message: error!.localizedDescription
				)
				self.status = .disabled
				self.hideActivityIndicator()
				return
			}
			guard !willTriggerLogin else {

				// Register to be notified when the session is updated.
				self.sessionUpdateRequestTime = Foundation.Date()
				NotificationCenter.default.addObserver(self, selector: #selector(self.spotifySessionUpdated(_:)), name: NSNotification.Name(rawValue: SpotifyClient.SESSION_UPDATE_NOTIFICATION), object: self.spotify)

				// Let the presenter hide the player:
				self.hideActivityIndicator()
				self.status = .disabled
				return
			}

			guard self.status == .active else {
				// On a slow network when a session needed to be renewed,
				// it's possible that the stop button was already pressed.
				self.hideActivityIndicator()
				return
			}

			self.spotify.playTracks(trackURIs, fromIndex:index, trackStartTime: self.playlist.trackPosition) { error in
				self.hideActivityIndicator()
				guard error == nil else {
					Utility.presentAlert(
						"Unable to start playing",
						message: error!.localizedDescription
					)
					return
				}
			}
		}
	}

	/**
	Handles notification that the spotify session was updated (when user logs in).
	*/
	func spotifySessionUpdated(_ notification: Notification) {

		// Do not keep listening for the notification.
		NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: SpotifyClient.SESSION_UPDATE_NOTIFICATION), object: spotify)
		let loginRequestTime = sessionUpdateRequestTime
		sessionUpdateRequestTime = nil

		// No valid session ... nothing to do.
		guard let session = spotify.auth.session, session.isValid() else {
			return
		}

		guard UserSetting.sharedInstance.canStreamSpotifyTracks != false else {
			self.status = .disabled
			return
		}

		// Request was made a long time (> 30 seconds) ago ... do not surprise user by blasting music now.
		guard let requestTime = loginRequestTime, Foundation.Date().timeIntervalSince(requestTime) < 30.0 else {
			return
		}

		// The request was made no more than 30 seconds ago, start playing requested tracks.
		playTracks()
	}

	func updateUI(isPlaying: Bool) {
		let imageName = isPlaying ? "Pause" : "Play"
		playPauseButton.setImage(UIImage(named: imageName), for: UIControlState())
	}

	func updateNowPlayingInfo(_ trackId: String? = nil) {

		guard let nowPlayingId = trackId ?? playlist.currentTrack?.spotifyTrackId ?? spotify.playerCurrentTrackId else {
			print("updateNowPlayingInfo(): no nowPlayingId available")
			return
		}

		// If the track information is not yet available, try to fetch it:
		guard let track = playlist.trackMetadata[nowPlayingId] else {
			// This happens when no data is available yet (e.g. before the metadata request delivers data).
			setNowPlayingInfo(nil)

			let trackURIs = playlist.trackURIsCenteredOnTrack(
				nowPlayingId,
				maxCount: Constant.SPOTIFY_MAX_TRACKS_FOR_INFO_FETCH)

			spotify.trackInfo.trackMetadata(trackURIs) { error, trackInfoList in
				self.playlist.setTrackMetadata(trackInfoList)
				// It's possible that the track has changed since the original request; if so
				// we should not set the now playing info with the old track info.
				if self.spotify.playerCurrentTrackId == nowPlayingId {
					if let trackInfo = self.playlist.trackMetadata[nowPlayingId] {
						self.setNowPlayingInfo(trackInfo)
					}
				}
				if error != nil {
					// This is non-critical, so do not show the user any error message.
					print("updateNowPlayingInfo: error when getting track metadata: \(error!)")
				}
			}
			return
		}
		setNowPlayingInfo(track)
	}

	func setNowPlayingInfo(_ trackInfo: SPTTrack?) {
		guard let track = trackInfo else {
			nowPlayingCenter.nowPlayingInfo = nil
			return
		}
		guard let player = self.spotify.player else {
			print("setNowPlayingInfo: no player available")
			return
		}

		let artists = track.artists as! [SPTPartialArtist]

		let artistNames = artists.filter({ $0.name != nil}).map({ $0.name! }).joined(separator: ", ")

		var nowPlayingInfo: [String: AnyObject] = [
			MPMediaItemPropertyTitle: track.name as AnyObject,
			MPMediaItemPropertyAlbumTitle: track.album.name as AnyObject,
			MPMediaItemPropertyPlaybackDuration: track.duration as AnyObject,
			MPNowPlayingInfoPropertyElapsedPlaybackTime: player.playbackState.position as AnyObject,
			// This one is necessary for the pause / playback status in control center in the simulator:
			MPNowPlayingInfoPropertyPlaybackRate: (player.playbackState.isPlaying ? 1 : 0) as AnyObject
		]

		// TODO: add album image

		if artistNames.characters.count > 0 {
			nowPlayingInfo[MPMediaItemPropertyArtist] = artistNames as AnyObject?
		}

		nowPlayingCenter.nowPlayingInfo = nowPlayingInfo
	}

	func showActivityIndicator() {
		activityIndicator.startAnimating()
	}

	func hideActivityIndicator() {
		activityIndicator.stopAnimating()
	}

	func setPlaylistTrackPosition() {
		playlist.trackPosition = self.spotify.player?.playbackState?.position ?? 0.0
	}
}


// MARK: System notification handlers

extension AudioPlayerViewController {

	/**
	Notification handler for audio route changes.

	If the user has unplugged their headphones / disconnected from bluetooth speakers / something similar,
	then pause the audio.
	*/
	dynamic func audioRouteChanged(_ notification: Notification) {
		guard let player = self.spotify.player else {
			print("audioRouteChanged: no player available")
			return
		}

		guard player.playbackState.isPlaying else {
			return
		}

		// Save current track position so that playback can resume at the proper spot.
		setPlaylistTrackPosition()

		guard let reasonCode = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else {
			print("audioRouteChanged: unable to get int value for key AVAudioSessionRouteChangeReasonKey")
			return
		}

		if AVAudioSessionRouteChangeReason(rawValue: reasonCode) == .oldDeviceUnavailable {
			player.setIsPlaying(false) { error in
				guard error == nil else {
					print("audioRouteChanged: error while trying to pause player: \(error)")
					return
				}
			}
		}
	}

	/**
	If an incoming call interrupts the audio, put the player into the paused state.
	When the interruption is over, start playing audio again.  Or at least try to ...
	some people report that the audio fails to resume after an interruption when
	the app is in the background, but it seems to work fine in ios 9.3.
	*/
	func audioSessionInterruption(_ notification: Notification) {
		guard notification.name == NSNotification.Name.AVAudioSessionInterruption else {
			return
		}

		guard let rawTypeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else {
			return
		}

		if AVAudioSessionInterruptionType(rawValue: rawTypeValue) == .began {
			pausePlaying()

			// The pausedDueToAudioInterruption flag is used to determine whether audio should restart
			// after the interruption has finished.  If the AVAudioSessionInterruption was triggered
			// due to another app starting to play music, we do not want to re-start playing after
			// the other app finishes.
			if !AVAudioSession.sharedInstance().isOtherAudioPlaying {
				pausedDueToAudioInterruption = true
			}
		} else {
			if pausedDueToAudioInterruption && status == .active {
				pausedDueToAudioInterruption = false
				startPlaying()
			}
		}
	}
	
	/**
	Configure handling for events triggered by remote hardware (e.g. headphones, bluetooth speakers, etc.).
	*/
	func registerForRemoteEvents() {
		let remote = MPRemoteCommandCenter.shared()

		remote.nextTrackCommand.isEnabled = true
		remote.nextTrackCommand.addTarget(self, action: #selector(self.skipToNextTrack(_:)))

		remote.previousTrackCommand.isEnabled = true
		remote.previousTrackCommand.addTarget(self, action: #selector(self.skipToPreviousTrack(_:)))

		remote.togglePlayPauseCommand.isEnabled = true
		remote.togglePlayPauseCommand.addTarget(self, action: #selector(self.togglePlayback(_:)))

		remote.pauseCommand.isEnabled = true
		remote.pauseCommand.addTarget(self, action: #selector(self.pausePlaying(_:)))

		remote.playCommand.isEnabled = true
		remote.playCommand.addTarget(self, action: #selector(self.startPlaying(_:)))

		remote.stopCommand.isEnabled = true
		remote.stopCommand.addTarget(self, action: #selector(self.stopPlaying(_:)))

//		remote.seekForwardCommand.enabled = true
//		remote.seekForwardCommand.addTarget(self, action: <#T##Selector#>)
	}

//	func remoteSeek

	func removeMPRemoteCommandCenterEventListeners() {
		let remote = MPRemoteCommandCenter.shared()
		remote.nextTrackCommand.removeTarget(self)
		remote.previousTrackCommand.removeTarget(self)
		remote.togglePlayPauseCommand.removeTarget(self)
		remote.pauseCommand.removeTarget(self)
		remote.playCommand.removeTarget(self)
		remote.stopCommand.removeTarget(self)
	}
}


// MARK: SPTAudioStreamingPlaybackDelegate

extension AudioPlayerViewController:  SPTAudioStreamingPlaybackDelegate {

	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didChange metadata: SPTPlaybackMetadata!) {
	}

	// TODO: this is no longer a delegate method: move the logic elsewhere, if necessary.  Perhaps audioStreamingDidPopQueue should be used instead?
	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didChangeToTrack trackMetadata: [AnyHashable: Any]!) {
		// The trackMetadata object *should* have the track identifier too, but 
		// trackMetadata itself is occaionally nil, despite the method signature 
		// indicating otherwise.  So, fetch the track id from the player.

		guard let shortTrackId = spotify.playerCurrentTrackId else {
			return
		}

		// Cancel any currently-being-recognized pan gesture:
		progressIndicatorPanGestureRecognizer?.cancel()

		playlist.setCurrentTrack(shortTrackId)
		updateNowPlayingInfo(shortTrackId)
		setProgress(updateTrackDuration: true)

		if playlist.windowNeedsAdjustment() {
			playlist.setCurrentWindow()
			if let (index, trackURIs) = playlist.currentWindowTrackURIs() {

				spotify.loginOrRenewSession { willTriggerLogin, sessionValid, error in

					guard sessionValid else {
						print("Unable to renew session before replacing track URIS: willTriggerLogin: \(willTriggerLogin), error: \(error)")
						return
					}
					guard let player = self.spotify.player else {
						print("audioRouteChanged: no player available")
						return
					}

					// TODO: rework this (no longer available in API).  Or rework the whole track queueing concept?
//					player.replaceURIs(trackURIs, withCurrentTrack: Int32(index)) { error in
//						print("Replacing playlist URIs: error: \(error)")
//					}

				}
			}
		}
	}

	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didChangePlaybackStatus isPlaying: Bool) {
		updateUI(isPlaying: isPlaying)
		updateNowPlayingInfo()
		setProgress()
	}

	// This should be controlled with an operation queue, so that only one of these can execute at a time:
	func queueNextTrack() {
		guard
			let player = self.spotify.player,
			let metadata = player.metadata else {
			print("queueNextTrack: no player/metadata available")
			return
		}

		if metadata.nextTrack == nil, let nextTrackId = playlist.nextTrackId() {
			player.queueSpotifyURI(SpotifyClient.fullSpotifyTrackId(nextTrackId)) { error in
				if error != nil {
					print("queueNextTrack: error queueing next track: \(error)")
				}
			}
		}
	}

	/**
	Somtimes this is called a long while before audioStreaming(_:didChangePlaybackStatus); it is being
	used here to toggle the pause button to a playbutton if the last available track has been reached.
	*/
	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didStopPlayingTrack trackUri: String!) {
		// TODO: should playlist hold trackUris instead of identifiers, since the spotify API has changed?
		let trackId = SPTTrack.identifier(fromURI: URL(string: trackUri))!
		if playlist.isLastTrack(trackId) {
			updateUI(isPlaying: false)
		}
		setProgress()
		delegate?.trackStoppedPlaying(trackId)
	}

	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didStartPlayingTrack trackUri: String!) {
		if let interested = delegate {
			interested.trackStartedPlaying(SPTTrack.identifier(fromURI: URL(string: trackUri)))
		}
		setProgress(updateTrackDuration: true)
		updateUI(isPlaying: true)
		queueNextTrack()
	}

	/** Called when the audio streaming object becomes the active playback device on the user's account.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidBecomeActivePlaybackDevice(_ audioStreaming: SPTAudioStreamingController!) {
		// print("audioStreamingDidBecomeActivePlaybackDevice")

		// If the user taps on a track before this device is the active playback device,
		// and then hits the stop button to close the audio player before playback has
		// started, do not start playing.
		guard status == .active else {
			spotify.player?.setIsPlaying(false, callback: nil)
			return
		}
		setProgress()
	}

	/** Called when the audio streaming object becomes an inactive playback device on the user's account.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidBecomeInactivePlaybackDevice(_ audioStreaming: SPTAudioStreamingController!) {
		// Probably nothing to do here.
		print("audioStreamingDidBecomeInactivePlaybackDevice")
	}

	/** Called when the streaming controller lost permission to play audio.

	This typically happens when the user plays audio from their account on another device.

	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidLosePermission(forPlayback audioStreaming: SPTAudioStreamingController!) {
		setPlaylistTrackPosition()

		guard !AVAudioSession.sharedInstance().isOtherAudioPlaying else {
			// If permission was lost and another application on this device is now playing audio,
			// it's presumably the Spotify application, and it doesn't make sense to show an alert
			// in this case
			return
		}

		Utility.presentAlert(
			"Lost playback permission",
			message: "This usually happens if your Spotify account is being used on another device."
		)
	}
}


// MARK: SPTAudioStreamingDelegate

extension AudioPlayerViewController: SPTAudioStreamingDelegate {

	func audioStreamingDidLogin(_ audioStreaming: SPTAudioStreamingController!) {
		print("audioStreamingDidLogin")
		self.playTracks()
	}
	/** Called when network connectivity is lost.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidDisconnect(_ audioStreaming: SPTAudioStreamingController!) {
		setPlaylistTrackPosition()
		print("audioStreamingDidDisconnect")
	}

	/** Called when network connectivitiy is back after being lost.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidReconnect(_ audioStreaming: SPTAudioStreamingController!) {
		// Probably do nothing here.  We don't want music to suddenly start blaring
		// out when network connectivity is restored minutes or hours after it was lost.
		print("audioStreamingDidReconnect")
	}

	/** Called when the streaming controller encounters a fatal error.

	At this point it may be appropriate to inform the user of the problem.

	@param audioStreaming The object that sent the message.
	@param error The error that occurred.
	*/
	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didEncounterError error: Error!) {
		setPlaylistTrackPosition()

		Utility.presentAlert(
			"Error during playback",
			message: error.localizedDescription
		)
	}

	/** Called when the streaming controller recieved a message for the end user from the Spotify service.

	This string should be presented to the user in a reasonable manner.

	@param audioStreaming The object that sent the message.
	@param message The message to display to the user.
	*/
	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didReceiveMessage message: String!) {
		Utility.presentAlert(
			"Message for you from Spotify",
			message: message
		)
	}
}

// MARK: progress inidicator control
extension AudioPlayerViewController {

	func initprogressIndicator() {
		// Listen for backgrounding event, so that progress indicator updates can be stopped.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(self.willResignActive(_:)),
			name: NSNotification.Name.UIApplicationWillResignActive,
			object: nil)

		addprogressIndicatorGestureRecognizers()
	}

	/**
	Add gesture recognizer for panning on the progress indicator.
	*/
	func addprogressIndicatorGestureRecognizers() {
		progressIndicatorPanGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(self.progressIndicatorContainerPanned(_:)))

		progressIndicatorContainer.addGestureRecognizer(progressIndicatorPanGestureRecognizer!)
	}

	func progressIndicatorContainerPanned(_ recognizer: UIPanGestureRecognizer) {

		var pannedProgress = Float(recognizer.location(in: progressIndicator).x / progressIndicator.bounds.width)
		pannedProgress = max(0.0, min(1.0, pannedProgress))

		guard
			let player = spotify.player,
			let trackDuration = player.metadata?.currentTrack?.duration else {
				print("progressIndicatorContainerPanned: no player information available")
				return
		}

		let offset = trackDuration * Double(pannedProgress)

		switch (recognizer.state) {
		case .began:
			// If the pan is not starting over the thumb image, cancel the gesture recognizer.
			let currentPosition = Float(player.playbackState.position / trackDuration)
			guard abs(currentPosition - pannedProgress) < 0.15 else {
				progressIndicatorPanGestureInvalid = true
				progressIndicatorPanGestureRecognizer?.cancel()
				return
			}

			// Update the position before cancelling the animation, so that it
			// doesn't jump back from the end.
			progressIndicator.value = pannedProgress
			stopProgressUpdating()

		case .ended:
			// TODO: spotify ios-sdk bug here when trying to seek after having paused at last 1-2 seconds before track end?
			player.seek(to: offset) { error in
				self.setElapsedTimeValue(offset)
				self.setProgress()
				if let err = error {
					print("Error in progressIndicatorContainerPanned while trying to seek to offset: \(offset): \(err)")
				}
			}

		case .changed:
			progressIndicator.value = pannedProgress
			self.setElapsedTimeValue(offset)

		case .cancelled, .failed:
			if progressIndicatorPanGestureInvalid {
				// The pan gesture was marked invalid as soon as recognized, and the animation was not interrupted.
				progressIndicatorPanGestureInvalid = false
			} else {
				// The animation was interrupted, ensure that it starts again.
				setProgress()
			}

		default:
			break
		}
	}

	func setProgress(updateTrackDuration: Bool = false) {

		setProgressIndicatorPosition()

		DispatchQueue.main.async {
			self.showElapsedTime()
			if updateTrackDuration {
				self.showTrackDuration()
			}
		}

		guard spotify.player?.playbackState?.isPlaying ?? false else {
			stopProgressUpdating()
			return
		}

		DispatchQueue.main.async {
			self.startElapsedTimeTimer()
		}

		guard progressIndicatorAnimationRequested == false else {
			return
		}

		progressIndicatorAnimationRequested = true
		DispatchQueue.main.async {

			if self.progressIndicatorAnimationRequested {
				self.progressIndicatorAnimationRequested = false
				self.progressIndicatorAnimating = true
				guard
					let player = self.spotify.player,
					let duration = player.metadata.currentTrack?.duration
					else {
						return
				}
				let remainder = duration - player.playbackState.position

				UIView.animate(
					withDuration: remainder,
					delay: 0.0,
					options: [.curveLinear],
					animations: {
						self.progressIndicator.setValue(1.0, animated: true)
					},
					completion: nil)
			}
		}
	}

	/**
	Sets the progress indicator position based on the the spotify player's progress,
	and stops any progress indicator animation that might be running.
	*/
	func setProgressIndicatorPosition() {
		// TODO: fix everywhere: player.metadata and player.playbackState are actually optionals
		guard
			let player = self.spotify.player,
			let position = player.playbackState?.position,
			let duration = player.metadata?.currentTrack?.duration
			else {
				return
		}
		let progress = Float(position / duration)

		progressIndicator.value = progress

		if progressIndicatorAnimating {
			endprogressIndicatorAnimation()
		}
	}

	func stopProgressUpdating() {
		if progressIndicatorAnimating {
			endprogressIndicatorAnimation()
		}

		// Invalidate the timer on the same run loop that it was created on.
		DispatchQueue.main.async {
			self.elapsedTimeTimer?.invalidate()
			self.elapsedTimeTimer = nil
		}
	}

	/**
	Stop the animation in all sublayers of the progress indicator.
	*/
	func endprogressIndicatorAnimation() {
		func removeLayerAnimations(_ layer: CALayer) {
			layer.removeAllAnimations()
			if let sublayers = layer.sublayers {
				for sublayer in sublayers {
					removeLayerAnimations(sublayer)
				}
			}
		}

		progressIndicatorAnimating = false
		CATransaction.begin()
		removeLayerAnimations(progressIndicator.layer)
		CATransaction.commit()

	}

	func startElapsedTimeTimer() {
		guard elapsedTimeTimer == nil || elapsedTimeTimer!.isValid == false else {
			// A timer is already running.
			return
		}

		let appState = UIApplication.shared.applicationState
		guard appState == .active || appState == .inactive else {
			// No need to update the elapsed time label if the app is in the background.
			return
		}

		self.elapsedTimeTimer = Timer.scheduledTimer(
			timeInterval: 1.0,
			target: self,
			selector: #selector(self.showElapsedTime),
			userInfo: nil,
			repeats: true)

	}

	func showTrackDuration() {
		trackDurationLabel.text = formatTrackTime(spotify.player?.metadata?.currentTrack?.duration ?? 0.0)
	}

	func showElapsedTime(_ sender: AnyObject? = nil) {
		setElapsedTimeValue(spotify.player?.playbackState?.position ?? 0.0)
	}

	func setElapsedTimeValue(_ elapsed: Double) {
		elapsedTrackTimeLabel.text = formatTrackTime(elapsed)
	}

	func formatTrackTime(_ interval: TimeInterval) -> String {
		return String(format: "%d:%02.0f", Int(interval) / 60, round(interval.truncatingRemainder(dividingBy: 60)))
	}

	func willResignActive(_ notification: Notification) {

		setProgressIndicatorPosition()
		stopProgressUpdating()

		// Listen for foregrounding event, so that progress indicator updates will be triggered.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(self.willEnterForeground(_:)),
			name: NSNotification.Name.UIApplicationWillEnterForeground,
			object: nil)
	}

	func willEnterForeground(_ notification: Notification) {
		print("isPlaying: \(spotify.isPlaying())")
		setProgress()
		updateUI(isPlaying: spotify.isPlaying())

		NotificationCenter.default.removeObserver(
			self,
			name: NSNotification.Name.UIApplicationWillEnterForeground,
			object: nil)
	}
	
}
