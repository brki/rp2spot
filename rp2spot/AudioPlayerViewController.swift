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

	@IBOutlet weak var playPauseButton: UIButton!
	@IBOutlet weak var nextTrackButton: UIButton!
	@IBOutlet weak var previousTrackButton: UIButton!

	var playlist = AudioPlayerPlaylist(list:[], currentIndex: 0)

	var spotify = SpotifyClient.sharedInstance

	// ``nowPlayingCenter`` is used to set current song information, this will
	// be displayed in the control center.
	var nowPlayingCenter = MPNowPlayingInfoCenter.defaultCenter()

	override func viewDidLoad() {
		super.viewDidLoad()
		spotify.player.delegate = self
		spotify.player.playbackDelegate = self
		spotify.player.`repeat` = false

		// Listen for a notification so that we can tell when
		// a user has unplugged their headphones.
		NSNotificationCenter.defaultCenter().addObserver(
			self,
			selector: "audioRouteChanged:",
			name: AVAudioSessionRouteChangeNotification,
			object: nil)

		registerForRemoteEvents()
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
		removeMPRemoteCommandCenterEventListeners()
	}

	@IBAction func togglePlayback(sender: AnyObject) {
		if spotify.player.isPlaying {
			pausePlaying()
		} else {
			startPlaying()
		}
	}

	func startPlaying(sender: AnyObject? = nil) {
		// TODO: check if there is something to play.
		spotify.player.setIsPlaying(true) { error in
			if let err = error {
				// TODO: notify delegate of error
				return
			}
		}
	}

	func pausePlaying(sender: AnyObject? = nil) {
		spotify.player.setIsPlaying(false) { error in
			if let err = error {
				// TODO: notify delegate of error
				return
			}
		}
	}

	@IBAction func skipToNextTrack(sender: AnyObject) {
		spotify.player.skipNext() { error in
			// TODO: notify delegate of error
		}
	}
	
	@IBAction func skipToPreviousTrack(sender: AnyObject) {
		spotify.player.skipPrevious() { error in
			// TODO: notify delegate of error
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

				// TODO: notify delegate that stop button was pressed.
				(self.parentViewController! as! HistoryBrowserViewController).playerContainerViewHeightConstraint.constant = 0
			}
		}
	}

	func playTracks(playList: AudioPlayerPlaylist) {
		self.playlist = playList
		let trackURIs = spotify.URIsForTrackIds(playList.list.map({ $0.spotifyTrackId! }))
		guard trackURIs.count > 0 else {
			print("playTracks: no tracks to play!")
			return
		}

		spotify.loginOrRenewSession() { willTriggerNotification, error in
			guard error == nil else {
				print("error while trying to renew session: \(error)")
				// TODO: notify delegate of error
				return
			}
			// TODO: handle case where a session-update notification will be posted, (e.g. app goes to safari / spotify and reopens with a url)

			self.spotify.playTracks(trackURIs, fromIndex:self.playlist.currentIndex) { error in
				guard error == nil else {
					// TODO: if error, call delegate method playbackError() (HistoryBrowserVC, etc)
					return
				}
				// TODO: get track metadata to display, using:
				SPTTrack.tracksWithURIs(trackURIs, accessToken: nil, market: nil) { error, trackInfoList in
					guard error == nil else {
						print("Error fetching track infos: \(error!)")
						// TODO: notify of error
						return
					}
					guard let infos = trackInfoList as? [SPTTrack] else {
						print("trackInfoList is nil or does not contain expected SPTTrack types: \(trackInfoList)")
						return
					}
					self.playlist.setTrackMetadata(infos)
					self.updateNowPlayingInfo()
				}
			}
		}
	}

	func updateUI(isPlaying isPlaying: Bool) {
		let imageName = isPlaying ? "Pause" : "Play"
		playPauseButton.imageView!.image = UIImage(named: imageName)!
	}

	func updateNowPlayingInfo() {
		guard let track = playlist.trackMetadata[SPTTrack.identifierFromURI(spotify.player.currentTrackURI)] else {
			print("Unable to get current track metadata")
			nowPlayingCenter.nowPlayingInfo = nil
			return
		}

		let artistNames = track.artists.filter({ $0.name != nil}).map({ $0.name! }).joinWithSeparator(", ")
		var nowPlayingInfo: [String: AnyObject] = [
			MPMediaItemPropertyTitle: track.name,
			MPMediaItemPropertyAlbumTitle: track.album.name,
			MPMediaItemPropertyPlaybackDuration: track.duration
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
		remote.nextTrackCommand.addTarget(self, action: "skipToNextTrack:")

		remote.previousTrackCommand.enabled = true
		remote.previousTrackCommand.addTarget(self, action: "skipToPreviousTrack:")

		remote.togglePlayPauseCommand.enabled = true
		remote.togglePlayPauseCommand.addTarget(self, action: "togglePlayback:")

		remote.pauseCommand.enabled = true
		remote.pauseCommand.addTarget(self, action: "pausePlaying:")

		remote.playCommand.enabled = true
		remote.playCommand.addTarget(self, action: "startPlaying:")

		remote.stopCommand.enabled = true
		remote.stopCommand.addTarget(self, action: "stopPlaying:")
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
		updateNowPlayingInfo()
	}

	func audioStreaming(audioStreaming: SPTAudioStreamingController!, didChangePlaybackStatus isPlaying: Bool) {
		updateUI(isPlaying: isPlaying)
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
	}


	/** Called before the streaming controller begins playing another track.

 @param audioStreaming The object that sent the message.
 @param trackUri The URI of the track that stopped.
 */
	//	-(void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didStopPlayingTrack:(NSURL *)trackUri;

/** Called when the streaming controller fails to play a track.

 This typically happens when the track is not available in the current users' region, if you're playing
 multiple tracks the playback will start playing the next track automatically

 @param audioStreaming The object that sent the message.
 @param trackUri The URI of the track that failed to play.
 */
//	-(void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didFailToPlayTrack:(NSURL *)trackUri;


/** Called when the streaming controller begins playing a new track.

 @param audioStreaming The object that sent the message.
 @param trackUri The URI of the track that started to play.
 */
//	-(void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didStartPlayingTrack:(NSURL *)trackUri;




/** Called when the audio streaming object becomes the active playback device on the user's account.
 @param audioStreaming The object that sent the message.
 */
//	-(void)audioStreamingDidBecomeActivePlaybackDevice:(SPTAudioStreamingController *)audioStreaming;


/** Called when the audio streaming object becomes an inactive playback device on the user's account.
 @param audioStreaming The object that sent the message.
 */
//-(void)audioStreamingDidBecomeInactivePlaybackDevice:(SPTAudioStreamingController *)audioStreaming;


/** Called when the streaming controller lost permission to play audio.

 This typically happens when the user plays audio from their account on another device.

 @param audioStreaming The object that sent the message.
 */
//	-(void)audioStreamingDidLosePermissionForPlayback:(SPTAudioStreamingController *)audioStreaming;



/** Called when the streaming controller popped a new item from the playqueue.

 @param audioStreaming The object that sent the message.
 */
//	-(void)audioStreamingDidPopQueue:(SPTAudioStreamingController *)audioStreaming;
}


// MARK: SPTAudioStreamingDelegate
// TODO: implement these:

extension AudioPlayerViewController: SPTAudioStreamingDelegate {
/** Called when the streaming controller encounters a fatal error.

 At this point it may be appropriate to inform the user of the problem.

 @param audioStreaming The object that sent the message.
 @param error The error that occurred.
 */
//	-(void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didEncounterError:(NSError *)error;


/** Called when the streaming controller recieved a message for the end user from the Spotify service.

 This string should be presented to the user in a reasonable manner.

 @param audioStreaming The object that sent the message.
 @param message The message to display to the user.
 */
//	-(void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didReceiveMessage:(NSString *)message;


/** Called when network connectivity is lost.
 @param audioStreaming The object that sent the message.
 */
//	-(void)audioStreamingDidDisconnect:(SPTAudioStreamingController *)audioStreaming;


/** Called when network connectivitiy is back after being lost.
 @param audioStreaming The object that sent the message.
 */
//	-(void)audioStreamingDidReconnect:(SPTAudioStreamingController *)audioStreaming;

}