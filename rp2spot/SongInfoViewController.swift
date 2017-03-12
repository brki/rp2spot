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
	var canOpenSpotifyAppStoreURL = UIApplication.shared.canOpenURL(Constant.SPOTIFY_APPSTORE_URL as URL)
	lazy var spotifyTrackURL: URL? = {
		guard let trackId = self.songInfo.spotifyTrackId,
			let url = URL(string: SpotifyClient.fullSpotifyTrackId(trackId)) else {

			return nil
		}
		return url
	}()

	lazy var canOpenTrackInSpotify: Bool = {
		guard let url = self.spotifyTrackURL else {
			return false
		}
		return UIApplication.shared.canOpenURL(url)
	}()


	override func viewDidLoad() {
		super.viewDidLoad()

		// TODO: use spotify track metadata to get a medium or large image for display here, instead of
		// the potentially out-of-date small image url from the rphistory web service.
		// Consider though, that the small image is probably also the one used for the table view cells.
		view.backgroundColor = Constant.Color.sageGreen.color()

		let imageURL = songInfo.imageURL(.small)
		let placeHolderImage =  UIImage(named: "vinyl")
		if let url = imageURL {
			albumArtworkImageView.af_setImage(withURL: url, placeholderImage: placeHolderImage)
		} else {
			albumArtworkImageView.image = placeHolderImage
		}

		songTitleLabel.text = songInfo.title
		artistNameLabel.text = songInfo.artistName
		albumNameLabel.text = songInfo.albumTitle

		if !(canOpenTrackInSpotify || canOpenSpotifyAppStoreURL) {
			spotifyOpenButton.isEnabled = false
		}
		updateSpotifyTrackInfo()
	}

	@IBAction func showRadioParadiseInfoPage(_ sender: AnyObject) {
		guard let url = RadioParadise.songInfoURL(songInfo.radioParadiseSongId) else {
			print("showRadioParadiseInfoPage: unable to get URL for song with id: \(songInfo.radioParadiseSongId)")
			return
		}
		let safariVC = SFSafariViewController(url: url)
		present(safariVC, animated: true, completion: nil)
	}

	@IBAction func openInSpotify(_ sender: AnyObject) {

		let app = UIApplication.shared

		if canOpenTrackInSpotify {
			app.openURL(spotifyTrackURL!)
		} else {
			app.openURL(Constant.SPOTIFY_APPSTORE_URL as URL)
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
			guard let track = trackInfo, error == nil else {
				print("updateSpotifyTrackInfo(): Unable to get track information: error: \(error)")
				return
			}
			DispatchQueue.main.async {
				self.songTitleLabel.text = track.name
				self.albumNameLabel.text = track.albumTitle
				self.artistNameLabel.text = track.artists.joined(separator: ", ")
				if let imageURL = (track.largeCover ?? track.mediumCover)?.imageURL {
					self.albumArtworkImageView.af_setImage(withURL: imageURL)
				}
			}
		}
	}
}
