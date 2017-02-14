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

	struct PlaylistTrackInfo {
		let index: Int
		let trackURIString: String
	}

	let list: [PlayedSongData]
	var currentIndex: Int?
	var trackPosition: TimeInterval = 0.0 // point in the track at which playback should start.
	var trackToIndexMap = [String: Int]() // key is in form "foo" (not "spotify:track:foo"), value is an index into ``list``
	var trackMetadata = [String: SPTTrack]() // key is in form "foo" (not "spotify:track:foo")

	var currentTrack: PlayedSongData? {
		guard let index = currentIndex else {
			return nil
		}
		return list[index]
	}

	var nextIndex: Int? {
		guard
            let index = currentIndex,
                index < list.count - 1 else {
			return nil
		}
        return index + 1
	}

	var previousIndex: Int? {
		guard
				let index = currentIndex,
				index > 0 else {
			return nil
		}
		return index - 1
	}

	init(list: [PlayedSongData], currentIndex: Int? = nil) {
		self.list = list
		self.currentIndex = currentIndex
		for (index, song) in list.enumerated() {
			trackToIndexMap[song.spotifyTrackId!] = index
		}
	}

	func windowAroundIndex(_ index: Int, maxCount: Int) -> PlaylistWindow {
		if list.count <= maxCount {
			return PlaylistWindow(startIndex: 0, endIndex: max(0, list.count - 1))
		}
		let halfOfRange = maxCount / 2
		let startIndex = max(0, index - halfOfRange + 1) // +1 to keep final count <= maxCount; assumption: browsing into older history is less likely.
		let endIndex = min(list.count - 1, index + halfOfRange)
		return PlaylistWindow(startIndex: startIndex, endIndex: endIndex)
	}

	func currentTrackIsFirstTrack() -> Bool {
		guard let index = currentIndex else {
			return false
		}
		return index == 0
	}

	func currentTrackIsLastTrack() -> Bool {
		guard let index = currentIndex else {
			return false
		}
		return index == list.count - 1
	}

	mutating func setTrackMetadata(_ newTrackMetadata: [SPTTrack]?) {
		guard let metadata = newTrackMetadata else {
			return
		}
		for track in metadata {
			trackMetadata[track.identifier] = track
		}
	}

    func currentTrackInfo() -> PlaylistTrackInfo? {
		return trackInfoForIndex(self.currentIndex)
	}

	func nextTrackInfo() -> PlaylistTrackInfo? {
		return trackInfoForIndex(self.nextIndex)
	}

	func playedSongDataForTrackId(trackId: String?) -> PlayedSongData? {
		guard let id = trackId else {
			return nil
		}
		guard let index = trackToIndexMap[id] else {
			return nil
		}
		return list[index]
	}

	func trackInfoForIndex(_ trackIndex: Int?) -> PlaylistTrackInfo? {
		guard
            let index = trackIndex,
            let trackId = list[index].spotifyTrackId else {
				return nil
		}
		return PlaylistTrackInfo(index: index, trackURIString: SpotifyClient.fullSpotifyTrackId(trackId))
	}

	/**
	Gets a list of track URIs for the playlist, centered on the given index.
	
	If the index is near the upper or lower limit, or if the current list 
	has less than maxCount items, then less than maxCount items will be returned.
	*/
	func trackURIsCenteredOnIndex(_ index: Int, maxCount: Int) -> [URL] {
		var selected: [PlayedSongData]
		if list.count < maxCount {
			selected = list
		} else {
			let window = windowAroundIndex(index, maxCount: maxCount)
			selected = Array(list[window.startIndex ... window.endIndex])
		}

		return SpotifyClient.sharedInstance.URIsForTrackIds(selected.map({ $0.spotifyTrackId! }))
	}

	func trackURIsCenteredOnTrack(_ trackId: String, maxCount: Int) -> [URL] {
		guard let index = trackToIndexMap[trackId] else {
			print("trackURIsCenteredOnTrack: track not in track map")
			return [URL]()
		}
		return trackURIsCenteredOnIndex(index, maxCount: maxCount)
	}

	/**
	Gets the trackURIs of all playlist songs.
	*/
	func trackURIs() -> [URL] {
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
