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

	enum CurrentlyFetchingType: Int {
		case None, Top, Bottom
	}

	let context = CoreDataStack.sharedInstance.managedObjectContext

	let userSettings = UserSetting.sharedInstance

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
	Get newer (or older) song history.
	*/
	func fetchMoreHistory(newer newer: Bool, completionHandler: RPFetchResultHandler? = nil) {

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

			PlayedSong.upsertSongs(songHistory, context: self.context)
			completionHandler?(success: true, fetchedCount: songHistory.count, error: nil)
		}

		var limitDate: NSDate
		let limitSong = extremitySong(newer)
		if let song = limitSong {
			limitDate = song.playedAt
		} else {
			limitDate = NSDate()
		}

		// If there is no limitSong there are no songs, so use the fetchOlder() method, which will result in some
		// songs being loaded.  An alternative would have been to calculate some time back from now and call
		// fetchNewer(), but the result is the same.
		if newer && limitSong != nil {
			RadioParadise.fetchNewer(userSettings.spotifyRegion, newerThan: limitDate, handler: songProcessingHandler)
		} else {
			RadioParadise.fetchOlder(userSettings.spotifyRegion, olderThan: limitDate, handler: songProcessingHandler)
		}
	}

	func attemptHistoryFetch(newerHistory newerHistory: Bool, afterFetch: ((success: Bool) -> Void)? = nil) {
		fetchMoreHistory(newer: newerHistory) { success, fetchedCount, error in
			afterFetch?(success: success)
			if let err = error {
				let title = "Unable to get \(newerHistory ? "newer" : "older") song history"
				var message: String?
				if ErrorInfo.isRequestTimedOut(err) {
					message = "The request timed out - check your network connection"
				}
				Utility.presentAlert(title, message: message)
			}
		}
	}

	func loadMoreIfAtLastRow(row: Int) {
		if isLastRow(row) {
			attemptHistoryFetch(newerHistory: false)
		}
	}
}

extension HistoryViewController: NSFetchedResultsControllerDelegate {

	func controllerWillChangeContent(controller: NSFetchedResultsController) {
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

	func isLastRow(row: Int) -> Bool {
		if let fetchedObjects = fetchedResultsController.fetchedObjects {
			return row == fetchedObjects.count - 1
		}
		return false
	}
}


// MARK: UITableViewDataSource methods

extension HistoryViewController {
	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("PlainSongHistoryCell", forIndexPath: indexPath) as! PlainHistoryTableViewCell

		if let song = fetchedResultsController.objectAtIndexPath(indexPath) as? PlayedSong {
			cell.configureForSong(song)
		}

		// If user has scrolled all the way down to the last row, try to fetch some older song history.
		loadMoreIfAtLastRow(indexPath.row)

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
}