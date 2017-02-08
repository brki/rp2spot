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

class AudioPlayerViewController: UIViewController {

	enum PlayerStatus {
		case
		active,		// Player is active an presumably visible
		disabled	// Player is non-active, and presumably invisible
	}

	struct State {
		var currentTrackURI: String? = nil
		var currentTrackPlayRequested: Bool = false
		var nextTrackURI: String? = nil
		var nextTrackQueuingRequested: Bool = false

		mutating func clearNextTrackState() {
			nextTrackQueuingRequested = false
			nextTrackURI = nil
		}
		mutating func clearCurrentTrackState() {
			currentTrackURI = nil
			currentTrackPlayRequested = false
		}
		mutating func willPlayTrack(trackURI: String?) {
			clearNextTrackState()
			currentTrackURI = trackURI
			currentTrackPlayRequested = true
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

	var targetState = State()

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
		setPlayPauseButton(isPlaying: spotify.isPlaying)
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

			self.targetState.currentTrackPlayRequested = true
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
		targetState.currentTrackPlayRequested = false
		print("pausePlaying: setting currentTrackPlayRequested = false")
		player.setIsPlaying(false) { error in
			if let err = error {
				print("pausePlaying: error while trying to pause player: \(err)")
				return
			}
		}
	}

	@IBAction func skipToNextTrack(_ sender: AnyObject) {
		self.playlist.incrementIndex()
		let nextURI = targetState.nextTrackURI
		targetState.clearNextTrackState()
		if nextURI != nil {
			// Let player continue to the already-queued next track.
			playerSkipNext()
		} else {
			changeToNewTrack()
		}
	}

	@IBAction func skipToPreviousTrack(_ sender: AnyObject) {
		self.playlist.decrementIndex()
		changeToNewTrack()
	}

	@IBAction func stopPlaying(_ sender: AnyObject) {
		guard let player = self.spotify.player else {
			print("stopPlaying: no player available")
			return
		}
		guard spotify.isPlaying || status == .active else {
			return
		}

		// Do not start playing audio after interruption if user has pressed the stop button.
		pausedDueToAudioInterruption = false
		setPlaylistTrackPosition()
		player.setIsPlaying(false) { error in
			guard error == nil else {
				print("stopPlaying: error while trying to stop player: \(error!)")
				return
			}
			self.updateNowPlayingInfo()
			if let interested = self.delegate, let wasPlayingTrackId = self.playlist.currentTrack?.spotifyTrackId {
				interested.trackStoppedPlaying(wasPlayingTrackId)
			}
			self.status = .disabled
		}
	}

