//
//  PlayedSong.swift
//  rp2spot
//
//  Created by Brian on 14/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation
import CoreData


class PlayedSong: NSManagedObject {

	static func playedDuring(start start: NSDate, end: NSDate, context: NSManagedObjectContext) -> [NSDate: PlayedSong] {
		let request = NSFetchRequest(entityName: "PlayedSong")
		request.predicate = NSPredicate(format: "playedAt BETWEEN {%@, %@}", start, end)
		var playTimes = [NSDate: PlayedSong]()
		do {
			if let songs = try context.executeFetchRequest(request) as? [PlayedSong] {
				for song in songs {
					playTimes[song.playedAt] = song
				}
			} else {
				print("Unexpected result format in playedDuring()")
			}
		} catch {
			print("Error performing fetch in playedDuring(): \(error)")
		}
		return playTimes
	}

	/**
	Insert or update songs with the provided PlayedSongData array.
	*/
	static func upsertSongs(songDataList: [PlayedSongData], context: NSManagedObjectContext) {
		context.performBlockAndWait {
			let existingPlayTimes = playedDuring(
				start: songDataList.last!.playedAt,
				end: songDataList.first!.playedAt,
				context: context)

			for songData in songDataList {
				if let existingSong = existingPlayTimes[songData.playedAt] {
					existingSong.updateWithData(songData)
				} else {
					let _ = PlayedSong(playedSongData: songData, context: context)
				}
			}
		}
	}

	override init(entity: NSEntityDescription, insertIntoManagedObjectContext context: NSManagedObjectContext?) {
		super.init(entity: entity, insertIntoManagedObjectContext: context)
	}

	init(playedSongData: PlayedSongData, context: NSManagedObjectContext) {
		let entity = NSEntityDescription.entityForName("PlayedSong", inManagedObjectContext: context)!
		super.init(entity: entity, insertIntoManagedObjectContext: context)
		self.updateWithData(playedSongData, checkBeforeAssignment: false)
	}


	/**
	Update the object with the provided data.

	If ``checkBeforeAssignment`` is ``true``, then only update values if they have changed.
	This prevents useless updates from happening when the context is saved.
	*/
	func updateWithData(data: PlayedSongData, checkBeforeAssignment: Bool = true) {

		if !checkBeforeAssignment || self.title != data.title {
			self.title = data.title
		}
		if !checkBeforeAssignment || self.playedAt != data.playedAt {
			self.playedAt = data.playedAt
		}
		if !checkBeforeAssignment || self.albumTitle != data.albumTitle {
			self.albumTitle = data.albumTitle
		}
		if !checkBeforeAssignment || self.asin != data.asin {
			self.asin = data.asin
		}
		if !checkBeforeAssignment || self.artistName != data.artistName {
			self.artistName = data.artistName
		}
		if !checkBeforeAssignment || self.radioParadiseSongId != data.radioParadiseSongId {
			self.radioParadiseSongId = data.radioParadiseSongId
		}
		if !checkBeforeAssignment || self.spotifyTrackId != data.spotifyTrackId {
			self.spotifyTrackId = data.spotifyTrackId
		}
		if !checkBeforeAssignment || self.smallImageURL != data.smallImageURL {
			self.smallImageURL = data.smallImageURL
		}
		if !checkBeforeAssignment || self.largeImageURL != data.largeImageURL {
			self.largeImageURL = data.largeImageURL
		}
	}
}