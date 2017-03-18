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

	lazy var fetchedResultsController: NSFetchedResultsController<NSFetchRequestResult> = {
		// TODO: clarify why conversion added this:
		// () -> <<error type>> in
		var frc: NSFetchedResultsController<NSFetchRequestResult>!
		self.context.performAndWait {
			let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "PlayedSong")
			fetchRequest.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: true)]
			frc = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: self.context, sectionNameKeyPath: nil, cacheName: nil)

		}
		frc.delegate = self.fetchedResultsControllerDelegate
		return frc
	}()

	/**
	(Re)fetch the data for the fetchedResultsController.
	*/
	func refresh(_ handler: @escaping (NSError?) -> Void) {
		context.perform {
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

	func loadLatestIfEmpty(_ handler: ((_ success: Bool) -> Void)? = nil) {
		guard songCount == 0 else {
			handler?(true)
			return
		}
		context.perform {
			self.attemptHistoryFetch(newerHistory: false) { success in
				handler?(success)
			}
		}
	}

	/**
	Get more history, if no other history request is already running.
	*/
	func attemptHistoryFetch(newerHistory: Bool, afterFetch: ((_ success: Bool) -> Void)? = nil) {
		guard !isRefreshing else {
			afterFetch?(false)
			return
		}
		isRefreshing = true

		isFetchingNewer = newerHistory
		fetchMoreHistory(newer: newerHistory) { success, fetchedCount, error in
			if fetchedCount > 0 {
				self.removeExcessLocalHistory(fromBottom: !newerHistory)
			}
			afterFetch?(success)
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
	- completionHandler: handler to call after history fetched (or in case of failure)
	*/
	func fetchMoreHistory(newer: Bool, completionHandler: RPFetchResultHandler? = nil) {

		let now = Foundation.Date()
		let baseDate = extremityDateInList(newest: newer) ?? now

		// Avoid trying to fetch history earlier than the known limit:
		guard !isDateEarlierThanLimit(baseDate) else {
			completionHandler?(true, 0, nil)
			return
		}

		var vectorCount = self.userSettings.historyFetchSongCount

		// baseDate will be equal to now if there are no songs in the list.
		if !newer || baseDate == now {
			vectorCount = -vectorCount
		}

		self.updateWithHistoryFromDate(baseDate, vectorCount: vectorCount, purgeBeforeUpdating: false, completionHandler: completionHandler)
	}

	func extremityDateInList(newest: Bool = true) -> Foundation.Date? {
		return extremitySongData(newest: newest)?.playedAt
	}

	func hasEarlierHistory() -> Bool {
		let earliestDateInList = extremityDateInList(newest: false) ?? Foundation.Date()
		return !isDateEarlierThanLimit(earliestDateInList)
	}

	func isDateEarlierThanLimit(_ date: Foundation.Date) -> Bool {
		return (date as NSDate).earlierDate(Constant.RADIO_PARADISE_MINIMUM_HISTORY_DATE) == date
	}

	/**
	Fetches song history and inserts the fetched data into the local store.
	*/
	func updateWithHistoryFromDate(_ date: Foundation.Date, vectorCount: Int, purgeBeforeUpdating: Bool = false, completionHandler: RPFetchResultHandler? = nil ) {
		/**
		This method handles the data returned from the fetchNewer() or fetchOlder() calls.

		If a song list is returned, it triggers the saving of those songs.

		It calls the RPFetchResultsHandler completionHandler, if present.
		*/
		func songProcessingHandler(_ playedSongs: [PlayedSongData]?, error: NSError?, response: HTTPURLResponse?) {
			guard error == nil else {
				completionHandler?(false, 0,	error)
				return
			}

			guard let songHistory = playedSongs else {
				let status = "playedSong list is unexpectedly nil"
				print(status)

				completionHandler?(
					false,
					0,
					NSError(domain: "PlayedSongDataManager", code: 1, userInfo: [NSLocalizedDescriptionKey: status])
				)
				return
			}

			guard songHistory.count > 0 else {
				completionHandler?(true, 0, nil)
				return
			}

			if purgeBeforeUpdating {
				removeAllHistory()
			}

			PlayedSong.upsertSongs(songHistory, context: self.context, onlyInserts: purgeBeforeUpdating)
			completionHandler?(true, songHistory.count, nil)
		}

		_ = RadioParadise.fetchHistory(userSettings.spotifyRegionValue, date: date, vectorCount: vectorCount, handler: songProcessingHandler)
	}

	/**
	Replace local history with the history from the given date, if the history fetch is successful.
	*/
	func replaceLocalHistory(_ newDate: Foundation.Date, handler:@escaping (_ success: Bool) -> Void) {
		guard !isRefreshing else {
			print("replaceHistory: abandoning refresh because a refresh is already running")
			handler(false)
			return
		}

		isRefreshing = true
		isFetchingNewer = false

		updateWithHistoryFromDate(newDate, vectorCount: -Constant.RADIO_PARADISE_REFRESH_SONG_COUNT, purgeBeforeUpdating: true) { success, fetchedCount, error in
			guard error == nil else {
				let title = "Unable to get song history for selected time"
				var message: String?
				if error!.domain == NSURLErrorDomain {
					message = error!.localizedDescription
				}
				Utility.presentAlert(title, message: message)
				handler(false)
				self.isRefreshing = false
				return
			}
			self.refresh() { error in
				guard error == nil else {
					print("replaceLocalHistory: error refreshing fetch request: \(error)")
					handler(false)
					self.isRefreshing = false
					return
				}
				handler(success)
				self.isRefreshing = false
			}
		}
	}

	func isNearlyLastRow(_ row: Int) -> Bool {
		return row == songCount - 8
	}

	/**
	If, after a fetch, there are too many songs in local storage, remove the excess from
	the other side (e.g. if refresh was done at the top, remove songs from the bottom of
	the tableview).
	*/
	func removeExcessLocalHistory(fromBottom: Bool) {

		// A possible optimiation would be to use a bulk delete action for this (bulk delete
		// actions do not fire notifications  though, so it might require refreshing the
		// tableview / fetchedResultsController.

		let maxHistoryCount = userSettings.maxLocalSongHistoryCount

		context.perform {

			let currentSongCount = self.songCount

			guard currentSongCount > maxHistoryCount else {
				// No need to do anything.
				return
			}
			
			guard let songs = self.fetchedResultsController.fetchedObjects as? [PlayedSong] else {
				print("removeExcessLocalHistory: unable to get PlayedSong objects")
				return
			}

			let toBeDeleted: CountableClosedRange<Int>

			if fromBottom {
				toBeDeleted = (maxHistoryCount - 1)...(currentSongCount - 1)
			} else {
				toBeDeleted = 0...(currentSongCount - maxHistoryCount)
			}

			for index in toBeDeleted {
				let song = songs[index]
				self.context.delete(song)
			}
		}
	}

	func removeAllHistory() {
		let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "PlayedSong")
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

		context.performAndWait {
			do {
				try self.context.execute(deleteRequest)
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
	func trackListWithSelectedIndex(_ indexPath: IndexPath, handler: @escaping (_ list: AudioPlayerPlaylist) -> Void) {
		guard songCount > 0 else {
			handler(AudioPlayerPlaylist(list: [], currentIndex: 0))
			return
		}

		context.perform {
			// If the selected song has no Spotify track, just return an empty list.
			guard let selectedSong = self.fetchedResultsController.object(at: indexPath) as? PlayedSong, selectedSong.spotifyTrackId != nil else {
				handler(AudioPlayerPlaylist(list: [], currentIndex: 0))
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

			handler(AudioPlayerPlaylist(list: songData, currentIndex: selectedIndex))
		}
	}

	/**
	Get the newest (or oldest) song.
	*/
	func extremitySongData(newest: Bool) -> PlayedSongData? {
		var song: PlayedSongData?

		guard let fetchedObjects = self.fetchedResultsController.fetchedObjects, fetchedObjects.count > 0 else {
			return nil
		}

		context.performAndWait {
			var selectedSong: PlayedSong?
			if newest {
				selectedSong = fetchedObjects[fetchedObjects.count - 1] as? PlayedSong
			} else {
				selectedSong = fetchedObjects[0] as? PlayedSong
			}

			if let selected = selectedSong {
				song = PlayedSongData.init(song: selected)
			}
		}
		return song
	}

	func dataForSpotifyTracks() -> [PlayedSongData] {
		var songData = [PlayedSongData]()
		context.performAndWait {
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

	func numberOfRowsInSection(_ section: Int) -> Int {
		// From what I've read, it is safe to access fetched result controller sections
		// without using the context's thread.
		return self.fetchedResultsController.sections?[section].numberOfObjects ?? 0
	}

	/**
	Gets the object at the index path.
	
	Note that this should only be called from withing the context's performBlock(AndWait) closure.
	*/
	func objectAtIndexPath(_ indexPath: IndexPath) -> PlayedSong? {
		return self.fetchedResultsController.object(at: indexPath) as? PlayedSong
	}

	/**
	Gets a PlayedSongData object for the given index path.
	
	This method uses the context's performBlockAndWait method.
	*/
	func songDataForObjectAtIndexPath(_ indexPath: IndexPath) -> PlayedSongData? {
		var songData: PlayedSongData? = nil
		context.performAndWait {
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
	func indexPathWithMatchingUniqueId(_ uniqueId: String, inIndexPaths indexPaths: [IndexPath]) -> IndexPath? {
		var matchingPath: IndexPath?
		context.performAndWait {
			for indexPath in indexPaths {
				if let song = self.objectAtIndexPath(indexPath), song.uniqueId == uniqueId {
					matchingPath = indexPath
					break
				}
			}
		}
		return matchingPath
	}
}
