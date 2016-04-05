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
	var isFetchingNewer = false
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
			fetchRequest.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: true)]
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

		isFetchingNewer = newerHistory
		fetchMoreHistory(newer: newerHistory) { success, fetchedCount, error in
			if fetchedCount > 0 {
				self.removeExcessLocalHistory(fromBottom: !newerHistory)
			}
			afterFetch?(success: success)
			if let err = error {
				let title = "Unable to get \(newerHistory ? "newer" : "older") song history"
				var message: String?

				// If it's a network error, include the problem description:
				if err.domain == NSURLErrorDomain {
					message = err.localizedDescription
				}

				Utility.presentAlert(title, message: message)
			}
			self.isRefreshing = false
		}
	}

	/**
	Get newer (or older) song history.

	Parameters:
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

		RadioParadise.fetchHistory(userSettings.spotifyRegionValue, date: date, vectorCount: vectorCount, handler: songProcessingHandler)
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
		isFetchingNewer = false

		updateWithHistoryFromDate(newDate, vectorCount: -userSettings.historyFetchSongCount, purgeBeforeUpdating: true) { success, fetchedCount, error in
			guard error == nil else {
				let title = "Unable to get song history for selected data"
				var message: String?
				if ErrorInfo.isRequestTimedOut(error!) {
					message = "The request timed out - check your network connection"
				}
				Utility.presentAlert(title, message: message)
				handler(success: false)
				self.isRefreshing = false
				return
			}
			self.refresh() { error in
				guard error == nil else {
					print("replaceLocalHistory: error refreshing fetch request: \(error)")
					handler(success: false)
					self.isRefreshing = false
					return
				}
				handler(success: success)
				self.isRefreshing = false
			}
		}
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

		// A possible optimiation would be to use a bulk delete action for this (bulk delete
		// actions do not fire notifications  though, so it might require refreshing the
		// tableview / fetchedResultsController.

		let maxHistoryCount = userSettings.maxLocalSongHistoryCount

		context.performBlock {

			let currentSongCount = self.songCount

			guard currentSongCount > maxHistoryCount else {
				// No need to do anything.
				return
			}
			
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
	Creates an AudioPlayerPlaylist with tracks that have a Spotify track id.
	*/
	func trackListWithSelectedIndex(indexPath: NSIndexPath, handler: (list: AudioPlayerPlaylist) -> Void) {
		guard songCount > 0 else {
			handler(list: AudioPlayerPlaylist(list: [], currentIndex: 0))
			return
		}

		context.performBlock {
			// If the selected song has no Spotify track, just return an empty list.
			guard let selectedSong = self.fetchedResultsController.objectAtIndexPath(indexPath) as? PlayedSong where selectedSong.spotifyTrackId != nil else {
				handler(list: AudioPlayerPlaylist(list: [], currentIndex: 0))
				return
			}

			var songData = [PlayedSongData]()
			var selectedIndex = -1
			var index = 0
			for song in self.fetchedResultsController.fetchedObjects as! [PlayedSong] {
				if song.spotifyTrackId != nil {
					if selectedIndex == -1 && song.spotifyTrackId! == selectedSong.spotifyTrackId! {
						selectedIndex = index
					}
					index += 1
					songData.append(PlayedSongData(song: song))
				}
			}

			handler(list: AudioPlayerPlaylist(list: songData, currentIndex: selectedIndex))
		}
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
				handler(fetchedObjects[fetchedObjects.count - 1] as? PlayedSong)
			} else {
				handler(fetchedObjects[0] as? PlayedSong)
			}
		}
	}

	func dataForSpotifyTracks() -> [PlayedSongData] {
		var songData = [PlayedSongData]()
		context.performBlockAndWait {
			for song in self.fetchedResultsController.fetchedObjects as! [PlayedSong] {
				if song.spotifyTrackId != nil {
					songData.append(PlayedSongData(song: song))
				}
			}
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

	/**
	Gets the index path with the matching spotify track id.

	This method uses the context's performBlockAndWait method.
	*/
	func indexPathWithMatchingTrackId(trackId: String, inIndexPaths indexPaths: [NSIndexPath]) -> NSIndexPath? {
		var matchingPath: NSIndexPath?
		context.performBlockAndWait {
			for indexPath in indexPaths {
				if let song = self.objectAtIndexPath(indexPath) where song.spotifyTrackId == trackId {
					matchingPath = indexPath
					break
				}
			}
		}
		return matchingPath
	}
}