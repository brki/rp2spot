//
//  AudioPlayerPlaylist.swift
//  rp2spot
//
//  Created by Brian King on 10/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

struct AudioPlayerPlaylist {
	let list: [PlayedSongData]
	var currentIndex: Int?
	var trackToIndexMap = [String: Int]() // key is in form "foo" (not "spotify:track:foo"), value is an index into ``list``
	var trackMetadata = [String: SPTTrack]() // key is in form "foo" (not "spotify:track:foo")

	init(list: [PlayedSongData], currentIndex: Int? = nil) {
		self.list = list
		self.currentIndex = currentIndex
		for (index, song) in list.enumerate() {
			trackToIndexMap[song.spotifyTrackId!] = index
		}
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
		trackMetadata.removeAll()
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

	mutating func incrementIndex() {
		guard currentIndex != nil else {
			if list.count > 0 {
				currentIndex = 0
			}
			return
		}
		if currentIndex! < list.count - 1 {
			currentIndex!++
		}
	}

	mutating func decrementIndex() {
		guard currentIndex != nil else {
			if list.count > 0 {
				currentIndex = 0
			}
			return
		}
		if currentIndex! > 0 {
			currentIndex!--
		}
	}
}