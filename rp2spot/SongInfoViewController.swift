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
		updateSpotifyTrackInfo()
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

	/**
	The information available from the Radio Paradise history service does not necessarily match
	100% the matching song on Spotify.  Update with the details from Spotify.
	*/
	func updateSpotifyTrackInfo() {
		guard let trackId = songInfo.spotifyTrackId else {
			return
		}
		spotify.trackInfo.trackInfo(trackId) { error, trackInfo in
			guard let track = trackInfo where error == nil else {
				print("updateSpotifyTrackInfo(): Unable to get track information: error: \(error)")
				return
			}
			async_main {
				self.songTitleLabel.text = track.name
				self.albumNameLabel.text = track.album.name
				self.artistNameLabel.text = track.artists.filter({ $0.name != nil}).map({ $0.name! }).joinWithSeparator(", ")
			}
		}
	}
}
