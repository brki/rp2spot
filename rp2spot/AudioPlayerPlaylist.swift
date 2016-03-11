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
	var currentIndex: Int
	var trackToIndexMap = [String: Int]()
	var trackMetadata = [String: SPTTrack]()

	init(list: [PlayedSongData], currentIndex: Int) {
		self.list = list
		self.currentIndex = currentIndex
		for (index, song) in list.enumerate() {
			trackToIndexMap[SpotifyClient.fullSpotifyTrackId(song.spotifyTrackId!)] = index
		}
	}

	func isLastTrack(spotifyTrackId: String) -> Bool {
		if let index = trackToIndexMap[spotifyTrackId] {
			return index == list.count - 1
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

	mutating func incrementIndex() {
		if currentIndex < list.count - 1 {
			currentIndex++
		}
	}

	mutating func decrementIndex() {
		if currentIndex > 0 {
			currentIndex--
		}
	}
}