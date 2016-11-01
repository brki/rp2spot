//
//  PlainHistoryTableViewCell.swift
//  rp2spot
//
//  Created by Brian on 21/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit
import AlamofireImage

class PlainHistoryTableViewCell: UITableViewCell {
	static let albumThumbnailPlaceholder = UIImage(named: "vinyl")

	static let albumThumbnailFilter =  AspectScaledToFillSizeWithRoundedCornersFilter(
		size: CGSize(width: 128, height: 128),
		radius: 15.0
	)

	var spotifyTrackId: String?

	@IBOutlet weak var albumImageView: UIImageView!
	@IBOutlet weak var date: UILabel!
	@IBOutlet weak var artist: UILabel!
	@IBOutlet weak var songTitle: UILabel!

	func configureForSong(_ song: PlayedSongData, currentlyPlayingTrackId: String?) {
		let placeHolderImage = PlainHistoryTableViewCell.albumThumbnailPlaceholder
		let imageURL = song.imageURL(.small)
		self.songTitle.text = song.title
		self.artist.text = song.artistName
		self.date.text = Date.sharedInstance.shortLocalizedString(song.playedAt)
		self.spotifyTrackId = song.spotifyTrackId

		if let url = imageURL {
			self.albumImageView.af_setImageWithURL(url, placeholderImage: placeHolderImage, filter: PlainHistoryTableViewCell.albumThumbnailFilter)
		} else {
			self.albumImageView.image = placeHolderImage
		}

		assignBackgroundColor(currentlyPlayingTrackId: currentlyPlayingTrackId)
	}

	func assignBackgroundColor(currentlyPlayingTrackId: String?) {
		if spotifyTrackId == nil {
			self.backgroundColor = Constant.Color.lightOrange.color()
			self.tintColor = Constant.Color.spotifyGreen.color()
		} else if let current = currentlyPlayingTrackId, current == spotifyTrackId {
			self.backgroundColor = Constant.Color.spotifyGreen.color()
			self.tintColor = UIColor.white
		} else {
			self.backgroundColor = Constant.Color.sageGreen.color()
			self.tintColor = Constant.Color.spotifyGreen.color()
		}
	}
}
