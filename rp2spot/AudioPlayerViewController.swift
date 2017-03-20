//
//  AudioPlayerViewController.swift
//  rp2spot
//
//  Created by Brian King on 07/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit
import AVFoundation
import AlamofireImage
import MediaPlayer
import CleanroomLogger
import Reachability


class AudioPlayerViewController: UIViewController {

	enum PlayerStatus {
		case
		active,		// Player is active an presumably visible
		disabled	// Player is non-active, and presumably invisible
	}

	var nowPlayingInfo = [String: Any]()

	struct State {
		var currentTrackURI: String? = nil
		var currentTrackPlayRequested: Bool = false
		var nextTrackURI: String? = nil
		var nextTrackQueuingRequested: Bool = false
		var nowPlayingTrackId: String? = nil
		var isMovingToPreviousTrack = false

		mutating func clearNextTrackState() {
			nextTrackQueuingRequested = false
			nextTrackURI = nil
		}
		mutating func clearCurrentTrackState() {
			currentTrackPlayRequested = false
			currentTrackURI = nil
		}
		mutating func willPlayTrack(trackURI: String?) {
			clearNextTrackState()
			currentTrackURI = trackURI
			currentTrackPlayRequested = true
			isMovingToPreviousTrack = false
			nowPlayingTrackId = nil
		}
		mutating func willQueueNextTrack(trackURI: String?) {
			nextTrackURI = trackURI
			nextTrackQueuingRequested = true
		}
		/**
		Update state for when a track is playing.
		If the track is the current track, this will set currentTrackPlayRequested to false.
		*/
		mutating func trackIsPlaying(trackURI: String?) {
			guard currentTrackURI == trackURI else {
				return
			}
			currentTrackPlayRequested = false
		}
	}

	let reachability = Reachability()!
	enum NetworkReachabilityState {
		case none, wifi, cellular

		static func state(_ reachability: Reachability) -> NetworkReachabilityState {
			if reachability.isReachable {
				if reachability.isReachableViaWiFi {
					return self.wifi
				} else {
					return self.cellular
				}
			}
			return self.none
		}
	}
	var lastKnownNetworkReachability: NetworkReachabilityState?

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

	var state = State()

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

	// When the player is paused, and a pan gesture is used to change the time,
	// although the player is asked to adjust it's position, it does not adjust
	// it's position until it starts playing again.
	// For display purposes, it's good to know what the selected position is.
	var seekedToPosition: TimeInterval? = nil

	var progressIndicatorAnimating = false
	var progressIndicatorAnimationRequested = false
	var progressIndicatorPanGestureInvalid = false
	var elapsedTimeTimer: Timer?

//	var restartPlayingOnPauseNotificiation = false

	// playerNeedsRestart is set to true when a player restart is necessary to avoid
	// a playback error (for example with the spotify ios-sdk beta 25, when dropping from
	// wifi to cellular during playback).
	var playerNeedsRestart = false

	// onPauseAction will be called instead of the normal handling when a notifyPause
	// is received.
	var onPauseAction: (() -> Void)? = nil

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

		// Listen for network reachability changes
		NotificationCenter.default.addObserver(self, selector: #selector(self.reachabilityChanged),name: ReachabilityChangedNotification,object: reachability)
		do{
			try reachability.startNotifier()
		} catch {
			Log.error?.message("could not start reachability notifier")
		}

		initprogressIndicator()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		updateButtons(isPlaying: spotify.isPlaying)
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
		reachability.stopNotifier()
		NotificationCenter.default.removeObserver(self)
		removeMPRemoteCommandCenterEventListeners()
	}

