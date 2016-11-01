//
//  LocalPlaylistSongs.swift
//  rp2spot
//
//  Created by Brian on 17/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

class LocalPlaylistSongs {
	var playlistTitle: String?
	let songs: [PlayedSongData]
	var selected = [Int: Bool]()
	var maxSelected = Constant.SPOTIFY_AUTH_CALLBACK_URL
	var spotifyPlaylistId: String?

	init(songs: [PlayedSongData]) {
		self.songs = songs
	}

	func toggleSelection(_ index: Int) {
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

	func setPlaylistTitle(_ title: String?) {
		playlistTitle = title
	}

	func songAtIndex(_ index: Int) -> (song: PlayedSongData, selected: Bool) {
		return (songs[index], selected[index] != nil)
	}

	/**
	Gets the track ids of the selected songs, in the order that they have in self.songs.
	*/
	func selectedTrackIds() -> [String] {
		var selectedIds = [String]()
		for index in selected.keys.sorted() {
			if let trackId = songs[index].spotifyTrackId {
				selectedIds.append(trackId)
			}
		}
		return selectedIds
	}
}
