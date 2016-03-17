//
//  PlayedSongDataManager.swift
//  rp2spot
//
//  Created by Brian King on 10/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation
import CoreData

class PlayedSongDataManager {

	var fetchedResultsControllerDelegate: NSFetchedResultsControllerDelegate
	var context: NSManagedObjectContext
	let userSettings = UserSetting.sharedInstance
	var isFetchingOlder = false
	var _isRefreshing = false
	var isRefreshing: Bool {
		get {
			return _isRefreshing
		}
		set {
			objc_sync_enter(self)
			_isRefreshing = newValue
			objc_sync_exit(self)
		}
	}

	var songCount: Int {
		// It is safe to access the fetchedObjects count without using the context's queue
		return self.fetchedResultsController.fetchedObjects?.count ?? 0
	}

	init(fetchedResultsControllerDelegate: NSFetchedResultsControllerDelegate, context: NSManagedObjectContext) {
		self.fetchedResultsControllerDelegate = fetchedResultsControllerDelegate
		self.context = context
	}

	lazy var fetchedResultsController: NSFetchedResultsController = {
		var frc: NSFetchedResultsController!
		self.context.performBlockAndWait {
			let fetchRequest = NSFetchRequest(entityName: "PlayedSong")
			fetchRequest.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: false)]
			frc = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: self.context, sectionNameKeyPath: nil, cacheName: nil)

		}
		frc.delegate = self.fetchedResultsControllerDelegate
		return frc
	}()

	/**
	(Re)fetch the data for the fetchedResultsController.
	*/
	func refresh(handler: (NSError?) -> Void) {
		context.performBlock {
			do {
				try self.fetchedResultsController.performFetch()
				handler(nil)
			} catch {
				handler(error as NSError)
			}
		}
	}

	func saveContext() {
		CoreDataStack.saveContext(self.context)
	}

	func loadLatestIfEmpty(handler: ((success: Bool) -> Void)? = nil) {
		guard songCount == 0 else {
			handler?(success: true)
			return
		}
		context.performBlock {
			self.attemptHistoryFetch(newerHistory: false) { success in
				handler?(success: success)
			}
		}
	}

	/**
	Get more history, if no other history request is already running.
	*/
	func attemptHistoryFetch(newerHistory newerHistory: Bool, afterFetch: ((success: Bool) -> Void)? = nil) {
		guard !isRefreshing else {
			afterFetch?(success: false)
			return
		}
		isRefreshing = true

		isFetchingOlder = !newerHistory
		fetchMoreHistory(newer: newerHistory) { success, fetchedCount, error in
			if fetchedCount > 0 {
				self.removeExcessLocalHistory(fromBottom: newerHistory)
			}
			afterFetch?(success: success)
			if let err = error {
				let title = "Unable to get \(newerHistory ? "newer" : "older") song history"
				var message: String?
				if ErrorInfo.isRequestTimedOut(err) {
					message = "The request timed out - check your network connection"
				}
				Utility.presentAlert(title, message: message)
			}
			self.isRefreshing = false
		}
	}

	/**
	Get newer (or older) song history.

	- Parameters:
	- newer: If true, fetch newer history, else fetch older history
	- forDate: base date from which newer or older history will be fetched
	- completionHandler: handler to call after history fetched (or in case of failure)
	*/
	func fetchMoreHistory(newer newer: Bool, forDate: NSDate? = nil, completionHandler: RPFetchResultHandler? = nil) {

		extremitySong(newest: newer) { limitSong in
			var baseDate: NSDate
			if let song = limitSong {
				baseDate = song.playedAt
			} else {
				baseDate = NSDate()
			}

			// Avoid trying to fetch history earlier than the known limit:
			guard baseDate.earlierDate(Constant.RADIO_PARADISE_MINIMUM_HISTORY_DATE) != baseDate else {
				completionHandler?(success: true, fetchedCount: 0, error: nil)
				return
			}

			var vectorCount = self.userSettings.historyFetchSongCount
			if !newer || limitSong == nil {
				vectorCount = -vectorCount
			}
			self.updateWithHistoryFromDate(baseDate, vectorCount: vectorCount, purgeBeforeUpdating: false, completionHandler: completionHandler)
		}
	}

	/**
	Fetches song history and inserts the fetched data into the local store.
	*/
	func updateWithHistoryFromDate(date: NSDate, vectorCount: Int, purgeBeforeUpdating: Bool = false, completionHandler: RPFetchResultHandler? = nil ) {
		/**
		This method handles the data returned from the fetchNewer() or fetchOlder() calls.

		If a song list is returned, it triggers the saving of those songs.

		It calls the RPFetchResultsHandler completionHandler, if present.
		*/
		func songProcessingHandler(playedSongs: [PlayedSongData]?, error: NSError?, response: NSHTTPURLResponse?) {
			guard error == nil else {
				completionHandler?(success: false, fetchedCount: 0,	error: error)
				return
			}

			guard let songHistory = playedSongs else {
				let status = "playedSong list is unexpectedly nil"
				print(status)

				completionHandler?(
					success: false,
					fetchedCount: 0,
					error: NSError(domain: "PlayedSongDataManager", code: 1, userInfo: [NSLocalizedDescriptionKey: status])
				)
				return
			}

			guard songHistory.count > 0 else {
				completionHandler?(success: true, fetchedCount: 0, error: nil)
				return
			}

			if purgeBeforeUpdating {
				removeAllHistory()
			}

			PlayedSong.upsertSongs(songHistory, context: self.context, onlyInserts: purgeBeforeUpdating)
			completionHandler?(success: true, fetchedCount: songHistory.count, error: nil)
		}

		RadioParadise.fetchHistory(userSettings.spotifyRegion, date: date, vectorCount: vectorCount, handler: songProcessingHandler)
	}

	/**
	Replace local history with the history from the given date, if the history fetch is successful.
	*/
	func replaceLocalHistory(newDate: NSDate, handler:(success: Bool) -> Void) {
		guard !isRefreshing else {
			print("replaceHistory: abandoning refresh because a refresh is already running")
			handler(success: false)
			return
		}

		isRefreshing = true
		isFetchingOlder = false

		updateWithHistoryFromDate(newDate, vectorCount: -userSettings.historyFetchSongCount, purgeBeforeUpdating: true) { success, fetchedCount, error in
			self.isRefreshing = false
			guard error == nil else {
				let title = "Unable to get song history for selected data"
				var message: String?
				if ErrorInfo.isRequestTimedOut(error!) {
					message = "The request timed out - check your network connection"
				}
				Utility.presentAlert(title, message: message)
				handler(success: false)
				return
			}
			self.refresh() { error in
				guard error == nil else {
					print("replaceLocalHistory: error refreshing fetch request: \(error)")
					handler(success: false)
					return
				}
				handler(success: success)
			}
		}
	}

	/**
	If almost at the last row, trigger pulling more data.
	
	The function returns true if refresh was triggered, false otherwise
	*/
	func loadMoreIfNearLastRow(row: Int) -> Bool {
		guard !isRefreshing else {
			// Only one refresh at a time.
			return false
		}
		if isNearlyLastRow(row) {
			self.attemptHistoryFetch(newerHistory: false)
			return true
		}
		return false
	}

	func isNearlyLastRow(row: Int) -> Bool {
		return row == songCount - 8
	}

	/**
	If, after a fetch, there are too many songs in local storage, remove the excess from
	the other side (e.g. if refresh was done at the top, remove songs from the bottom of
	the tableview).
	*/
	func removeExcessLocalHistory(fromBottom fromBottom: Bool) {

		// TODO possibly: optimization: use a bulk delete action for this (bulk delete actions do not fire notifications
		//                though, so it might require refreshing the tableview / fetchedResultsController.

		let maxHistoryCount = userSettings.maxLocalSongHistoryCount

		let currentSongCount = songCount
		guard currentSongCount > maxHistoryCount else {
			// No need to do anything.
			return
		}

		context.performBlock {
			guard let songs = self.fetchedResultsController.fetchedObjects as? [PlayedSong] else {
				print("removeExcessLocalHistory: unable to get PlayedSong objects")
				return
			}

			let toBeDeleted: Range<Int>

			if fromBottom {
				toBeDeleted = (maxHistoryCount - 1)...(currentSongCount - 1)
			} else {
				toBeDeleted = 0...(currentSongCount - maxHistoryCount)
			}

			for index in toBeDeleted {
				let song = songs[index]
				self.context.deleteObject(song)
			}
		}
	}

	func removeAllHistory() {
		let fetchRequest = NSFetchRequest(entityName: "PlayedSong")
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

		context.performBlockAndWait {
			do {
				try self.context.executeRequest(deleteRequest)
			} catch {
				print("Unable to bulk delete all PlayedSong history: \(error)")
				return
			}
		}
		CoreDataStack.saveContext(self.context, waitForChildContext: true)
	}


	/**
	Calls handler with a AudioPlayerPlaylist of songs that have associated Spotify tracks, centered around the given indexPath.
	
	If the song at indexPath does not have a Spotify track, an empty AudioPlayerPlaylist will be returned.
	*/
	func trackListCenteredAtIndexPath(indexPath: NSIndexPath, maxElements: Int, handler: (list: AudioPlayerPlaylist) -> Void) {

		guard songCount > 0 else {
			handler(list: AudioPlayerPlaylist(list: [], currentIndex: 0))
			return
		}

		var laterList = [PlayedSongData]()  // for songs with a playedAt date after the center song
		var earlierList = [PlayedSongData]() // for songs with a playedAt date before the center song

		context.performBlock {
			guard let centerSong = self.fetchedResultsController.objectAtIndexPath(indexPath) as? PlayedSong where centerSong.spotifyTrackId != nil else {
				handler(list: AudioPlayerPlaylist(list: [], currentIndex: 0))
				return
			}

			var desiredElements = maxElements - 1
			let maxRow = self.songCount - 1
			var laterRow = indexPath.row - 1
			var earlierRow = indexPath.row + 1
			var hasEarlier = earlierRow <= maxRow
			var hasLater = laterRow >= 0

			// Because of the FRC's sort order, songs played at a later date come earlier in the list of objects.
			// Not all songs have an associated Spotify track.
			// Starting from the center song, fetch a pair of (earlier, later) songs with a Spotify track,
			// as far as possible.  If the earliest or latest available song is reached, but there are still
			// more songs available on the other side (earlier or later), continue fetching those songs (this
			// may result in the "centerSong" not really being in the center).
			while desiredElements > 0 && (hasEarlier || hasLater) {
				var laterAdded = false

				while hasLater && !laterAdded {
					let path = NSIndexPath(forRow: laterRow, inSection: indexPath.section)
					if let song = self.fetchedResultsController.objectAtIndexPath(path) as? PlayedSong where song.spotifyTrackId != nil {
						laterList.append(PlayedSongData(song: song))
						laterAdded = true
						desiredElements--
					}
					laterRow--
					hasLater = laterRow >= 0
				}
				if desiredElements == 0 {
					continue
				}

				var earlierAdded = false
				while hasEarlier && !earlierAdded {
					let path = NSIndexPath(forRow: earlierRow, inSection: indexPath.section)
					if let song = self.fetchedResultsController.objectAtIndexPath(path) as? PlayedSong where song.spotifyTrackId != nil {
						earlierList.append(PlayedSongData(song: song))
						earlierAdded = true
						desiredElements--
					}
					earlierRow++
					hasEarlier = earlierRow <= maxRow
				}
			}
			var playList = Array(earlierList.reverse())
			playList.append(PlayedSongData(song: centerSong))
			let songIndex = playList.count - 1
			playList += laterList
			handler(list: AudioPlayerPlaylist(list: playList, currentIndex: songIndex))
		}

	}

	/**
	Get an array of track ids, starting with the given index path, and going towards more recent objects.
	*/
	func trackIdsStartingAtIndexPath(indexPath: NSIndexPath, maxCount: Int = SpotifyClient.MAX_PLAYER_TRACK_COUNT) -> [String] {
		var trackIds = [String]()
		let section = indexPath.section
		var trackCount = 0
		var row = indexPath.row
		context.performBlockAndWait {
			repeat {
				let path = NSIndexPath(forRow: row, inSection: section)
				if let song = self.fetchedResultsController.objectAtIndexPath(path) as? PlayedSong, trackId = song.spotifyTrackId {
					trackIds.append(trackId)
					trackCount++
				}
				row--
			} while trackCount < maxCount && row >= 0
		}
		return trackIds
	}

	/**
	Get the newest (or oldest) song.
	*/
	func extremitySong(newest newest: Bool, handler: (PlayedSong?) -> Void) {
		guard let fetchedObjects = self.fetchedResultsController.fetchedObjects where fetchedObjects.count > 0 else {
			handler(nil)
			return
		}
		context.performBlock {
			if newest {
				handler(fetchedObjects[0] as? PlayedSong)
			} else {
				handler(fetchedObjects[fetchedObjects.count - 1] as? PlayedSong)
			}
		}
	}

	func currentSongData(ascendingDate: Bool = true) -> [PlayedSongData] {
		var songData = [PlayedSongData]()
		context.performBlockAndWait {
			for song in self.fetchedResultsController.fetchedObjects as! [PlayedSong] {
				songData.append(PlayedSongData(song: song))
			}
		}
		if ascendingDate {
			return songData.reverse()
		}
		return songData
	}
}

// MARK: UITableViewDataSource helpers

extension PlayedSongDataManager {

	func numberOfRowsInSection(section: Int) -> Int {
		// From what I've read, it is safe to access fetched result controller sections
		// without using the context's thread.
		return self.fetchedResultsController.sections?[section].numberOfObjects ?? 0
	}

	/**
	Gets the object at the index path.
	
	Note that this should only be called from withing the context's performBlock(AndWait) closure.
	*/
	func objectAtIndexPath(indexPath: NSIndexPath) -> PlayedSong? {
		return self.fetchedResultsController.objectAtIndexPath(indexPath) as? PlayedSong
	}

	/**
	Gets a PlayedSongData object for the given index path.
	
	This method uses the context's performBlockAndWait method.
	*/
	func songDataForObjectAtIndexPath(indexPath: NSIndexPath) -> PlayedSongData? {
		var songData: PlayedSongData? = nil
		context.performBlockAndWait {
			if let song = self.objectAtIndexPath(indexPath) {
				songData = PlayedSongData(song: song)
			}
		}
		return songData
	}
}