	@IBAction func togglePlayback(_ sender: AnyObject) {
		guard let player = spotify.player else {
			Log.warning?.message("togglePlayback: no player available")
			return
		}
		if player.playbackState.isPlaying {
			pausePlaying()
		} else {
			startPlaying()
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
				Log.warning?.message("Unable to renew session in startPlaying(): willTriggerLogin: \(willTriggerLogin), error: \(error)")
				self.hideActivityIndicator()
				return
			}
			guard let player = self.spotify.player else {
				Log.warning?.message("startPlaying: no player available")
				return
			}

			self.state.currentTrackPlayRequested = true
			player.setIsPlaying(true) { error in
				self.hideActivityIndicator()
				if let err = error {
					Utility.presentAlert("Unable to start playing", message: err.localizedDescription)
					return
				}
			}
		}
	}

	func pausePlaying(_ sender: AnyObject? = nil, handler: ((Error?) -> Void)? = nil) {
		setPlaylistTrackPosition()
		guard let player = self.spotify.player else {
			Log.warning?.message("pausePlaying: no player available")
			return
		}
		guard spotify.isPlaying else {
			Log.verbose?.message("pausePlaying: player is not currently playing")
			// TODO: re-evaluate if there is a better way to handle this case:
			// This happens when, for example, the app is re-opened after the player
			// was paused using the control center on a locked phone.  An
			// AVAudioSessionInterruptionNotification .began is received, which calls pausePlaying()
			// and sets pausedDueToAudioInterruption = true.
			// But, since it wasn't playing, we don't want to start playing again when
			// the AVAudioSessionInterruptionNotification ends.
			pausedDueToAudioInterruption = false
			return
		}
		state.currentTrackPlayRequested = false
		Log.verbose?.message("pausePlaying: will tell player to pause")
		player.setIsPlaying(false) { error in
			if let err = error {
				Log.warning?.message("pausePlaying: error while trying to pause player: \(err)")
				return
			}
		}
	}

	@IBAction func skipToNextTrack(_ sender: AnyObject) {
		playlist.incrementIndex()
		playPlaylistCurrentTrack()
	}

	@IBAction func skipToPreviousTrack(_ sender: AnyObject) {
		self.playlist.decrementIndex()
		state.isMovingToPreviousTrack = true
		playPlaylistCurrentTrack()
	}

	@IBAction func stopPlaying(_ sender: AnyObject) {
		guard let player = self.spotify.player else {
			Log.warning?.message("stopPlaying: no player available")
			return
		}
		guard spotify.isPlaying || status == .active else {
			return
		}

		// Do not start playing audio after interruption if user has pressed the stop button.
		pausedDueToAudioInterruption = false
		setPlaylistTrackPosition()
		player.setIsPlaying(false) { error in
			guard error == nil || (error as! NSError).code == SPTErrorCodeNotActiveDevice else {
				Log.error?.message("stopPlaying: error while trying to stop player: \(error!)")
				return
			}
			self.updateNowPlayingInfo()
			if let interested = self.delegate,
				let wasPlayingTrackId = self.playlist.currentTrack?.spotifyTrackId,
				let uniqueId = self.playlist.uniqueID(spotifyTrackId: wasPlayingTrackId)
			{
				interested.trackStoppedPlaying(uniqueId)
			}
			self.status = .disabled
		}
	}

	func playTracks(_ withPlaylist: AudioPlayerPlaylist? = nil) {
		if let newPlaylist = withPlaylist {
			playlist = newPlaylist
		}
		guard playlist.currentTrack != nil else {
			Log.info?.message("playTracks: No current track, so can not start playing.")
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

			// TODO: this may need changing when using the non-Safari auth flow:
			guard !willTriggerLogin else {

				// Register to be notified when the session is updated.
				self.sessionUpdateRequestTime = Foundation.Date()
				NotificationCenter.default.addObserver(
						self,
						selector: #selector(self.spotifySessionUpdated(_:)),
						name: NSNotification.Name(rawValue: SpotifyClient.SESSION_UPDATE_NOTIFICATION),
						object: self.spotify)

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
			self.lastKnownNetworkReachability = NetworkReachabilityState.state(self.reachability)
			self.playPlaylistCurrentTrack()
		}
	}

	func playPlaylistCurrentTrack(changeNow: Bool = true) {
		if let oldTrackURI = state.currentTrackURI,
	  		let uniqueId = playlist.uniqueID(spotifyTrackId: SpotifyClient.shortSpotifyTrackId(oldTrackURI))
		{
			delegate?.trackStoppedPlaying(uniqueId)
		}
		state.clearCurrentTrackState()

		// Fetch metadata if it's not already present.
		guard playlist.currentTrackInfo() != nil else {
			let trackIds = self.playlist.trackIdsCenteredOnCurrentIndex(maxCount: Constant.SPOTIFY_MAX_TRACKS_FOR_INFO_FETCH)
			self.spotify.trackInfo.trackMetadata(trackIds) {error, tracks in
				guard self.status == .active else {
					// On a slow network when a session needed to be renewed,
					// it's possible that the stop button was already pressed.
					self.hideActivityIndicator()
					return
				}
				guard let trackInfos = tracks else {
					// TODO: notify the user ...
					Log.warning?.message("No track metadata available")
					self.hideActivityIndicator()
					return
				}
				self.playlist.setTrackMetadata(trackInfos)
				// TODO: use the SpotifyTrackInfo tracks to update the displayed track details
				self.playPlaylistCurrentTrack()
			}
			return
		}

		// Handle as gracefully as possible the case that a track that is expected to be available is not
		// actually available.
		var playlistTrackURI: String? = nil
		var tryCount = 0
		while playlistTrackURI == nil && tryCount < 5 {
			tryCount += 1
			playlistTrackURI = playlist.currentTrackInfo()?.trackInfo.trackURIString
			if playlistTrackURI == nil {
				// TODO: mark track visually as unavailable (add delegate method?) if not available.
				if state.isMovingToPreviousTrack {
					playlist.decrementIndex()
				} else {
					playlist.incrementIndex()
				}
			}
		}
		guard let trackURI = playlistTrackURI else {
			Log.warning?.message("playPlaylistCurrentTrack: currentTrackInfo unexpectedly nil")
			Utility.presentAlert(
					"No playable tracks found",
					message: "You may want to try refreshing the history list by selecting another date / time.")
			return
		}
		self.state.willPlayTrack(trackURI: trackURI)
		if spotify.isPlaying && spotify.currentTrackURI == trackURI {
			// Do nothing
			Log.verbose?.message("Spotify current track URI is target URI, don't do anything")
		} else if spotify.nextTrackURI != trackURI {
			Log.debug?.message("Player being told to play a new track")
			self.spotify.playTrack(trackURI, trackStartTime: self.playlist.trackPosition) { error in
				Log.debug?.message("spotify.playTrack called")
				guard error == nil else {
					Utility.presentAlert(
							"Unable to start playing",
							message: error!.localizedDescription
					)
					return
				}
			}
		} else if changeNow || !spotify.isPlaying {
			Log.debug?.message("Player-skipping to next track")
			self.spotify.player?.skipNext() { error in
				guard error == nil else {
					Log.warning?.message("Error while trying to skipNext(): \(error)")
					Utility.presentAlert(
							"Unable to skip to next track",
							message: error!.localizedDescription
					)
					return
				}
			}
		} else {
			// If execution reaches here, the correct next track is queued, and the player should continue on to
			// play it.
			Log.verbose?.message("Falling through to next track")
		}
	}

	/**
	Handles notification that the spotify session was updated (when user logs in).
	*/
	func spotifySessionUpdated(_ notification: Notification) {
		Log.verbose?.value(notification)
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

	func updateButtons(isPlaying: Bool) {
		let imageName = isPlaying ? "Pause" : "Play"
		playPauseButton.setImage(UIImage(named: imageName), for: UIControlState())

		previousTrackButton.isEnabled = !playlist.currentTrackIsFirstTrack()
		nextTrackButton.isEnabled = !playlist.currentTrackIsLastTrack()
	}

	func updateNowPlayingInfo(_ trackId: String? = nil, forcePositionUpdate: Bool = false) {
		guard let nowPlayingId = trackId ?? playlist.currentTrack?.spotifyTrackId ?? spotify.playerCurrentTrackId else {
			Log.debug?.message("no nowPlayingId available")
			return
		}
		if let trackInfo = self.playlist.trackMetadata[nowPlayingId] {
			DispatchQueue.main.async {
				self.setNowPlayingInfo(trackInfo, forcePositionUpdate: forcePositionUpdate)
			}
		}
	}

	func setNowPlayingInfo(_ trackInfo: SpotifyTrackInfo?, forcePositionUpdate: Bool = false) {
		guard let track = trackInfo else {
			nowPlayingCenter.nowPlayingInfo = nil
			nowPlayingInfo = [String: Any]()
			return
		}
		let playbackRate = (spotify.isPlaying ? 1 : 0)
		let trackChanged = state.nowPlayingTrackId != track.identifier
		if trackChanged {
			// TODO: see where nowPlayingTrackId is being set
			state.nowPlayingTrackId = track.identifier
			nowPlayingInfo[MPMediaItemPropertyTitle] = track.name as AnyObject
			nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track.albumTitle as AnyObject
			nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = track.duration as AnyObject
			// This one is necessary for the pause / playback status in control center in the simulator:
			let artistNames = track.artists.joined(separator: ", ")
			if artistNames.characters.count > 0 {
				nowPlayingInfo[MPMediaItemPropertyArtist] = artistNames as AnyObject?
			}
		}
		nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate as AnyObject
		nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = (seekedToPosition ?? spotify.playbackPosition ?? 0.0) as AnyObject
		nowPlayingCenter.nowPlayingInfo = nowPlayingInfo

		// Set artwork if this is a new track.
		// TODO: perhaps this should be done on a background thread, and the actual setting of self.nowPlayingCenter.nowPlayingInfo done on the main thread.
		if trackChanged {
			// There are usually three covers available: small, medium, and large.
			// We will try to use the medium one.
			guard
				let imageInfo = track.mediumCover ?? track.largeCover, let imageURL = imageInfo.imageURL
			else {
				print("No track album art info available")
				return
			}
			let title = track.name
			let urlRequest = URLRequest(url: imageURL)
			ImageDownloader.default.download(urlRequest) { response in
				guard let image = response.result.value
				else {
					Log.warning?.message("unable to get image, response: \(response.response)")
					return
				}
				guard let currentInfo = self.nowPlayingCenter.nowPlayingInfo,
					  currentInfo[MPMediaItemPropertyTitle] as? String == title
				else {
					Log.debug?.message("Track has changed, not setting outdated artwork image")
					return
				}
				// Update playing state with latest values:
				Log.verbose?.message("Setting now playing info artwork")
				if #available(iOS 10.0, *) {
					self.nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: imageInfo.size) { size in
						return image
					}
				} else {
					self.nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: image)
				}
				self.nowPlayingCenter.nowPlayingInfo = self.nowPlayingInfo
			}
		}
	}

	func showActivityIndicator() {
		DispatchQueue.main.async {
			self.activityIndicator.startAnimating()
		}
	}

	func hideActivityIndicator() {
		DispatchQueue.main.async {
			self.activityIndicator.stopAnimating()
		}
	}

	func setPlaylistTrackPosition() {
		playlist.trackPosition = seekedToPosition ?? spotify.playbackPosition ?? 0.0
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
		Log.verbose?.value(notification)
		guard let player = self.spotify.player else {
			Log.warning?.message("audioRouteChanged: no player available")
			return
		}

		guard player.playbackState.isPlaying else {
			return
		}

		// Save current track position so that playback can resume at the proper spot.
		setPlaylistTrackPosition()

		guard let reasonCode = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else {
			Log.error?.message("audioRouteChanged: unable to get int value for key AVAudioSessionRouteChangeReasonKey")
			return
		}

		if AVAudioSessionRouteChangeReason(rawValue: reasonCode) == .oldDeviceUnavailable {
			Log.debug?.message("Pausing play because old device is unavailable")
			// TODO: does this make sense here?  Why not call self.pausePlaying()?
			player.setIsPlaying(false) { error in
				guard error == nil else {
					Log.warning?.message("audioRouteChanged: error while trying to pause player: \(error)")
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
		Log.verbose?.value(notification)

		guard
			let userInfo = notification.userInfo,
			let rawTypeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt
		else {
			return
		}

		if AVAudioSessionInterruptionType(rawValue: rawTypeValue) == .began {
			guard spotify.isPlaying else {
				Log.debug?.message("AVAudioSessionInterruptionType began, but player is not currently playing, so ignoring it.")
				return
			}
			Log.debug?.message("will pause playing due to audio interruption: spotify.isPlaying: \(spotify.isPlaying), pausedDueToAudioInterruption: \(pausedDueToAudioInterruption)")
			pausePlaying()

			// The pausedDueToAudioInterruption flag is used to determine whether audio should restart
			// after the interruption has finished.  If the AVAudioSessionInterruption was triggered
			// due to another app starting to play music, we do not want to re-start playing after
			// the other app finishes.
			if !AVAudioSession.sharedInstance().isOtherAudioPlaying{
				pausedDueToAudioInterruption = true
			}
		} else {
			guard
				let optionRawValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
				AVAudioSessionInterruptionOptions(rawValue: optionRawValue) == .shouldResume
			else {
				Log.debug?.message("Audio interruption ended, but Options is not shouldResume, so not starting to play")
				return
			}
			guard pausedDueToAudioInterruption && status == .active else {
				Log.debug?.message("Audio interruption ended, but not (pausedDueToAudioInerruption && status == .active): spotify.isPlaying: \(spotify.isPlaying),pausedDueToAudioInterruption: \(pausedDueToAudioInterruption)")
				return
			}
			pausedDueToAudioInterruption = false
			startPlaying()
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
		remote.pauseCommand.addTarget(self, action: #selector(self.pausePlaying(_:handler:)))

		remote.playCommand.isEnabled = true
		remote.playCommand.addTarget(self, action: #selector(self.startPlaying(_:)))

		remote.stopCommand.isEnabled = true
		remote.stopCommand.addTarget(self, action: #selector(self.stopPlaying(_:)))

//		remote.seekForwardCommand.enabled = true
//		remote.seekForwardCommand.addTarget(self, action: <#T##Selector#>)
	}

	func setRemotePreviousTrackEnabled(_ enabled: Bool) {
		MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = enabled
	}

	func setRemoteNextTrackEnabled(_ enabled: Bool) {
		MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = enabled
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

	func reachabilityChanged(notification: NSNotification) {
		let reachability = notification.object as! Reachability
		let currentReachability = NetworkReachabilityState.state(reachability)
		if currentReachability != .none {
			spotify.updateDesiredBitRate() { error in
				if error != nil {
					Log.warning?.message("Error when trying to set target bit rate: \(error!)")
				}
			}
		}
		if currentReachability == .cellular && lastKnownNetworkReachability == .wifi {
			// In order to avoid an invalid context (error code 1006) error which happens quite frequently after
			// changing from wifi to cellular while playing, mark that the player should be restarted before
			// changing the track.
			// TODO: test with in-track seeking after changing from wifi to cellular; that may also need to be handled.
			// TODO: test if this is necessary if the player is currently stopped or paused.
			playerNeedsRestart = true
		}
		lastKnownNetworkReachability = currentReachability
	}
}


// MARK: SPTAudioStreamingPlaybackDelegate

extension AudioPlayerViewController:  SPTAudioStreamingPlaybackDelegate {

	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didChange metadata: SPTPlaybackMetadata!) {
		Log.debug?.value(metadata)
//		print("previous: \(metadata.prevTrack?.name), current: \(metadata.currentTrack?.name), next: \(metadata.nextTrack?.name)")
		guard let fullTrackURI = metadata.currentTrack?.uri else {
			return
		}
		let trackURI = SpotifyClient.shortSpotifyTrackId(fullTrackURI)
		updateNowPlayingInfo(trackURI)

		// Check if next track info is set to expected value.
		guard
			state.nextTrackQueuingRequested,
			let playerNextUri = metadata.nextTrack?.uri,
			let playlistNextUri = playlist.nextTrackInfo()?.trackInfo.trackURIString
		else {
				if playlist.currentTrackIsLastTrack() {
					state.clearNextTrackState()
				}
				return
		}
		if playerNextUri == playlistNextUri {
			if let verbose = Log.verbose {
				if let trackDetails = playlist.playedSongDataForTrackId(trackId: SpotifyClient.shortSpotifyTrackId(playerNextUri)) {
					verbose.message("track queued.  [\(playerNextUri)] (\(trackDetails.title))")
				}
			}
			state.nextTrackQueuingRequested = false
		} else {
			if let warning = Log.warning {
				if let trackDetails = playlist.playedSongDataForTrackId(trackId: SpotifyClient.shortSpotifyTrackId(playerNextUri)) {
					warning.message("wrong track queued.  [\(playerNextUri)] (\(trackDetails.title))")
				} else {
					warning.message("wrong track queued.  [\(playerNextUri)] (No info found in playlist).")
				}
			}
		}
	}

	func queueNextTrack(metadata playerMetadata: SPTPlaybackMetadata?) {
		guard let metadata = playerMetadata else {
			Log.verbose?.message("queueNextTrack: no metadata provided")
			return
		}
		guard !state.nextTrackQueuingRequested else {
			Log.verbose?.message("queueNextTrack: queue request was already made")
			return
		}
		guard metadata.nextTrack == nil else {
			Log.verbose?.message("queueNextTrack: non-nil next track: \(metadata.nextTrack!.name)")
			return
		}
		guard !state.currentTrackPlayRequested else {
			Log.verbose?.message("queueNextTrack: current track play currently requested, will not attempt to queue next track")
			return
		}
		guard let nextTrack = playlist.trackInfoForIndex(playlist.nextIndex) else {
			Log.debug?.message("queueNextTrack: playlist has no next track")
			return
		}
		guard let trackURIString = nextTrack.trackInfo.trackURIString else {
			Log.debug?.message("queueNextTrack: next track does not have a valid URI; not able to queue it.")
			return
		}
		state.willQueueNextTrack(trackURI: trackURIString)
		Log.verbose?.message("queue request being sent")
		spotify.player?.queueSpotifyURI(trackURIString) { error in
			if error != nil {
				Log.warning?.message("Error while trying to queue next track (\(trackURIString)): \(error)")
			}
		}
	}

//	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didChangePlaybackStatus isPlaying: Bool) {
//		print("didChangePlaybackStatus, isPlaying: \(isPlaying)")
//	}

	/**
	Called before the streaming controller begins playing another track.
	*/
	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didStopPlayingTrack trackUri: String!) {
		Log.debug?.message("trackURI: \(trackUri)")
		setProgress()
		guard !playlist.currentTrackIsLastTrack() else {
			// TODO: auto-fetch new track history and play?
			// Hide the player controls.
			stopPlaying(self)
			return
		}
		Log.verbose?.message("state: \(state)")
		playlist.incrementIndex()
		playPlaylistCurrentTrack(changeNow: false)
	}

//	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didStartPlayingTrack trackUri: String!) {
//		print("didStartPlayingTrack: \(trackUri)")
//	}
//
//	func audioStreamingDidSkip(toNextTrack audioStreaming: SPTAudioStreamingController!) {
//		print("audioStreamingDidSkip")
//	}

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
		// TODO: is there a better way to do this?  This gives an error "-50 (nil)"
		//       but still has the desired effect of letting audio come out of the
		//       phone's speakers.
		try? AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback, with: .defaultToSpeaker)

		setProgress()
	}

	/** Called when the audio streaming object becomes an inactive playback device on the user's account.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidBecomeInactivePlaybackDevice(_ audioStreaming: SPTAudioStreamingController!) {
		// Probably nothing to do here.
		Log.debug?.trace()
	}

	/** Called when the streaming controller lost permission to play audio.

	This typically happens when the user plays audio from their account on another device.

	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidLosePermission(forPlayback audioStreaming: SPTAudioStreamingController!) {
		Log.debug?.trace()
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

	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didReceive event: SpPlaybackEvent) {
//		print("didReceiveEvent: \(state)")
		guard let spotifyEvent = Constant.SpotifyPlaybackEvent.fromSpotifyEnum(event) else {
			Log.debug?.message("unmapped event: \(event)")
			return
		}
		Log.debug?.value(spotifyEvent)
		let currentTrackURI = spotify.currentTrackURI
		seekedToPosition = nil
		switch spotifyEvent {
		case .notifyTrackChanged, .notifyPlay, .notifyPause:
			handleCurrentTrackCurrentState(trackURI: currentTrackURI)
		case .audioFlush:
			// Called after seeking in a track.
			setProgress()
			if let trackURI = currentTrackURI {
				updateNowPlayingInfo(SpotifyClient.shortSpotifyTrackId(trackURI), forcePositionUpdate: true)
			}
		}
	}

	// TODO: double check here and elsewhere that comparisons of trackids will work correctly,
	//       considering that there can be an originally-known trackId and a different regionally-playable trackId.
	func handleCurrentTrackCurrentState(trackURI: String?) {
		let isPlaying = spotify.isPlaying
		if isPlaying {
			state.trackIsPlaying(trackURI: trackURI)
			pausedDueToAudioInterruption = false
		}
		guard !state.currentTrackPlayRequested else {
			return	
		}
		Log.debug?.message("handleCurrentTrack: \(state)")
		queueNextTrack(metadata: spotify.player?.metadata)
		DispatchQueue.main.async {
			Log.verbose?.message("updateUI called from handleCurrentTrackCurrentState: isPlaying: \(isPlaying)")
			self.updateButtons(isPlaying: isPlaying)
		}
		setRemotePreviousTrackEnabled(!playlist.currentTrackIsFirstTrack())
		setRemoteNextTrackEnabled(!playlist.currentTrackIsLastTrack())
		setProgress(updateTrackDuration: true)
		let trackId = trackURI == nil ? nil : SpotifyClient.shortSpotifyTrackId(trackURI!)
		self.updateNowPlayingInfo(trackId)
		if isPlaying, let playingTrackId = trackId {
			progressIndicatorPanGestureRecognizer?.cancel()
			hideActivityIndicator()
			guard let uniqueId = playlist.uniqueID(spotifyTrackId: playingTrackId) else {
				Log.warning?.message("Unable to get uniqueID from playingTrackId")
				return
			}
			delegate?.trackStartedPlaying(uniqueId)
		}
	}
}


// MARK: SPTAudioStreamingDelegate

extension AudioPlayerViewController: SPTAudioStreamingDelegate {

	func audioStreamingDidLogin(_ audioStreaming: SPTAudioStreamingController!) {
		Log.debug?.trace()
		self.playTracks()
	}
	/** Called when network connectivity is lost.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidDisconnect(_ audioStreaming: SPTAudioStreamingController!) {
		Log.debug?.trace()
		setPlaylistTrackPosition()
		spotify.player?.setIsPlaying(false) { error in
			if let pauseError = error {
				Log.warning?.message("stopPlaying: error while trying to pause playback: \(pauseError)")
			}
		}
		pausePlaying()
	}

	/** Called when network connectivitiy is back after being lost.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidReconnect(_ audioStreaming: SPTAudioStreamingController!) {
		Log.debug?.trace()
		// Probably do nothing here.  We don't want music to suddenly start blaring
		// out when network connectivity is restored minutes or hours after it was lost.
	}

	/** Called on error
	@param audioStreaming The object that sent the message.
	@param error An NSError. Domain is SPTAudioStreamingErrorDomain and code is one of SpErrorCode
	*/
	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didReceiveError error: Error!) {
		Log.debug?.trace()
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
			let position = seekedToPosition ?? spotify.playbackPosition,
			let trackDuration = spotify.currentTrackDuration else {
				Log.warning?.message("progressIndicatorContainerPanned: no player information available")
				return
		}

		let offset = trackDuration * Double(pannedProgress)

		switch (recognizer.state) {
		case .began:
			// If the pan is not starting over the thumb image, cancel the gesture recognizer.
			let currentPosition = Float(position / trackDuration)
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
			progressIndicator.value = pannedProgress
			stopProgressUpdating()
			player.seek(to: offset) { error in
				guard error == nil else {
					self.setProgress()
					Log.warning?.message("Error in progressIndicatorContainerPanned while trying to seek to offset: \(offset): \(error!)")
					return
				}
				self.setElapsedTimeValue(offset)
				// setProgress() will be called in audioStreaming(-:didReceive:)
				self.seekedToPosition = offset
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

		guard spotify.isPlaying else {
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
					let duration = self.spotify.currentTrackDuration,
					let position = self.seekedToPosition ?? self.spotify.playbackPosition
					else {
						return
				}
				let remainder = duration - position

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
		guard
			let position = self.seekedToPosition ?? spotify.playbackPosition,
			let duration = spotify.currentTrackDuration
		else {
			Log.debug?.message("setProgressIndicatorPosition: no info available, returning.")
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
		trackDurationLabel.text = formatTrackTime(spotify.currentTrackDuration ?? 0.0)
	}

	func showElapsedTime(_ sender: AnyObject? = nil) {
		setElapsedTimeValue(seekedToPosition ?? spotify.playbackPosition ?? 0.0)
	}

	func setElapsedTimeValue(_ elapsed: Double) {
		elapsedTrackTimeLabel.text = formatTrackTime(elapsed)
	}

	func formatTrackTime(_ interval: TimeInterval) -> String {
		var minutes = Int(interval) / 60
		var seconds = Int(round(interval.truncatingRemainder(dividingBy: 60)))
		if seconds == 60 {
			seconds = 0
			minutes += 1
		}
		return String(format: "%d:%02d", minutes, seconds)
	}

	func willResignActive(_ notification: Notification) {
		Log.verbose?.value(notification)
		setProgressIndicatorPosition()
		stopProgressUpdating()
		updateNowPlayingInfo()

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(self.didBecomeActive(_:)),
			name: NSNotification.Name.UIApplicationDidBecomeActive,
			object: nil)
	}

	func didBecomeActive(_ notification: Notification) {
		Log.verbose?.value(notification)
		Log.verbose?.message("didBecomeActive: spotify.isPlaying: \(spotify.isPlaying), state: \(state)")
		setProgress(updateTrackDuration: true)
		progressIndicator.layoutIfNeeded()
		updateButtons(isPlaying: spotify.isPlaying)

		NotificationCenter.default.removeObserver(
			self,
			name: NSNotification.Name.UIApplicationDidBecomeActive,
			object: nil)
	}
}
