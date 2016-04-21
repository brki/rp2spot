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
	@IBOutlet weak var dateSelectionButton: UIBarButtonItem!
	@IBOutlet weak var dateSelectorActivityIndicator: UIActivityIndicatorView!
	@IBOutlet weak var centerActivityIndicator: UIActivityIndicatorView!

	var refreshManager: ScrollViewRefreshManager!

	lazy var historyData: PlayedSongDataManager = {
		return PlayedSongDataManager(fetchedResultsControllerDelegate:self,
			context: CoreDataStack.childContextForContext(CoreDataStack.sharedInstance.managedObjectContext))
	}()

	var insertIndexPaths = [NSIndexPath]()
	var deleteIndexPaths = [NSIndexPath]()
	var updateIndexPaths = [NSIndexPath]()

	var currentlyPlayingTrackId: String?

	var shouldScrollPlayingSongCellToVisible = false

	var audioPlayerVC: AudioPlayerViewController!

	var userSettings = UserSetting.sharedInstance

	var refreshControlsEnabled = true {
		didSet {
			let enabled = refreshControlsEnabled
			async_main {
				self.refreshManager.inactiveControlsEnabled = enabled
				// The top control should remain disabled if there is no earlier history:
				if enabled {
					self.refreshManager.topRefreshControl?.enabled = self.historyData.hasEarlierHistory()
				}
				self.dateSelectionButton.enabled = enabled
			}
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.rowHeight = 64
		tableView.dataSource = self
		tableView.delegate = self

		setupRefreshControls()

		historyData.refresh() { error in

			// If there is no song history yet, load the latest songs.
			self.centerActivityIndicator.startAnimating()

			self.historyData.loadLatestIfEmpty() { success in
				async_main {

					self.centerActivityIndicator.stopAnimating()

					self.tableView.reloadData()

					// Try to restore the history view that the user had when they left the app.
					let topRow = self.userSettings.historyBrowserTopVisibleRow
					if  topRow != 0  && topRow < self.historyData.songCount {
						self.tableView.scrollToRowAtIndexPath(
							NSIndexPath(forRow: topRow, inSection: 0),
							atScrollPosition: .Top,
							animated: false
						)
					}

				}
			}
		}

	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)

		if !historyData.isRefreshing {

			// If the maximum local history count has been reduced, discard extra rows.
			historyData.removeExcessLocalHistory(fromBottom: false)
		}

		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(self.willResignActive(_:)), name: UIApplicationWillResignActiveNotification, object: nil)
	}

	override func viewWillDisappear(animated: Bool) {
		super.viewWillDisappear(animated)
		saveTopVisibleRow()
		NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationWillResignActiveNotification, object: nil)
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		let destinationVC = segue.destinationViewController

		if let identifier = segue.identifier where identifier == "BrowserToPlaylistCreation",
			let navController = destinationVC as? UINavigationController,
			vc = navController.topViewController as? PlaylistViewController {

			let songData = historyData.dataForSpotifyTracks()
			vc.localPlaylist = LocalPlaylistSongs(songs: songData)

			for cell in tableView.visibleCells as! [PlainHistoryTableViewCell] {
				if let _ = cell.spotifyTrackId, indexPath = tableView.indexPathForCell(cell) {
					let song = historyData.songDataForObjectAtIndexPath(indexPath)
					vc.firstVisibleDate = song?.playedAt
					break
				}
			}

		} else if let vc = destinationVC as? AudioPlayerViewController {

			audioPlayerVC = vc
			audioPlayerVC.delegate = self

		} else if let vc = destinationVC as? SongInfoViewController {

			guard let cell = sender as? UITableViewCell,
				indexPath = tableView.indexPathForCell(cell),
				songData = historyData.songDataForObjectAtIndexPath(indexPath) else {
					print("Unable to get song data for selected row for showing detail view")
					return
			}
			vc.songInfo = songData
		}
	}

	@IBAction func selectDate(sender: UIBarButtonItem) {
		guard let datePickerVC = storyboard?.instantiateViewControllerWithIdentifier("HistoryDateSelectorViewController") as? HistoryDateSelectorViewController else {
			return
		}

		datePickerVC.modalPresentationStyle = .OverCurrentContext
		let displayDate = historyData.extremityDateInList(newest: true) ?? NSDate()
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

	@IBAction func prepareForUnwind(segue: UIStoryboardSegue) {
		// Nothing to do here, but this method needs to exist so that the exit segues can be created from other View controllers.
	}

	func hidePlayer() {
		self.playerContainerViewHeightConstraint.constant = 0
	}

	func showPlayer() {
		self.playerContainerViewHeightConstraint.constant = 120
	}

	func willResignActive(notification: NSNotification) {
		saveTopVisibleRow()
	}

	/**
	Save the index of the topmost visible row, so that it can be restored when the app restarts.
	*/
	func saveTopVisibleRow() {
		if let indexPaths = tableView.indexPathsForVisibleRows where indexPaths.count > 0 {
			userSettings.historyBrowserTopVisibleRow = indexPaths[0].row
		} else {
			userSettings.historyBrowserTopVisibleRow = 0
		}
	}
}


