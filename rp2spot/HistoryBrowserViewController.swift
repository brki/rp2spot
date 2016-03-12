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
	@IBOutlet weak var playerContainerView: UIView!

	let tableViewController = UITableViewController()
	let refreshControl = UIRefreshControl()

	lazy var historyData: PlayedSongDataManager = {
		return PlayedSongDataManager(fetchedResultsControllerDelegate:self,
			context: CoreDataStack.sharedInstance.managedObjectContext)
	}()

	var insertIndexPaths = [NSIndexPath]()
	var deleteIndexPaths = [NSIndexPath]()

	var audioPlayerVC: AudioPlayerViewController!

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.rowHeight = 64
		tableView.dataSource = self
		tableView.delegate = self
		historyData.refresh() { error in
			// If there is no song history yet, load the latest songs.
			self.historyData.loadLatestIfEmpty() { success in
				async_main {
					self.setupRefreshControl()
					self.tableView.reloadData()
				}
			}
		}
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		if let vc = segue.destinationViewController as? AudioPlayerViewController {
			audioPlayerVC = vc
		}
	}

	@IBAction func selectDate(sender: UIBarButtonItem) {
		guard let datePickerVC = storyboard?.instantiateViewControllerWithIdentifier("HistoryDateSelectorViewController") as? HistoryDateSelectorViewController else {
			return
		}

		datePickerVC.modalPresentationStyle = .OverCurrentContext

		historyData.extremitySong(newest: true) { newestSong in
			let displayDate = newestSong?.playedAt ?? NSDate()
			datePickerVC.startingDate = displayDate
			datePickerVC.delegate = self

			async_main {
				self.presentViewController(datePickerVC, animated: true, completion: nil)

				guard let popover = datePickerVC.popoverPresentationController else {
					return
				}
				popover.permittedArrowDirections = .Up
				popover.barButtonItem = sender
				popover.delegate = self
			}
		}
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
		historyData.attemptHistoryFetch(newerHistory: true) { success in
			async_main {
				sender.endRefreshing()
			}
		}
	}
}

extension HistoryBrowserViewController: DateSelectionAcceptingProtocol {
	func dateSelected(date: NSDate) {
		historyData.replaceLocalHistory(date) { success in
			if success {
				async_main {
					self.tableView.reloadData()
					self.tableView.contentOffset = CGPointMake(0, 0 - self.tableView.contentInset.top)
				}

			}
		}
	}
}

extension HistoryBrowserViewController: UIPopoverPresentationControllerDelegate {
	func adaptivePresentationStyleForPresentationController(controller: UIPresentationController) -> UIModalPresentationStyle {
		return .None
	}
}


// MARK: NSFetchedResultsControllerDelegate

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

		let disableRowAnimations = historyData.isFetchingOlder

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

		if historyData.isFetchingOlder {
			// If rows above have been deleted at the top of the table view, shift the current contenteOffset up an appropriate amount:
			tableView.contentOffset = CGPointMake(tableView.contentOffset.x, tableView.contentOffset.y - tableView.rowHeight * CGFloat(rowsToDelete.count))
		}

		tableView.endUpdates()

		if disableRowAnimations {
			CATransaction.commit()
		}

		historyData.saveContext()
	}
}


// MARK: UITableViewDataSource methods

extension HistoryBrowserViewController: UITableViewDataSource {
	func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("HistoryBrowserCell", forIndexPath: indexPath) as! PlainHistoryTableViewCell

		if let song = historyData.objectAtIndexPath(indexPath) {
			cell.configureForSong(song)
		}

		// If user has scrolled almost all the way down to the last row, try to fetch some older song history.
		historyData.loadMoreIfNearLastRow(indexPath.row)

		return cell
	}

	func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return historyData.numberOfRowsInSection(section)
	}
}


// MARK: UITableViewDelegate methods

extension HistoryBrowserViewController: UITableViewDelegate {

	func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		// If selected row has no spotify track, do not start playing
		guard historyData.objectAtIndexPath(indexPath)?.spotifyTrackId != nil else {
			return
		}

		historyData.trackListCenteredAtIndexPath(indexPath, maxElements: Constant.AUDIO_PLAYER_MAX_TRACK_LIST_SIZE) { playList in

			guard playList.list.count > 0 else {
				print("Empty playlist: nothing to play")
				return
			}

			// TODO: handle the container view resizing better:
			async_main {
				self.playerContainerViewHeightConstraint.constant = 100
			}

			self.audioPlayerVC.playTracks(playList)
		}
	}
}