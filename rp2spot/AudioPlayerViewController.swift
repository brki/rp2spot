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
		Active,		// Player is active an presumably visible
		Disabled	// Player is non-active, and presumably invisible
	}

	@IBOutlet weak var playPauseButton: UIButton!
	@IBOutlet weak var nextTrackButton: UIButton!
	@IBOutlet weak var previousTrackButton: UIButton!
	@IBOutlet weak var activityIndicator: UIActivityIndicatorView!

	var playlist = AudioPlayerPlaylist(list:[])

	var spotify = SpotifyClient.sharedInstance

	var sessionUpdateRequestTime: NSDate?

	// ``nowPlayingCenter`` is used to set current song information, this will
	// be displayed in the control center.
	var nowPlayingCenter = MPNowPlayingInfoCenter.defaultCenter()

	var status: PlayerStatus = .Disabled {
		didSet {
			if status != oldValue {
				delegate?.playerStatusChanged(status)
			}
		}
	}

	var delegate: AudioStatusObserver?

	override func viewDidLoad() {
		super.viewDidLoad()
		spotify.player.delegate = self
		spotify.player.playbackDelegate = self

		// Listen for a notification so that we can tell when
		// a user has unplugged their headphones.
		NSNotificationCenter.defaultCenter().addObserver(
			self,
			selector: #selector(self.audioRouteChanged(_:)),
			name: AVAudioSessionRouteChangeNotification,
			object: nil)

		registerForRemoteEvents()
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		updateUI(isPlaying: spotify.player.isPlaying)
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
		removeMPRemoteCommandCenterEventListeners()
	}

	@IBAction func togglePlayback(sender: AnyObject) {
		if spotify.player.isPlaying {
			pausePlaying()
		} else {
			self.startPlaying()
		}
	}

	func startPlaying(sender: AnyObject? = nil) {
		guard status == .Active else {
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
			self.spotify.player.setIsPlaying(true) { error in
				self.hideActivityIndicator()
				if let err = error {
					Utility.presentAlert("Unable to start playing", message: err.localizedDescription)
					return
				}
			}
		}
	}

	func pausePlaying(sender: AnyObject? = nil) {
		playlist.trackPosition = spotify.player.currentPlaybackPosition
		spotify.player.setIsPlaying(false) { error in
			if let err = error {
				print("pausePlaying: error while trying to pause player: \(err)")
				return
			}
		}
	}

	@IBAction func skipToNextTrack(sender: AnyObject) {
		guard status == .Active && !playlist.windowNeedsAdjustment() else {
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
		showActivityIndicator()
		spotify.loginOrRenewSession { willTriggerLogin, sessionValid, error in
			guard sessionValid else {
				print("Unable to renew session in skipToNextTrack(): willTriggerLogin: \(willTriggerLogin), error: \(error)")
				self.hideActivityIndicator()
				return
			}
			self.spotify.player.skipNext() { error in
				self.hideActivityIndicator()
				self.updateNowPlayingInfo()
				print("Error when trying to skip to next track: \(error)")
			}
		}
	}
	
	@IBAction func skipToPreviousTrack(sender: AnyObject) {
		guard status == .Active && !playlist.windowNeedsAdjustment() else {
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
			self.spotify.player.skipPrevious() { error in
				self.hideActivityIndicator()
				self.updateNowPlayingInfo()
				print("Error when trying to skip to previous track: \(error)")
			}
		}
	}

	@IBAction func stopPlaying(sender: AnyObject) {
		guard spotify.player.isPlaying || status == .Active else {
			return
		}

		playlist.trackPosition = spotify.player.currentPlaybackPosition
		// Pause music before stopping, to avoid a split second of leftover audio
		// from the currently playing track being played when the audio player
		// starts playing again (it could be a different song that start, or a different
		// position in the same song).
		spotify.player.setIsPlaying(false) { error in
			if let pauseError = error {
				print("stopPlaying: error while trying to pause playback: \(pauseError)")
			}
			self.spotify.player.stop() { error in
				guard error == nil else {
					print("stopPlaying: error while trying to stop player: \(error!)")
					return
				}
				self.updateNowPlayingInfo()
				self.status = .Disabled
			}
		}
	}

	func playTracks(withPlaylist: AudioPlayerPlaylist? = nil) {

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

		status = .Active
		showActivityIndicator()

		spotify.loginOrRenewSession() { willTriggerLogin, sessionValid, error in
			guard error == nil else {
				Utility.presentAlert(
					"Unable to start playing",
					message: error!.localizedDescription
				)
				self.status = .Disabled
				self.hideActivityIndicator()
				return
			}
			guard !willTriggerLogin else {

				// Register to be notified when the session is updated.
				self.sessionUpdateRequestTime = NSDate()
				NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(self.spotifySessionUpdated(_:)), name: SpotifyClient.SESSION_UPDATE_NOTIFICATION, object: self.spotify)

				// Let the presenter hide the player:
				self.hideActivityIndicator()
				self.status = .Disabled
				return
			}

			guard self.status == .Active else {
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
	func spotifySessionUpdated(notification: NSNotification) {

		// Do not keep listening for the notification.
		NSNotificationCenter.defaultCenter().removeObserver(self, name: SpotifyClient.SESSION_UPDATE_NOTIFICATION, object: spotify)
		let loginRequestTime = sessionUpdateRequestTime
		sessionUpdateRequestTime = nil

		// No valid session ... nothing to do.
		guard let session = spotify.auth.session where session.isValid() else {
			return
		}

		guard UserSetting.sharedInstance.canStreamSpotifyTracks != false else {
			self.status = .Disabled
			return
		}

		// Request was made a long time (> 30 seconds) ago ... do not surprise user by blasting music now.
		guard let requestTime = loginRequestTime where NSDate().timeIntervalSinceDate(requestTime) < 30.0 else {
			return
		}

		// The request was made no more than 30 seconds ago, start playing requested tracks.
		playTracks()
	}

	func updateUI(isPlaying isPlaying: Bool) {
		let imageName = isPlaying ? "Pause" : "Play"
		playPauseButton.imageView!.image = UIImage(named: imageName)!
	}

	func updateNowPlayingInfo(trackId: String? = nil) {

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

	func setNowPlayingInfo(trackInfo: SPTTrack?) {
		guard let track = trackInfo else {
			nowPlayingCenter.nowPlayingInfo = nil
			return
		}

		let artistNames = track.artists.filter({ $0.name != nil}).map({ $0.name! }).joinWithSeparator(", ")

		var nowPlayingInfo: [String: AnyObject] = [
			MPMediaItemPropertyTitle: track.name,
			MPMediaItemPropertyAlbumTitle: track.album.name,
			MPMediaItemPropertyPlaybackDuration: track.duration,
			MPNowPlayingInfoPropertyElapsedPlaybackTime: spotify.player.currentPlaybackPosition,
			// This one is necessary for the pause / playback status in control center in the simulator:
			MPNowPlayingInfoPropertyPlaybackRate: spotify.player.isPlaying ? 1 : 0
		]

		if artistNames.characters.count > 0 {
			nowPlayingInfo[MPMediaItemPropertyArtist] = artistNames
		}

		nowPlayingCenter.nowPlayingInfo = nowPlayingInfo
	}

	func showActivityIndicator() {
		activityIndicator.startAnimating()
	}

	func hideActivityIndicator() {
		activityIndicator.stopAnimating()
	}
}


// MARK: System notification handlers

extension AudioPlayerViewController {

	/**
	Notification handler for audio route changes.

	If the user has unplugged their headphones / disconnected from bluetooth speakers / something similar,
	then pause the audio.
	*/
	dynamic func audioRouteChanged(notification: NSNotification) {
		guard spotify.player.isPlaying else {
			return
		}

		// Save current track position so that playback can resume at the proper spot.
		playlist.trackPosition = spotify.player.currentPlaybackPosition

		guard let reasonCode = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else {
			print("audioRouteChanged: unable to get int value for key AVAudioSessionRouteChangeReasonKey")
			return
		}

		if AVAudioSessionRouteChangeReason(rawValue: reasonCode) == .OldDeviceUnavailable {
			spotify.player.setIsPlaying(false) { error in
				guard error == nil else {
					print("audioRouteChanged: error while trying to pause player: \(error)")
					return
				}
			}
		}
	}

	/**
	Configure handling for events triggered by remote hardware (e.g. headphones, bluetooth speakers, etc.).
	*/
	func registerForRemoteEvents() {
		let remote = MPRemoteCommandCenter.sharedCommandCenter()

		remote.nextTrackCommand.enabled = true
		remote.nextTrackCommand.addTarget(self, action: #selector(self.skipToNextTrack(_:)))

		remote.previousTrackCommand.enabled = true
		remote.previousTrackCommand.addTarget(self, action: #selector(self.skipToPreviousTrack(_:)))

		remote.togglePlayPauseCommand.enabled = true
		remote.togglePlayPauseCommand.addTarget(self, action: #selector(self.togglePlayback(_:)))

		remote.pauseCommand.enabled = true
		remote.pauseCommand.addTarget(self, action: #selector(self.pausePlaying(_:)))

		remote.playCommand.enabled = true
		remote.playCommand.addTarget(self, action: #selector(self.startPlaying(_:)))

		remote.stopCommand.enabled = true
		remote.stopCommand.addTarget(self, action: #selector(self.stopPlaying(_:)))
	}

	func removeMPRemoteCommandCenterEventListeners() {
		let remote = MPRemoteCommandCenter.sharedCommandCenter()
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

	func audioStreaming(audioStreaming: SPTAudioStreamingController!, didChangeToTrack trackMetadata: [NSObject : AnyObject]!) {
		// The trackMetadata object *should* have the track identifier too, but 
		// trackMetadata itself is occaionally nil, despite the method signature 
		// indicating otherwise.  So, fetch the track id from the player.

		guard let shortTrackId = spotify.playerCurrentTrackId else {
			return
		}

		playlist.setCurrentTrack(shortTrackId)
		updateNowPlayingInfo(shortTrackId)

		if playlist.windowNeedsAdjustment() {
			playlist.setCurrentWindow()
			if let (index, trackURIs) = playlist.currentWindowTrackURIs() {

				spotify.loginOrRenewSession { willTriggerLogin, sessionValid, error in

					guard sessionValid else {
						print("Unable to renew session before replacing track URIS: willTriggerLogin: \(willTriggerLogin), error: \(error)")
						return
					}
					self.spotify.player.replaceURIs(trackURIs, withCurrentTrack: Int32(index)) { error in
						print("Replacing playlist URIs: error: \(error)")
					}

				}
			}
		}
	}

	func audioStreaming(audioStreaming: SPTAudioStreamingController!, didChangePlaybackStatus isPlaying: Bool) {
		updateUI(isPlaying: isPlaying)
		updateNowPlayingInfo()
	}

	/**
	Somtimes this is called a long while before audioStreaming(_:didChangePlaybackStatus); it is being
	used here to toggle the pause button to a playbutton if the last available track has been reached.
	*/
	func audioStreaming(audioStreaming: SPTAudioStreamingController!, didStopPlayingTrack trackUri: NSURL!) {
		let trackId = SPTTrack.identifierFromURI(trackUri)
		if playlist.isLastTrack(trackId) {
			updateUI(isPlaying: false)
		}
		delegate?.trackStoppedPlaying(trackId)
	}

	func audioStreaming(audioStreaming: SPTAudioStreamingController!, didStartPlayingTrack trackUri: NSURL!) {
		if let interested = delegate {
			interested.trackStartedPlaying(SPTTrack.identifierFromURI(trackUri))
		}

		updateUI(isPlaying: true)
	}

	/** Called when the audio streaming object becomes the active playback device on the user's account.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidBecomeActivePlaybackDevice(audioStreaming: SPTAudioStreamingController!) {
		// print("audioStreamingDidBecomeActivePlaybackDevice")

		// If the user taps on a track before this device is the active playback device,
		// and then hits the stop button to close the audio player before playback has
		// started, do not start playing.
		guard status == .Active else {
			spotify.player.stop(nil)
			return
		}
	}

	/** Called when the audio streaming object becomes an inactive playback device on the user's account.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidBecomeInactivePlaybackDevice(audioStreaming: SPTAudioStreamingController!) {
		// Probably nothing to do here.
		print("audioStreamingDidBecomeInactivePlaybackDevice")
	}

	/** Called when the streaming controller lost permission to play audio.

	This typically happens when the user plays audio from their account on another device.

	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidLosePermissionForPlayback(audioStreaming: SPTAudioStreamingController!) {
		playlist.trackPosition = spotify.player.currentPlaybackPosition

		Utility.presentAlert(
			"Lost playback permission",
			message: "This usually happens if your Spotify account is being used on another device."
		)
	}
}


// MARK: SPTAudioStreamingDelegate

extension AudioPlayerViewController: SPTAudioStreamingDelegate {

	/** Called when network connectivity is lost.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidDisconnect(audioStreaming: SPTAudioStreamingController!) {
		playlist.trackPosition = spotify.player.currentPlaybackPosition
		print("audioStreamingDidDisconnect")
	}

	/** Called when network connectivitiy is back after being lost.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidReconnect(audioStreaming: SPTAudioStreamingController!) {
		// Probably do nothing here.  We don't want music to suddenly start blaring
		// out when network connectivity is restored minutes or hours after it was lost.
		print("audioStreamingDidReconnect")
	}

	/** Called when the streaming controller encounters a fatal error.

	At this point it may be appropriate to inform the user of the problem.

	@param audioStreaming The object that sent the message.
	@param error The error that occurred.
	*/
	func audioStreaming(audioStreaming: SPTAudioStreamingController!, didEncounterError error: NSError!) {
		playlist.trackPosition = spotify.player.currentPlaybackPosition

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
	func audioStreaming(audioStreaming: SPTAudioStreamingController!, didReceiveMessage message: String!) {
		Utility.presentAlert(
			"Message for you from Spotify",
			message: message
		)
	}
}