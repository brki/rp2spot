//
//  AudioPlayerPlaylist.swift
//  rp2spot
//
//  Created by Brian King on 10/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

struct AudioPlayerPlaylist {

	struct PlaylistWindow {
		let startIndex: Int
		let endIndex: Int
	}
	let maxWindowSize = Constant.SPOTIFY_MAX_PLAYER_TRACKS
	// Provides a window of ``maxWindowSize`` onto the larger playlist.
	var currentWindow: PlaylistWindow?

	let list: [PlayedSongData]
	var currentIndex: Int?
	var trackPosition: NSTimeInterval = 0.0 // point in the track at which playback should start.
	var trackToIndexMap = [String: Int]() // key is in form "foo" (not "spotify:track:foo"), value is an index into ``list``
	var trackMetadata = [String: SPTTrack]() // key is in form "foo" (not "spotify:track:foo")

	var currentTrack: PlayedSongData? {
		guard let index = currentIndex else {
			return nil
		}
		return list[index]
	}

	init(list: [PlayedSongData], currentIndex: Int? = nil) {
		self.list = list
		self.currentIndex = currentIndex
		for (index, song) in list.enumerate() {
			trackToIndexMap[song.spotifyTrackId!] = index
		}
		setCurrentWindow()
	}

	mutating func setCurrentWindow() {
		guard let index = currentIndex else {
			currentWindow = nil
			return
		}
		currentWindow = windowAroundIndex(index, maxCount: maxWindowSize)
	}

	func windowAroundIndex(index: Int, maxCount: Int) -> PlaylistWindow {
		if list.count <= maxCount {
			return PlaylistWindow(startIndex: 0, endIndex: max(0, list.count - 1))
		}
		let halfOfRange = maxCount / 2
		let startIndex = max(0, index - halfOfRange + 1) // +1 to keep final count <= maxCount; assumption: browsing into older history is less likely.
		let endIndex = min(list.count - 1, index + halfOfRange)
		return PlaylistWindow(startIndex: startIndex, endIndex: endIndex)
	}

	func windowNeedsAdjustment() -> Bool {
		guard let index = currentIndex, window = currentWindow else {
			return false
		}

		// If the current index is the first or last track, no adjustment necessary.
		guard !(index == 0 || index == list.count - 1) else {
			return false
		}

		// If the index is at either edge of the window, it should be adjusted.
		return index - window.startIndex == 0 || index == window.endIndex
	}

	func isLastTrack(spotifyTrackId: String) -> Bool {
		if let index = trackToIndexMap[spotifyTrackId] {
			return index == list.count - 1
		}
		return false
	}

	func currentTrackIsLastTrack() -> Bool {
		if let index = currentIndex {
			return index == list.count - 1
		}
		return false
	}

	func currentTrackIsFirstTrack() -> Bool {
		if let index = currentIndex {
			return index == 0
		}
		return false
	}

	mutating func setTrackMetadata(newTrackMetadata: [SPTTrack]?) {
		guard let metadata = newTrackMetadata else {
			return
		}
		for track in metadata {
			trackMetadata[track.identifier] = track
		}
	}

	mutating func setCurrentTrack(trackId: String) {
		if let index = trackToIndexMap[trackId] {
			currentIndex = index
		} else {
			currentIndex = nil
		}
	}

	func currentTrackMetadata() -> SPTTrack? {
		guard let index = currentIndex,
			trackId = list[index].spotifyTrackId,
			metadata = trackMetadata[trackId] else {
			return nil
		}
		return metadata
	}

	/**
	Gets a list of track URIs for the playlist, centered on the given index.
	
	If the index is near the upper or lower limit, or if the current list 
	has less than maxCount items, then less than maxCount items will be returned.
	*/
	func trackURIsCenteredOnIndex(index: Int, maxCount: Int) -> [NSURL] {
		var selected: [PlayedSongData]
		if list.count < maxCount {
			selected = list
		} else {
			let window = windowAroundIndex(index, maxCount: maxCount)
			selected = Array(list[window.startIndex ... window.endIndex])
		}

		return SpotifyClient.sharedInstance.URIsForTrackIds(selected.map({ $0.spotifyTrackId! }))
	}

	func trackURIsCenteredOnTrack(trackId: String, maxCount: Int) -> [NSURL] {
		guard let index = trackToIndexMap[trackId] else {
			print("trackURIsCenteredOnTrack: track not in track map")
			return [NSURL]()
		}
		return trackURIsCenteredOnIndex(index, maxCount: maxCount)
	}

	/**
	Gets the tracks of the current window, and the index with reference to that
	window of the current track.  
	
	For example, if the playlist has 200 tracks, and the window is tracks
	51 - 150, and the playlist's currentIndex is 71, indexInWindow will be 20.
	*/
	func currentWindowTrackURIs() -> (indexInWindow: Int, tracks: [NSURL])? {
		guard let index = currentIndex, window = currentWindow else {
			return nil
		}
		let trackIds = list[window.startIndex ... window.endIndex].map({ $0.spotifyTrackId! })
		let trackURIs = SpotifyClient.sharedInstance.URIsForTrackIds(trackIds)
		let indexInWindow = index - window.startIndex
		return (indexInWindow: indexInWindow, tracks: trackURIs)
	}

	/**
	Gets the trackURIs of all playlist songs.
	*/
	func trackURIs() -> [NSURL] {
		return SpotifyClient.sharedInstance.URIsForTrackIds(Array(trackToIndexMap.keys))
	}

	mutating func incrementIndex() {
		trackPosition = 0.0
		guard currentIndex != nil else {
			if list.count > 0 {
				currentIndex = 0
			}
			return
		}
		if currentIndex! < list.count - 1 {
			currentIndex! += 1
		}
	}

	mutating func decrementIndex() {
		trackPosition = 0.0
		guard currentIndex != nil else {
			if list.count > 0 {
				currentIndex = 0
			}
			return
		}
		if currentIndex! > 0 {
			currentIndex! -= 1
		}
	}
}