	func playTracks(_ withPlaylist: AudioPlayerPlaylist? = nil) {
		if let newPlaylist = withPlaylist {
			playlist = newPlaylist
			// Set any already cached metadata for the playlist.
			let (cachedMetadata, _) = spotify.trackInfo.getCachedTrackInfo(playlist.trackURIs())
			playlist.setTrackMetadata(cachedMetadata)
		}

		guard let trackInfo = playlist.currentTrackInfo() else {
			print("playTracks: No current track, so can not start playing.")
			return
		}
		print("playTracks: calling willPlayTrack")
		targetState.willPlayTrack(trackURI: trackInfo.trackURIString)

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

			self.targetState.clearNextTrackState()
			self.spotify.playTrack(trackInfo.trackURIString, trackStartTime: self.playlist.trackPosition) { error in
				print("spotify.playTrack called")
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
	Triggers the playing of track identified by the currently selected index of the playlist.
	Notifies delegate that previous track has stopped playing.
	*/
	// TODO: refactor this to accept a .increment / .decrement param, and handle common logic.
	func changeToNewTrack() {
		let wasPlayingURI = spotify.currentTrackURI
		playTracks()
		if let trackURI = wasPlayingURI {
			delegate?.trackStoppedPlaying(SpotifyClient.shortSpotifyTrackId(trackURI))
		}
	}

	// TODO: rename this?
	func playerSkipNext() {
		if let wasPlayingTrackURI = spotify.currentTrackURI {
			delegate?.trackStoppedPlaying(SpotifyClient.shortSpotifyTrackId(wasPlayingTrackURI))
		}
		targetState.willPlayTrack(trackURI: playlist.currentTrackInfo()?.trackURIString)
		self.spotify.player?.skipNext() { error in
			guard error == nil else {
				print("Error while trying to skipNext(): \(error)")
				Utility.presentAlert(
					"Unable to skip to next track",
					message: error!.localizedDescription
				)
				return
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

	func setPlayPauseButton(isPlaying: Bool) {
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
		guard self.spotify.player != nil else {
			print("setNowPlayingInfo: no player available")
			return
		}

		// TODO: double check that this method is not being called too often.

		let artists = track.artists as! [SPTPartialArtist]

		let artistNames = artists.filter({ $0.name != nil}).map({ $0.name! }).joined(separator: ", ")

		var nowPlayingInfo: [String: AnyObject] = [
			MPMediaItemPropertyTitle: track.name as AnyObject,
			MPMediaItemPropertyAlbumTitle: track.album.name as AnyObject,
			MPMediaItemPropertyPlaybackDuration: track.duration as AnyObject,
			MPNowPlayingInfoPropertyElapsedPlaybackTime: (seekedToPosition ?? spotify.playbackPosition ?? 0.0) as AnyObject,
			// This one is necessary for the pause / playback status in control center in the simulator:
			MPNowPlayingInfoPropertyPlaybackRate: (spotify.isPlaying ? 1 : 0) as AnyObject
		]

		setNowPlayingArtwork(track: track)

		if artistNames.characters.count > 0 {
			nowPlayingInfo[MPMediaItemPropertyArtist] = artistNames as AnyObject?
		}

		nowPlayingCenter.nowPlayingInfo = nowPlayingInfo
	}

	func setNowPlayingArtwork(track: SPTTrack) {
		var imageInfo: Any?
		// There are usually three covers available: small, medium, and large.
		// We will try to use the medium one.
		if let covers = track.album?.covers, covers.count > 1 {
			imageInfo = covers[1]
		} else {
			imageInfo = track.album?.largestCover
		}
		guard let info = imageInfo as? SPTImage, let imageURL = info.imageURL else {
			print ("No track album art info available")
			return
		}
		let title = track.name
		let urlRequest = URLRequest(url: imageURL)
		ImageDownloader.default.download(urlRequest) { response in
			guard let image = response.result.value else {
				print("unable to get image, response: \(response.response)")
				return
			}
			guard self.nowPlayingCenter.nowPlayingInfo != nil, self.nowPlayingCenter.nowPlayingInfo![MPMediaItemPropertyTitle] as? String == title else {
				print("Track has changed, not setting outdated artwork image")
				return
			}
			if #available(iOS 10.0, *) {
				self.nowPlayingCenter.nowPlayingInfo![MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: info.size) { size in
					return image
				}
			} else {
				self.nowPlayingCenter.nowPlayingInfo![MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: image)
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
//		print("previous: \(metadata.prevTrack?.name), current: \(metadata.currentTrack?.name), next: \(metadata.nextTrack?.name)")
		guard let fullTrackURI = metadata.currentTrack?.uri else {
			return
		}
		let trackURI = SpotifyClient.shortSpotifyTrackId(fullTrackURI)
		updateNowPlayingInfo(trackURI)

		// Check if next track info is set to expected value.
		guard
			targetState.nextTrackQueuingRequested,
			let playerNextUri = metadata.nextTrack?.uri,
			let playlistNextUri = playlist.nextTrackInfo()?.trackURIString
		else {
				if playlist.currentTrackIsLastTrack() {
					targetState.clearNextTrackState()
				}
				return
		}
		if playerNextUri == playlistNextUri {
			print("correct track queued")
			targetState.nextTrackQueuingRequested = false
		} else {
			print("wrong track queued.  grrrr.")
		}
	}

	func queueNextTrack(metadata playerMetadata: SPTPlaybackMetadata?) {
		guard let metadata = playerMetadata else {
			print("queueNextTrack: no metadata provided")
			return
		}
		guard !targetState.nextTrackQueuingRequested else {
			print("queueNextTrack: queue request was already made")
			return
		}
		guard metadata.nextTrack == nil else {
			print("queueNextTrack: non-nil next track: \(metadata.nextTrack!.name)")
			return
		}
		guard !targetState.currentTrackPlayRequested else {
			print("queueNextTrack: current track play currently requested, will not attempt to queue next track")
			return
		}
		guard let nextTrack = playlist.trackInfoForIndex(playlist.nextIndex) else {
			print("queueNextTrack: playlist has no next track")
			return
		}
		targetState.willQueueNextTrack(trackURI: nextTrack.trackURIString)
		print("queueNextTrack: QUEUE REQUEST SENT")
		spotify.player?.queueSpotifyURI(nextTrack.trackURIString) { error in
			if error != nil {
				print("queueNextTrack: Error while trying to queue next track: \(error)")
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
		print("didStopPlayingTrack \(trackUri)")
		setProgress()
		guard !playlist.currentTrackIsLastTrack() else {
			// TODO: auto-fetch new track history and play?

			// Hide the player controls.
			stopPlaying(self)
			return
		}
		if targetState.nextTrackURI != nil {
			// The player will continue on to the next track.
			// TODO: see if this can be refactored; call changeToAdjacentTrack()
			if let trackId = playlist.currentTrack?.spotifyTrackId {
				delegate?.trackStoppedPlaying(trackId)
			}
			playlist.incrementIndex()
			targetState.willPlayTrack(trackURI: playlist.currentTrackInfo()?.trackURIString)
		} else {
			// The player needs to be told to start playing the next track from the (local) playlist.
			skipToNextTrack(self)
		}
	}

	func nextTrackIsQueued(metadata playbackMetadata: SPTPlaybackMetadata?) -> (Bool, AudioPlayerPlaylist.PlaylistTrackInfo?) {
		guard let nextTrack = playlist.trackInfoForIndex(playlist.nextIndex) else {
			// There is no next track in the playlist.
			return (true, nil)
		}
		guard let playerNextTrackUri = playbackMetadata?.nextTrack?.uri else {
			return (false, nextTrack)
		}
		return (playerNextTrackUri == nextTrack.trackURIString, nextTrack)
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

	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didReceive event: SpPlaybackEvent) {
		guard let spotifyEvent = Constant.SpotifyPlaybackEvent.fromSpotifyEnum(event) else {
//			print("didReceive unmapped event: \(event)")
			return
		}
		let currentTrackURI = spotify.currentTrackURI
		self.seekedToPosition = nil
		switch spotifyEvent {
		case .notifyTrackChanged, .notifyPlay, .notifyPause:
			handleCurrentTrackCurrentState(trackURI: currentTrackURI)
		case .audioFlush:
			setProgress()
			if let trackURI = currentTrackURI {
				self.updateNowPlayingInfo(SpotifyClient.shortSpotifyTrackId(trackURI))
			}
		}
	}
	
	func handleCurrentTrackCurrentState(trackURI: String?) {
		let isPlaying = spotify.isPlaying
		if isPlaying {
			targetState.trackIsPlaying(trackURI: trackURI)
		}
		guard !targetState.currentTrackPlayRequested else {
			return	
		}
		queueNextTrack(metadata: spotify.player?.metadata)
		DispatchQueue.main.async {
			print("updateUI called from handleCurrentTrackCurrentState")
			self.setPlayPauseButton(isPlaying: isPlaying)
		}
		setProgress(updateTrackDuration: true)
		let trackId = trackURI == nil ? nil : SpotifyClient.shortSpotifyTrackId(trackURI!)
		self.updateNowPlayingInfo(trackId)
		if isPlaying, let playingTrackId = trackId {
			progressIndicatorPanGestureRecognizer?.cancel()
			hideActivityIndicator()
			delegate?.trackStartedPlaying(playingTrackId)
		}
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
		spotify.player?.setIsPlaying(false) { error in
			if let pauseError = error {
				print("stopPlaying: error while trying to pause playback: \(pauseError)")
			}
		}

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

	/** Called on error
	@param audioStreaming The object that sent the message.
	@param error An NSError. Domain is SPTAudioStreamingErrorDomain and code is one of SpErrorCode
	*/
	func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didReceiveError error: Error!) {
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
				print("progressIndicatorContainerPanned: no player information available")
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
					print("Error in progressIndicatorContainerPanned while trying to seek to offset: \(offset): \(error!)")
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
			print("setProgressIndicatorPosition: no info available, returning.")
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
		return String(format: "%d:%02.0f", Int(interval) / 60, round(interval.truncatingRemainder(dividingBy: 60)))
	}

	func willResignActive(_ notification: Notification) {

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
		setProgress(updateTrackDuration: true)
		progressIndicator.layoutIfNeeded()
		setPlayPauseButton(isPlaying: spotify.isPlaying)

		NotificationCenter.default.removeObserver(
			self,
			name: NSNotification.Name.UIApplicationDidBecomeActive,
			object: nil)
	}
}
