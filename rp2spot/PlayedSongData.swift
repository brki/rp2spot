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

	// Note, there is a bug in Swift versions < 2.2 that prohibits returning nil in a failable initializer
	// before all non-optional properties have been initialized.  For this reason, these properties are declared
	// as vars, and the non-optionals as implicitly unwrapped optionals:
	// (ref: https://groups.google.com/d/msg/swift-language/78A0i1vDasc/hWnaDleYNf0J )
	var title: String!
	var playedAt: NSDate!
	var albumTitle: String!
	var asin: String?
	var largeImageURL: String?
	var smallImageURL: String?
	var spotifyTrackId: String?
	var radioParadiseSongId: NSNumber!
	var artistName: String!

	init?(response: NSHTTPURLResponse, representation: AnyObject) {

		guard let title = representation.valueForKeyPath("title") as? String else {
			print("PlayedSongData: unable to extract title")
			return nil
		}

		guard let playedAt = Date.sharedInstance.dateFromRPDateString(representation.valueForKeyPath("played_at") as! String) else {
			print("PlayedSongData: unable to extract playedAt")
			return nil
		}

		guard let albumTitle = representation.valueForKeyPath("album_title") as? String else {
			print("PlayedSongData: unable to extract albumTitle")
			return nil
		}

		guard let radioParadiseSongId = representation.valueForKeyPath("rp_song_id") as? NSNumber else {
			print("PlayedSongData: unable to extract radioParadiseSongId")
			return nil
		}

		guard let artistName = representation.valueForKeyPath("artist_name") as? String else {
			print("PlayedSongData: unable to extract artistName")
			return nil
		}

		self.title = title
		self.playedAt = playedAt
		self.albumTitle = albumTitle
		self.radioParadiseSongId = radioParadiseSongId
		self.artistName = artistName

		self.asin = representation.valueForKeyPath("asin") as? String ?? nil
		self.spotifyTrackId = representation.valueForKeyPath("spotify_track_id") as? String ?? nil
		self.smallImageURL = representation.valueForKeyPath("spotify_album_img_small_url") as? String ?? nil
		self.largeImageURL = representation.valueForKeyPath("spotify_album_img_large_url") as? String ?? nil
	}

	/**
	Create a PlayedSongData struct from a PlayedSong object.
	*/
	init(song: PlayedSong) {
		song.managedObjectContext!.performBlockAndWait {
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
	}

	static func collection(response response: NSHTTPURLResponse, representation: AnyObject) -> [PlayedSongData] {
		var objects = [PlayedSongData]()

		if let representation = representation as? [[String: AnyObject]] {
			for objRepresentation in representation {
				if let obj = PlayedSongData(response: response, representation: objRepresentation) {
					objects.append(obj)
				}
			}
		}

		return objects
	}
}

extension PlayedSongData : CustomStringConvertible {

	var description: String {
		return "PlayedSongData: \(self.spotifyTrackId == nil ? "\u{2757}" : "\u{2705}") \(self.title) (\(self.artistName)) [\(self.playedAt)]"
	}
}