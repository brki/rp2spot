//
//  SongInfoViewController.swift
//  rp2spot
//
//  Created by Brian King on 09/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit
import SafariServices

class SongInfoViewController: UIViewController {

	let spotify = SpotifyClient.sharedInstance

	@IBOutlet weak var songTitleLabel: UILabel!
	@IBOutlet weak var artistNameLabel: UILabel!
	@IBOutlet weak var albumNameLabel: UILabel!
	@IBOutlet weak var albumArtworkImageView: UIImageView!
	@IBOutlet weak var spotifyOpenButton: UIButton!

	var songInfo: PlayedSongData!

	override func viewDidLoad() {
		super.viewDidLoad()

		view.backgroundColor = Constant.Color.SageGreen.color()

		let imageURL = songInfo.imageURL(.Small)
		let placeHolderImage =  UIImage(named: "vinyl")
		if let url = imageURL {
			albumArtworkImageView.af_setImageWithURL(url, placeholderImage: placeHolderImage)
		} else {
			albumArtworkImageView.image = placeHolderImage
		}

		songTitleLabel.text = songInfo.title
		artistNameLabel.text = songInfo.artistName
		albumNameLabel.text = songInfo.albumTitle

		if songInfo.spotifyTrackId == nil || !UserSetting.sharedInstance.useSpotify {
			spotifyOpenButton.enabled = false
		}
	}

	@IBAction func showRadioParadiseInfoPage(sender: AnyObject) {
		guard let url = RadioParadise.songInfoURL(songInfo.radioParadiseSongId) else {
			print("showRadioParadiseInfoPage: unable to get URL for song with id: \(songInfo.radioParadiseSongId)")
			return
		}
		let safariVC = SFSafariViewController(URL: url)
		presentViewController(safariVC, animated: true, completion: nil)
	}

	@IBAction func openInSpotify(sender: AnyObject) {
		if let trackId = songInfo.spotifyTrackId {
			guard let url = NSURL(string: SpotifyClient.fullSpotifyTrackId(trackId)) else {
				print("Unable to create URL for track with identifier: \(trackId)")
				return
			}

			let app = UIApplication.sharedApplication()
			if app.canOpenURL(url) {
				app.openURL(url)
			} else {
				guard app.canOpenURL(Constant.SPOTIFY_APPSTORE_URL) else {
					print("Not allowed to open the spotify app store url: \(Constant.SPOTIFY_APPSTORE_URL)")
					return
				}
				app.openURL(Constant.SPOTIFY_APPSTORE_URL)
			}
		}
	}

	// TODO perhaps: get track metadata and show other details:
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
