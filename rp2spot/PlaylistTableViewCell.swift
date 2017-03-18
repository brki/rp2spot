//
//  PlaylistTableViewCell.swift
//  rp2spot
//
//  Created by Brian on 14/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

class PlaylistTableViewCell: PlainHistoryTableViewCell {

	override func configureForSong(_ song: PlayedSongData, currentlyPlayingUniqueId: String?) {
		super.configureForSong(song, currentlyPlayingUniqueId: nil)

	}

	func configureForSong(_ song: PlayedSongData, selected: Bool) {
		super.configureForSong(song, currentlyPlayingUniqueId: nil)
		if selected {
			accessoryType = .checkmark
		} else {
			accessoryType = .none
		}
	}
}
