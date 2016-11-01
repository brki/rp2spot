//
//  PlayedSongData.swift
//  rp2spot
//
//  Created by Brian on 14/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation
import Alamofire


final class PlayedSongData: ResponseObjectSerializable, ResponseCollectionSerializable {

	enum ImageSize {
		case small, large
	}
	
	var title: String
	var playedAt: Foundation.Date
	var albumTitle: String
	var asin: String?
	var largeImageURL: String?
	var smallImageURL: String?
	var spotifyTrackId: String?
	var radioParadiseSongId: NSNumber
	var artistName: String

	init?(response: HTTPURLResponse, representation: Any) {

		guard let representation = representation as? [String: Any] else {
			print("PlayedSongData: representation is not of expected form [String: Any]")
			return nil
		}

		guard let title = representation["title"] as? String else {
			print("PlayedSongData: unable to extract title")
			return nil
		}

		guard let playedAt = Date.sharedInstance.dateFromRPDateString(representation["played_at"] as! String) else {
			print("PlayedSongData: unable to extract playedAt")
			return nil
		}

		guard let albumTitle = representation["album_title"] as? String else {
			print("PlayedSongData: unable to extract albumTitle")
			return nil
		}

		guard let radioParadiseSongId = representation["rp_song_id"] as? NSNumber else {
			print("PlayedSongData: unable to extract radioParadiseSongId")
			return nil
		}

		guard let artistName = representation["artist_name"] as? String else {
			print("PlayedSongData: unable to extract artistName")
			return nil
		}

		self.title = title
		self.playedAt = playedAt
		self.albumTitle = albumTitle
		self.radioParadiseSongId = radioParadiseSongId
		self.artistName = artistName

		self.asin = representation["asin"] as? String ?? nil
		self.spotifyTrackId = representation["spotify_track_id"] as? String ?? nil
		self.smallImageURL = representation["spotify_album_img_small_url"] as? String ?? nil
		self.largeImageURL = representation["spotify_album_img_large_url"] as? String ?? nil
	}

	/**
	Create a PlayedSongData struct from a PlayedSong object.
	
	Note that it's the caller's responsibility to ensure that this is done in a thread-safe manner
	for the song's managedObjectContext.
	*/
	init(song: PlayedSong) {
		self.title = song.title
		self.playedAt = song.playedAt
		self.albumTitle = song.albumTitle
		self.radioParadiseSongId = song.radioParadiseSongId
		self.artistName = song.artistName
		self.asin = song.asin
		self.spotifyTrackId = song.spotifyTrackId
		self.smallImageURL = song.smallImageURL
		self.largeImageURL = song.largeImageURL
	}

	func imageURL(_ preferredSize: ImageSize = .small) -> URL? {
		var urlText: String?
		var imageURL: URL?
		if preferredSize == .small {
			urlText = smallImageURL
		} else {
			urlText = largeImageURL
		}

		if let imageURLText = urlText, let spotifyImageURL = URL(string: imageURLText) {
			imageURL = spotifyImageURL
		} else {
			let radioParadiseImageSize: RadioParadise.ImageSize = preferredSize == .small ? .Medium : .Large
			if let albumAsin = asin, let radioParadiseImageURL = URL(string: RadioParadise.imageURLText(albumAsin, size: radioParadiseImageSize)) {
				imageURL = radioParadiseImageURL
			}
		}
		return imageURL
	}

	/**
	Helper method for json deserialization.
	*/
	static func collection(response: HTTPURLResponse, representation: AnyObject) -> [PlayedSongData] {
		var objects = [PlayedSongData]()

		if let representation = representation as? [[String: AnyObject]] {
			for objRepresentation in representation {
				if let obj = PlayedSongData(response: response, representation: objRepresentation as AnyObject) {
					objects.append(obj)
				}
			}
		}

		return objects
	}

	/**
	Returns an array of PlayedSongData objects, given an array of PlayedSong objects.

	Note that it's the caller's responsibility to ensure that this is done in a thread-safe manner
	for the song's managedObjectContext.
	*/
	static func dataItemsFromPlayedSongs(_ playedSongs: [PlayedSong]) -> [PlayedSongData] {
		return playedSongs.map({ PlayedSongData(song: $0) })
	}
}

extension PlayedSongData : CustomStringConvertible {

	var description: String {
		return "PlayedSongData: \(self.spotifyTrackId == nil ? "\u{2757}" : "\u{2705}") \(self.title) (\(self.artistName)) [\(self.playedAt)]"
	}
}
