//
//  AudioStatusObserver.swift
//  rp2spot
//
//  Created by Brian King on 12/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//


protocol AudioStatusObserver {
	/**
	Called when the given track starts playing.
	
	Parameters:
	- spotifyTrackId: id in the form "spotify:track:askseufsdfsdf12"
	*/
	func trackStartedPlaying(spotifyTrackId: String)


	/**
	Called when the given track stops playing.

	Parameters:
	- spotifyTrackId: id in the form "spotify:track:askseufsdfsdf12"
	*/
	func trackStoppedPlaying(spotifyTrackId: String)

	func playerStatusChanged(newStatus: AudioPlayerViewController.PlayerStatus)
}