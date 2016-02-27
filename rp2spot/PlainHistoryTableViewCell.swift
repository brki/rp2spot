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

	@IBOutlet weak var albumImageView: UIImageView!
	@IBOutlet weak var date: UILabel!
	@IBOutlet weak var artist: UILabel!
	@IBOutlet weak var songTitle: UILabel!

	func configureForSong(song: PlayedSong) {
		let placeHolderImage = PlainHistoryTableViewCell.albumThumbnailPlaceholder
		var imageURL: NSURL?
		var spotifyTrackAvailable = false
		song.managedObjectContext!.performBlockAndWait {
			self.songTitle.text = song.title
			self.artist.text = song.artistName
			self.date.text = Date.sharedInstance.shortLocalizedString(song.playedAt)
			if let imageURLText = song.smallImageURL, spotifyImageURL = NSURL(string: imageURLText) {
				imageURL = spotifyImageURL
			} else if let asin = song.asin, radioParadiseImageURL = NSURL(string: RadioParadise.imageURLText(asin, size: .Medium)) {
				imageURL = radioParadiseImageURL
			}
			spotifyTrackAvailable = song.spotifyTrackId != nil
		}

		if let url = imageURL {
			self.albumImageView.af_setImageWithURL(url, placeholderImage: placeHolderImage, filter: PlainHistoryTableViewCell.albumThumbnailFilter)
		} else {
			self.albumImageView.image = placeHolderImage
		}

		if spotifyTrackAvailable {
			self.backgroundColor = Constant.Color.SageGreen.color()
		} else {
			self.backgroundColor = Constant.Color.LightOrange.color()
		}

	}
}