extension HistoryBrowserViewController: DateSelectionAcceptingProtocol {
	func dateSelected(date: NSDate) {

		// Disable refresh controls while refresh running
		refreshControlsEnabled = false

		dateSelectorActivityIndicator.startAnimating()

		historyData.replaceLocalHistory(date) { success in
			async_main {

				// Re-enable refresh controls.
				self.refreshControlsEnabled = true

				self.dateSelectorActivityIndicator.stopAnimating()

				// If there is new data, reload it.

				if success {
					self.tableView.reloadData()

					// Reposition at the bottom of the table, where the selected date is.
					let rowCount = self.historyData.songCount
					if rowCount > 0 {
						self.tableView.scrollToRowAtIndexPath(
							NSIndexPath(forRow: rowCount - 1, inSection: 0),
							atScrollPosition: .Bottom,
							animated: true
						)
					}
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


extension HistoryBrowserViewController: AudioStatusObserver {
	func playerStatusChanged(newStatus: AudioPlayerViewController.PlayerStatus) {
		if newStatus == .Active {
			async_main {
				self.shouldScrollPlayingSongCellToVisible = true
				self.showPlayer()
			}
		} else {
			async_main {
				self.hidePlayer()
				// trackStoppedPlaying() was already called, but the track that was
				// playing might have been hidden underneath the player at that time,
				// and might still be highlighted as the currently playing track.
				// Reload all visible rows to ensure that no row remains highlighted as playing.
				if let visibleIndexPaths = self.tableView.indexPathsForVisibleRows {
					self.tableView.reloadRowsAtIndexPaths(visibleIndexPaths, withRowAnimation: .Automatic)
				}
			}
		}
	}

	func trackStartedPlaying(spotifyShortTrackId: String) {
		currentlyPlayingTrackId = spotifyShortTrackId
		updatePlayingStatusOfVisibleCell(spotifyShortTrackId, isPlaying: true)
	}

	func trackStoppedPlaying(spotifyShortTrackId: String) {
		currentlyPlayingTrackId = nil
		updatePlayingStatusOfVisibleCell(spotifyShortTrackId, isPlaying: false)
	}

	/**
	Inspect the currently visisble cells.  If one of them has a matching track id,
	trigger a reload, so that it's playing status will be updated.
	*/
	func updatePlayingStatusOfVisibleCell(trackId: String, isPlaying: Bool) {
		async_main {
			let ensurePlayingCellVisible = self.shouldScrollPlayingSongCellToVisible
			self.shouldScrollPlayingSongCellToVisible = false

			guard let indexPaths = self.tableView.indexPathsForVisibleRows where indexPaths.count > 0 else {
				return
			}

			for path in indexPaths {
				if let cell = self.tableView.cellForRowAtIndexPath(path) as? PlainHistoryTableViewCell where cell.spotifyTrackId == trackId {
					self.tableView.reloadRowsAtIndexPaths([path], withRowAnimation: .Fade)
					return
				}
			}

			guard ensurePlayingCellVisible else {
				return
			}

			// No visible cell found.
			// If the player just appeared, it may have covered the visible cell.  Try to find the playing cell and scroll it into view.
			let lastVisibleRow = indexPaths.last!.row
			let section = indexPaths.last!.section
			// The height of the player is 120, the playing cell can be at most 3 cells beyond the last visible cell.
			let maxRowToTry = min(lastVisibleRow + 3, self.historyData.songCount - 1)
			let searchIndexPaths = Array(lastVisibleRow + 1 ... maxRowToTry).map({ NSIndexPath(forRow: $0, inSection: section) })
			if let indexPath = self.historyData.indexPathWithMatchingTrackId(trackId, inIndexPaths: searchIndexPaths) {
				self.tableView.scrollToRowAtIndexPath(indexPath, atScrollPosition: .Bottom, animated: true)
			}
		}
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

		case .Update:
			updateIndexPaths.append(indexPath!)

		default:
			print("Unexpected change type in controllerDidChangeContent: \(type.rawValue), indexPath: \(indexPath), newIndexPath: \(newIndexPath), object: \(anObject)")
		}
	}

	/**
	Apply all changes that have been collected.
	*/
	func controllerDidChangeContent(controller: NSFetchedResultsController) {
		// When adding items to the end of the table view, there is a noticeable flicker and small jump unless
		// the table view insert / delete animations are suppressed.
		let disableRowAnimations = historyData.isFetchingNewer

		if disableRowAnimations {
			CATransaction.begin()
			CATransaction.setDisableActions(true)
		}

		tableView.beginUpdates()

		let rowsToDelete = deleteIndexPaths.removeAllReturningValues()
		tableView.insertRowsAtIndexPaths(insertIndexPaths.removeAllReturningValues(), withRowAnimation: .None)
		tableView.deleteRowsAtIndexPaths(rowsToDelete, withRowAnimation: .None)
		tableView.reloadRowsAtIndexPaths(updateIndexPaths.removeAllReturningValues(), withRowAnimation: .None)

		if historyData.isFetchingNewer {
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

		if let songData = historyData.songDataForObjectAtIndexPath(indexPath) {
			cell.configureForSong(songData, currentlyPlayingTrackId: currentlyPlayingTrackId)
		}


		// The following code is currently commented out because I'm unsure that it makes for a better user experience,
		// but am not ready to throw it away yet.  Perhaps it should be an option for the user to enable / disable
		// this behaviour for the top / bottom / both ends of the history table.

		// If user has scrolled almost all the way down to the last row, try to fetch more song history.
//		if !historyData.isRefreshing && historyData.isNearlyLastRow(indexPath.row) {
//			refreshManager.bottomRefreshControl!.enabled = false
//			historyData.attemptHistoryFetch(newerHistory: true) { success in
//				self.refreshManager.bottomRefreshControl!.enabled = true
//			}
//		}

		return cell
	}

	func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return historyData.numberOfRowsInSection(section)
	}
}


// MARK: UITableViewDelegate methods

extension HistoryBrowserViewController: UITableViewDelegate {

	func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		// Only Spotify Premium accounts can stream music.
		guard userSettings.canStreamSpotifyTracks != false else {
			return
		}

		// If selected row has no spotify track, do not start playing
		historyData.context.performBlock {

			guard self.historyData.objectAtIndexPath(indexPath)?.spotifyTrackId != nil else {
				return
			}

			self.historyData.trackListWithSelectedIndex(indexPath) { playlist in

				guard playlist.list.count > 0 else {
					print("Empty playlist: nothing to play")
					return
				}

				self.audioPlayerVC.playTracks(playlist)
			}
		}
	}
}


// MARK: custom top / bottom refresh controls

extension HistoryBrowserViewController {

	func setupRefreshControls() {
		refreshManager = ScrollViewRefreshManager(tableView: tableView)
		refreshManager.backgroundView.backgroundColor = Constant.Color.LightGrey.color()
		refreshManager.addRefreshControl(.Top, target: self, refreshAction: #selector(self.refreshWithOlderHistory))
		refreshManager.addRefreshControl(.Bottom, target: self, refreshAction: #selector(self.refreshWithNewerHistory))
	}

	func refreshWithNewerHistory() {
		refreshControlsEnabled = false
		historyData.attemptHistoryFetch(newerHistory: true) { success in
			self.refreshControlsEnabled = true
			self.refreshManager.bottomRefreshControl!.didFinishRefreshing(self.tableView)
		}
	}

	func refreshWithOlderHistory() {
		self.refreshControlsEnabled = false
		historyData.attemptHistoryFetch(newerHistory: false) { success in
			self.refreshControlsEnabled = true
			self.refreshManager.topRefreshControl!.didFinishRefreshing(self.tableView)
		}
	}

	func enableTopControlIfEarlierHistoryExists() {
		refreshManager.topRefreshControl!.enabled = historyData.hasEarlierHistory()
	}

	// MARK: UITableViewDelegate actions that need to be communicated to the refresh manager:

	func scrollViewDidEndDragging(scrollView: UIScrollView, willDecelerate decelerate: Bool) {
		refreshManager.didEndDragging(scrollView)
	}

	func scrollViewWillBeginDragging(scrollView: UIScrollView) {
		refreshManager.willBeginDragging(scrollView)
	}

	func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
		refreshManager.didEndDecelerating(scrollView)
	}
}
