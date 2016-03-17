//
//  PlaylistTableViewCell.swift
//  rp2spot
//
//  Created by Brian on 14/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

class PlaylistTableViewCell: PlainHistoryTableViewCell {

	override func configureForSong(song: PlayedSongData, currentlyPlayingTrackId: String?) {
		super.configureForSong(song, currentlyPlayingTrackId: nil)

	}

	func configureForSong(song: PlayedSongData, selected: Bool) {
		super.configureForSong(song, currentlyPlayingTrackId: nil)
		if selected {
			accessoryType = .Checkmark
		} else {
			accessoryType = .None
		}
	}
}
