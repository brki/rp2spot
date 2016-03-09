//
//  HistoryBrowserViewController.swift
//  rp2spot
//
//  Created by Brian King on 07/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit
import CoreData
import AlamofireImage

typealias RPFetchResultHandler = (success: Bool, fetchedCount: Int, error: NSError?) -> Void

class HistoryBrowserViewController: UIViewController {

	@IBOutlet weak var tableView: UITableView!
	@IBOutlet weak var playerContainerViewHeightConstraint: NSLayoutConstraint!

	let tableViewController = UITableViewController()
	let refreshControl = UIRefreshControl()

	let context = CoreDataStack.sharedInstance.managedObjectContext

	let userSettings = UserSetting.sharedInstance

	var isFetchingOlder = false

	var isRefreshing = false

	var insertIndexPaths = [NSIndexPath]()
	var deleteIndexPaths = [NSIndexPath]()

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
		tableView.dataSource = self
		tableView.delegate = self
		refreshFetchRequest()
		setupRefreshControl()

		// If there is no song history yet, load the latest songs.
		if (fetchedResultsController.fetchedObjects?.count ?? 0) == 0 {
			attemptHistoryFetch(newerHistory: false)
		}
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
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

	func setupRefreshControl() {
		// Configure refresh control for the top of the table view.
		// A tableViewController is required to use the UIRefreshControl.
		refreshControl.attributedTitle = NSAttributedString(string: "Pull to refresh")
		refreshControl.addTarget(self, action: "refreshRequested:", forControlEvents: .ValueChanged)

		addChildViewController(tableViewController)
		tableViewController.tableView = tableView
		tableViewController.refreshControl = refreshControl
	}

	func refreshRequested(sender: UIRefreshControl) {
		attemptHistoryFetch(newerHistory: true) { success in
			sender.endRefreshing()
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

extension HistoryBrowserViewController: DateSelectionAcceptingProtocol {
	func dateSelected(date: NSDate) {
		replaceLocalHistory(date)
	}
}

extension HistoryBrowserViewController: UIPopoverPresentationControllerDelegate {
	func adaptivePresentationStyleForPresentationController(controller: UIPresentationController) -> UIModalPresentationStyle {
		return .None
	}
}

extension HistoryBrowserViewController: NSFetchedResultsControllerDelegate {

	/**
	Collects the changes that have been made.

	The changes are collected for later processing (instead of directly calling tableView.insertRowsAtIndexPaths()
	and related methods in this function) so that all the code for the CATransaction is called in one method - see
	controllerDidChangeContent() for more details on why a CATransaction is used.
	*/
	func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {

		switch type {
		case .Delete:
			deleteIndexPaths.append(indexPath!)

		case .Insert:
			insertIndexPaths.append(newIndexPath!)

		default:
			print("Unexpected change type in controllerDidChangeContent: \(type.rawValue), indexPath: \(indexPath), newIndexPath: \(newIndexPath), object: \(anObject)")
		}
	}

	/**
	Apply all changes that have been collected.
	*/
	func controllerDidChangeContent(controller: NSFetchedResultsController) {

		let disableRowAnimations = isFetchingOlder

		if disableRowAnimations {
			// When adding items to the end of the table view, there is a noticeable flicker and small jump unless
			// the table view insert / delete animations are suppressed.
			CATransaction.begin()
			CATransaction.setDisableActions(true)
		}

		tableView.beginUpdates()

		let rowsToDelete = deleteIndexPaths.removeAllReturningValues()
		tableView.insertRowsAtIndexPaths(insertIndexPaths.removeAllReturningValues(), withRowAnimation: .None)
		tableView.deleteRowsAtIndexPaths(rowsToDelete, withRowAnimation: .None)

		if isFetchingOlder {
			// If rows above have been deleted at the top of the table view, shift the current contenteOffset up an appropriate amount:
			tableView.contentOffset = CGPointMake(tableView.contentOffset.x, tableView.contentOffset.y - tableView.rowHeight * CGFloat(rowsToDelete.count))
		}

		tableView.endUpdates()

		if disableRowAnimations {
			CATransaction.commit()
		}

		self.context.performBlock {
			CoreDataStack.sharedInstance.saveContext()
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


extension HistoryBrowserViewController: UITableViewDataSource {
	func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("HistoryBrowserCell", forIndexPath: indexPath) as! PlainHistoryTableViewCell

		if let song = fetchedResultsController.objectAtIndexPath(indexPath) as? PlayedSong {
			cell.configureForSong(song)
		}

		// If user has scrolled almost all the way down to the last row, try to fetch some older song history.
		loadMoreIfNearLastRow(indexPath.row)

		return cell
	}

	func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if let sections = fetchedResultsController.sections {
			return sections[section].numberOfObjects
		} else {
			return 0
		}
	}
}

// MARK: UITableViewDelegate methods
extension HistoryBrowserViewController: UITableViewDelegate {

	func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
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
				// TODO: show player
				self.playerContainerViewHeightConstraint.constant = 100
				SpotifyClient.sharedInstance.playTracks(trackIds)
			}
		}
	}
}
