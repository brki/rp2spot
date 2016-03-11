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

	@IBOutlet weak var songTitleLable: UILabel!
	@IBOutlet weak var artistNameLabel: UILabel!

	var songInfo: PlayedSongData!

	@IBAction func showRadioParadiseInfoPage(sender: AnyObject) {
	}

	@IBAction func openInSpotify(sender: AnyObject) {
	}

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
