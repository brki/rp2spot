//
//  HistoryController.swift
//  rp2spot
//
//  Created by Brian on 03/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit
import CoreData
import AlamofireImage

typealias RPFetchResultHandler = (success: Bool, fetchedCount: Int, error: NSError?) -> Void

// TODO: add concurrency control: only allow one history fetch at once; ignore new history fetch requests if one is already in progress.

class HistoryViewController: UITableViewController {

	enum CurrentRefreshType {
		case Newer, Older
	}

	let context = CoreDataStack.sharedInstance.managedObjectContext

	let userSettings = UserSetting.sharedInstance

	var currentRefresh = CurrentRefreshType.Newer

	var isRefreshing = false

	lazy var fetchedResultsController: NSFetchedResultsController = {
		var frc: NSFetchedResultsController!
		self.context.performBlockAndWait {
			let fetchRequest = NSFetchRequest(entityName: "PlayedSong")
			fetchRequest.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: false)]
			frc = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: self.context, sectionNameKeyPath: nil, cacheName: nil)
		}
		return frc
	}()

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.rowHeight = 64
		refreshFetchRequest()

		// If there is no song history yet, load the latest songs.
		if (fetchedResultsController.fetchedObjects?.count ?? 0) == 0 {
			attemptHistoryFetch(newerHistory: false)
		}
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	@IBAction func refreshRequested(sender: UIRefreshControl) {
		attemptHistoryFetch(newerHistory: true) { success in
			sender.endRefreshing()
		}
	}

	@IBAction func selectDate(sender: UIBarButtonItem) {
		guard let datePickerVC = storyboard?.instantiateViewControllerWithIdentifier("HistoryDateSelectorViewController") as? HistoryDateSelectorViewController else {
			return
		}

		datePickerVC.modalPresentationStyle = .OverCurrentContext
		let displayDate = extremitySong(true)?.playedAt ?? NSDate()
		datePickerVC.startingDate = displayDate
		datePickerVC.delegate = self

		presentViewController(datePickerVC, animated: true, completion: nil)

		guard let popover = datePickerVC.popoverPresentationController else {
			return
		}
		popover.permittedArrowDirections = .Up
		popover.barButtonItem = sender
		popover.delegate = self
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

		currentRefresh = newerHistory ? .Newer : .Older
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
	- newer: should songs
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
	Replace local history with the history from the given date, if the history fetch is successful.
	*/
	func replaceLocalHistory(newDate: NSDate) {
		defer {
			objc_sync_exit(self)
		}
		objc_sync_enter(self)
		guard !isRefreshing else {
			print("replaceHistory: abandoning refresh because a refresh is already running")
			return
		}

		isRefreshing = true
		currentRefresh = .Newer

		updateWithHistoryFromDate(newDate, vectorCount: -userSettings.historyFetchSongCount, purgeBeforeUpdating: true) { success, fetchedCount, error in
			if let err = error {
				let title = "Unable to get song history for selected data"
				var message: String?
				if ErrorInfo.isRequestTimedOut(err) {
					message = "The request timed out - check your network connection"
				}
				Utility.presentAlert(title, message: message)
			} else {
				self.refreshFetchRequest()
				async_main {
					self.tableView.reloadData()
					self.tableView.contentOffset = CGPointMake(0, 0 - self.tableView.contentInset.top)
				}
			}
			objc_sync_enter(self)
			self.isRefreshing = false
			objc_sync_exit(self)
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

	func loadMoreIfNearLastRow(row: Int) {
		if !isRefreshing && isNearlyLastRow(row) {
			attemptHistoryFetch(newerHistory: false)
		}
	}
}

extension HistoryViewController: DateSelectionAcceptingProtocol {
	func dateSelected(date: NSDate) {
		replaceLocalHistory(date)
	}
}

extension HistoryViewController: UIPopoverPresentationControllerDelegate {
	func adaptivePresentationStyleForPresentationController(controller: UIPresentationController) -> UIModalPresentationStyle {
		return .None
	}
}

extension HistoryViewController: NSFetchedResultsControllerDelegate {

	func controllerWillChangeContent(controller: NSFetchedResultsController) {
		if currentRefresh != .Newer {
			// Disable animations to avoid a disconcerting animation effect caused by addition + deletion of rows when at the bottome
			// of the tableview.
			UIView.setAnimationsEnabled(false)
		}
		tableView.beginUpdates()
	}

	func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {

		guard let visiblePaths = tableView.indexPathsForVisibleRows else {
			// No visible paths, no need to update the view.
			return
		}

		switch type {
		case .Update:
			if let path = indexPath where visiblePaths.contains(path) {
				tableView.reloadRowsAtIndexPaths([path], withRowAnimation: .Automatic)
			}

		case .Delete:
			tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation: .Automatic)
			// Adjust position so that deletion of rows at top of tableview after fetching older history
			// for the bottom of tableview does not result in scrolling down, which can trigger repeated fetching
			// of older history when the bottommost row triggers another history fetch.
			// tldr; scroll up when deleting rows:
			tableView.contentOffset = CGPointMake(tableView.contentOffset.x, tableView.contentOffset.y - tableView.rowHeight)

		case .Insert:
			tableView.insertRowsAtIndexPaths([newIndexPath!], withRowAnimation: .Automatic)

		default:
			print("Unexpected change type in controllerDidChangeContent: \(type.rawValue), indexPath: \(indexPath)")
		}
	}

	/**
	Apply all changes that have been collected.
	*/
	func controllerDidChangeContent(controller: NSFetchedResultsController) {
		tableView.endUpdates()
		self.context.performBlock {
			CoreDataStack.sharedInstance.saveContext()
		}
		if !(UIView.areAnimationsEnabled()) {
			// Re-enable animation if it was disabled for a fetch of older items.
			UIView.setAnimationsEnabled(true)
		}
	}

	/**
	(Re)fetch the data for the fetchedResultsController.
	*/
	func refreshFetchRequest() {
		context.performBlockAndWait {
			do {
				try self.fetchedResultsController.performFetch()
				self.fetchedResultsController.delegate = self
			} catch {
				print("HistoryViewController: error on fetchedResultsController.performFetch: \(error)")
			}
		}
	}

	func isNearlyLastRow(row: Int) -> Bool {
		if let fetchedObjects = fetchedResultsController.fetchedObjects {
			return row == fetchedObjects.count - 10
		}
		return false
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
}


// MARK: UITableViewDataSource methods

extension HistoryViewController {
	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("PlainSongHistoryCell", forIndexPath: indexPath) as! PlainHistoryTableViewCell

		if let song = fetchedResultsController.objectAtIndexPath(indexPath) as? PlayedSong {
			cell.configureForSong(song)
		}

		// If user has scrolled almost all the way down to the last row, try to fetch some older song history.
		loadMoreIfNearLastRow(indexPath.row)

		return cell
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if let sections = fetchedResultsController.sections {
			return sections[section].numberOfObjects
		} else {
			return 0
		}
	}
}

// MARK: UITableViewDelegate methods
extension HistoryViewController {

	override func tableView(tableView: UITableView, estimatedHeightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
		return tableView.rowHeight
	}

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		var trackIds = [String]()
		context.performBlockAndWait {
			var lastRow = indexPath.row
			let section = indexPath.section
			if let sections = self.fetchedResultsController.sections {
				lastRow = sections[section].numberOfObjects - 1
			}

			var trackCount = 0
			var row = indexPath.row
			repeat {
				let path = NSIndexPath(forRow: row, inSection: section)
				if let song = self.fetchedResultsController.objectAtIndexPath(path) as? PlayedSong, trackId = song.spotifyTrackId {
					trackIds.append(trackId)
					trackCount++
				} else if row == indexPath.row {
					// Special case for when the tapped on row has no track: do not start player.
					break
				}
				row++
			} while trackCount < SpotifyClient.MAX_PLAYER_TRACK_COUNT && row < lastRow

		}
		if trackIds.count > 0 {
			SpotifyClient.sharedInstance.loginOrRenewSession() { willTriggerNotification, error in
				guard error == nil else {
					print("error while trying to renew session: \(error)")
					return
				}
				// TODO: handle case where a session-update notification will be posted
				SpotifyClient.sharedInstance.playTracks(trackIds)
			}
		}
	}
}