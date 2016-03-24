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

	var playlist = AudioPlayerPlaylist(list:[])

	var spotify = SpotifyClient.sharedInstance

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
			self.playTracks(self.playlist)
			return
		}
		spotify.loginOrRenewSession { willTriggerLogin, sessionValid, error in
			guard sessionValid else {
				print("Unable to renew session in startPlaying(): willTriggerLogin: \(willTriggerLogin), error: \(error)")
				return
			}
			self.spotify.player.setIsPlaying(true) { error in
				if let err = error {
					// TODO: notify delegate of error
					print("startPlaying(): error trying to setIsPlaying() on player: \(err)")
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
				// TODO: notify delegate of error
				return
			}
			self.updateNowPlayingInfo()
		}
	}

	@IBAction func skipToNextTrack(sender: AnyObject) {
		guard status == .Active else {
			// This may be triggered by a remote control when the player is disabled.  If that
			// is the case, then the tracklist and index will need to be communicated to the
			// Spotify player controller again.
			self.playlist.incrementIndex()
			self.playTracks(self.playlist)
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
		spotify.loginOrRenewSession { willTriggerLogin, sessionValid, error in
			guard sessionValid else {
				print("Unable to renew session in skipToNextTrack(): willTriggerLogin: \(willTriggerLogin), error: \(error)")
				return
			}
			self.spotify.player.skipNext() { error in
				// TODO: notify delegate of error
			}
		}
	}
	
	@IBAction func skipToPreviousTrack(sender: AnyObject) {
		guard status == .Active else {
			// This may be triggered by a remote control when the player is disabled.  If that
			// is the case, then the tracklist and index will need to be communicated to the
			// Spotify player controller again.
			playlist.decrementIndex()
			playTracks(playlist)
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
				return
			}
			self.spotify.player.skipPrevious() { error in
				// TODO: notify delegate of error
				self.updateNowPlayingInfo()
			}
		}
	}

	@IBAction func stopPlaying(sender: AnyObject) {
		// Pause music before stopping, to avoid a split second of leftover audio
		// from the currently playing track being played when the audio player
		// starts again.
		spotify.player.setIsPlaying(false) { error in
			if let pauseError = error {
				print("stopPlaying: error while trying to pause playback: \(pauseError)")
			}
			self.spotify.player.stop() { error in
				guard error == nil else {
					print("stopPlaying: error while trying to stop player: \(error!)")
					// TODO: notify delegate of error
					return
				}
				self.updateNowPlayingInfo()
				self.status = .Disabled
			}
		}
	}

	func playTracks(playList: AudioPlayerPlaylist) {
		self.playlist = playList
		let trackURIs = spotify.URIsForTrackIds(playList.list.map({ $0.spotifyTrackId! }))
		guard let index = self.playlist.currentIndex else {
			print("playTracks: No currentIndex, so can not start playing.")
			return
		}
		status = .Active

		spotify.loginOrRenewSession() { willTriggerLogin, sessionValid, error in
			guard error == nil else {
				print("error while trying to renew session: \(error)")
				// TODO: notify delegate of error
				return
			}
			guard !willTriggerLogin else {
				// TODO: handle case where a session-update notification will be posted, (e.g. app goes to safari / spotify and reopens with a url)
				// Perhaps nothing should be done here - the user will simply need to tap again to start playing.
				return
			}

			self.spotify.playTracks(trackURIs, fromIndex:index, trackStartTime: self.playlist.trackPosition) { error in
				guard error == nil else {
					// TODO: if error, call delegate method playbackError() (HistoryBrowserVC, etc)
					print("Error in AudioViewController.playTracks(): \(error)")
					return
				}
				self.updateNowPlayingInfo()
			}
		}
	}

	func updateUI(isPlaying isPlaying: Bool) {
		let imageName = isPlaying ? "Pause" : "Play"
		playPauseButton.imageView!.image = UIImage(named: imageName)!
	}

	func updateNowPlayingInfo(trackId: String? = nil) {

		let nowPlayingTrackId = trackId ?? playlist.currentTrack?.spotifyTrackId ?? SPTTrack.identifierFromURI(spotify.player.currentTrackURI)

		guard let nowPlayingId = nowPlayingTrackId else {
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
				let sameTrackPlaying = SPTTrack.identifierFromURI(self.spotify.player.currentTrackURI) == nowPlayingId
				if let trackInfo = self.playlist.trackMetadata[nowPlayingId] where sameTrackPlaying {
					self.setNowPlayingInfo(trackInfo)
				}
				if error != nil {
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
		let shortTrackId = SPTTrack.identifierFromURI(spotify.player.currentTrackURI)
		playlist.setCurrentTrack(shortTrackId)
		updateNowPlayingInfo(shortTrackId)
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
		updateNowPlayingInfo()
	}

	/** Called when the audio streaming object becomes the active playback device on the user's account.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidBecomeActivePlaybackDevice(audioStreaming: SPTAudioStreamingController!) {
		// Probably do nothing here.
		print("audioStreamingDidBecomeActivePlaybackDevice")
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
		// TODO: record last track time position, if possible.
		// TODO: notify user.
		print("audioStreamingDidLosePermissionForPlayback")
	}


	/** Called when the streaming controller popped a new item from the playqueue.

 @param audioStreaming The object that sent the message.
 */
	//	-(void)audioStreamingDidPopQueue:(SPTAudioStreamingController *)audioStreaming;


 /** Called when the streaming controller fails to play a track.

 This typically happens when the track is not available in the current users' region, if you're playing
 multiple tracks the playback will start playing the next track automatically

 @param audioStreaming The object that sent the message.
 @param trackUri The URI of the track that failed to play.
 */
	//	-(void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didFailToPlayTrack:(NSURL *)trackUri;

}


// MARK: SPTAudioStreamingDelegate

extension AudioPlayerViewController: SPTAudioStreamingDelegate {

	/** Called when network connectivity is lost.
	@param audioStreaming The object that sent the message.
	*/
	func audioStreamingDidDisconnect(audioStreaming: SPTAudioStreamingController!) {
		// TODO: record last track time position, if possible.
		// TODO: notify user.
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
		// TODO: record last track time position, if possible.
		// TODO: notify user.
		print("didEncountError: \(error)")
	}

	/** Called when the streaming controller recieved a message for the end user from the Spotify service.

	This string should be presented to the user in a reasonable manner.

	@param audioStreaming The object that sent the message.
	@param message The message to display to the user.
	*/
	func audioStreaming(audioStreaming: SPTAudioStreamingController!, didReceiveMessage message: String!) {
		// TODO: notify user (not sure what these messages are, yet).
		print("didReceiveMessage: \(message)")
	}
}