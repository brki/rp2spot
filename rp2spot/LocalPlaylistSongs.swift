//
//  LocalPlaylistSongs.swift
//  rp2spot
//
//  Created by Brian on 17/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

struct LocalPlaylistSongs {
	let songs: [PlayedSongData]
	var selected = [Int: Bool]()
	var maxSelected = Constant.SPOTIFY_AUTH_CALLBACK_URL
	var spotifyPlaylistId: String?

	init(songs: [PlayedSongData]) {
		self.songs = songs
	}

	mutating func toggleSelection(index: Int) {
		guard index < songs.count else {
			print("LocalPlaylistSongs:toggleSelection: warning: index out of bounds")
			return
		}
		if let _ = selected[index] {
			selected[index] = nil
		} else {
			selected[index] = true
		}
	}

	func songAtIndex(index: Int) -> (song: PlayedSongData, selected: Bool) {
		return (songs[index], selected[index] != nil)
	}

	/**
	Gets the track ids of the selected songs, in the order that they have in self.songs.
	*/
	func selectedTrackIds() -> [String] {
		var selectedIds = [String]()
		for index in selected.keys.sort() {
			if let trackId = songs[index].spotifyTrackId {
				selectedIds.append(trackId)
			}
		}
		return selectedIds
	}
}