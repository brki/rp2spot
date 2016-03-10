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
	var isRefreshing = false

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
	func refresh() {
		context.performBlockAndWait {
			do {
				try self.fetchedResultsController.performFetch()
			} catch {
				print("HistoryViewController: error on fetchedResultsController.performFetch: \(error)")
			}
		}
	}

	func saveContext() {
		self.context.performBlock {
			CoreDataStack.sharedInstance.saveContext()
		}
	}

	func loadLatestIfEmpty() {
		if (fetchedResultsController.fetchedObjects?.count ?? 0) == 0 {
			attemptHistoryFetch(newerHistory: false)
		}
	}

	/**
	Get more history, if no other history request is already running.
	*/
	func attemptHistoryFetch(newerHistory newerHistory: Bool, afterFetch: ((success: Bool) -> Void)? = nil) {
		defer {
			objc_sync_exit(self)
		}
		objc_sync_enter(self)
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
			objc_sync_enter(self)
			self.isRefreshing = false
			objc_sync_exit(self)
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

		var baseDate: NSDate
		let limitSong = extremitySong(newer)
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

		var vectorCount = userSettings.historyFetchSongCount
		if !newer || limitSong == nil {
			vectorCount = -vectorCount
		}
		updateWithHistoryFromDate(baseDate, vectorCount: vectorCount, purgeBeforeUpdating: false, completionHandler: completionHandler)
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
					error: NSError(domain: "HistoryViewController", code: 1, userInfo: [NSLocalizedDescriptionKey: status])
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
		defer {
			objc_sync_exit(self)
		}
		objc_sync_enter(self)
		guard !isRefreshing else {
			print("replaceHistory: abandoning refresh because a refresh is already running")
			handler(success: false)
			return
		}

		isRefreshing = true
		isFetchingOlder = false

		updateWithHistoryFromDate(newDate, vectorCount: -userSettings.historyFetchSongCount, purgeBeforeUpdating: true) { success, fetchedCount, error in
			if let err = error {
				let title = "Unable to get song history for selected data"
				var message: String?
				if ErrorInfo.isRequestTimedOut(err) {
					message = "The request timed out - check your network connection"
				}
				Utility.presentAlert(title, message: message)
			} else {
				self.refresh()
			}
			handler(success: success)
			objc_sync_enter(self)
			self.isRefreshing = false
			objc_sync_exit(self)
		}
	}

	func loadMoreIfNearLastRow(row: Int) {
		guard !isRefreshing else {
			// Only one refresh at a time.
			return
		}
		isNearlyLastRow(row) { isNearlyLast in
			if isNearlyLast {
				self.attemptHistoryFetch(newerHistory: false)
			}
		}
	}

	func isNearlyLastRow(row: Int, handler:(Bool) -> Void) {
		context.performBlock {
			if let fetchedObjects = self.fetchedResultsController.fetchedObjects {
				handler(row == fetchedObjects.count - 10)
			}
			handler(false)
		}
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

		context.performBlock {
			guard let songCount = self.fetchedResultsController.fetchedObjects?.count where songCount > maxHistoryCount else {
				// No need to do anything.
				return
			}
			guard let songs = self.fetchedResultsController.fetchedObjects as? [PlayedSong] else {
				print("removeExcessLocalHistory: unable to get PlayedSong objects")
				return
			}

			let toBeDeleted: Range<Int>

			if fromBottom {
				toBeDeleted = (maxHistoryCount - 1)...(songCount - 1)
			} else {
				toBeDeleted = 0...(songCount - maxHistoryCount)
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
		CoreDataStack.sharedInstance.saveContext()
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
	func extremitySong(newest: Bool) -> PlayedSong? {
		var song: PlayedSong?
		if let fetchedObjects = fetchedResultsController.fetchedObjects where fetchedObjects.count > 0 {
			context.performBlockAndWait {
				if newest {
					song = fetchedObjects[0] as? PlayedSong
				} else {
					song = fetchedObjects[fetchedObjects.count - 1] as? PlayedSong
				}
			}
		}
		return song
	}
}

// MARK: UITableViewDataSource helpers

extension PlayedSongDataManager {

	func numberOfRowsInSection(section: Int) -> Int {
		var numRows = 0
		context.performBlockAndWait {
			if let sections = self.fetchedResultsController.sections {
				numRows = sections[section].numberOfObjects
			}
		}
		return numRows
	}

	func objectAtIndexPath(indexPath: NSIndexPath) -> PlayedSong? {
		var song: PlayedSong? = nil
		context.performBlockAndWait {
			song = self.fetchedResultsController.objectAtIndexPath(indexPath) as? PlayedSong
		}
		return song
	}
}