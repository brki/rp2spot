//
//  SongInfoViewController.swift
//  rp2spot
//
//  Created by Brian King on 09/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

class SongInfoViewController: UIViewController {

	let spotify = SpotifyClient.sharedInstance

	var songInfo: PlayedSongData!

	func updateSpotifyTrackInfo() {
		guard let trackId = songInfo.spotifyTrackId else {
			return
		}
		spotify.trackInfo(trackId) { trackMetadata, error in
			guard error == nil else {
				// TODO: notify about error
				return
			}
			// TODO: update UI elements with data.
		}
	}
}
