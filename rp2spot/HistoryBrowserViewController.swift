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

typealias RPFetchResultHandler = (_ success: Bool, _ fetchedCount: Int, _ error: NSError?) -> Void

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

	var insertIndexPaths = [IndexPath]()
	var deleteIndexPaths = [IndexPath]()
	var updateIndexPaths = [IndexPath]()

	var currentlyPlayingTrackId: String?

	var shouldScrollPlayingSongCellToVisible = false

	var audioPlayerVC: AudioPlayerViewController!

	var userSettings = UserSetting.sharedInstance

	var refreshControlsEnabled = true {
		didSet {
			let enabled = refreshControlsEnabled
			DispatchQueue.main.async {
				self.refreshManager.inactiveControlsEnabled = enabled
				// The top control should remain disabled if there is no earlier history:
				if enabled {
					self.refreshManager.topRefreshControl?.enabled = self.historyData.hasEarlierHistory()
				}
				self.dateSelectionButton.isEnabled = enabled
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
				DispatchQueue.main.async {

					self.centerActivityIndicator.stopAnimating()

					self.tableView.reloadData()

					// Try to restore the history view that the user had when they left the app.
					let topRow = self.userSettings.historyBrowserTopVisibleRow
					if  topRow != 0  && topRow < self.historyData.songCount {
						self.tableView.scrollToRow(
							at: IndexPath(row: topRow, section: 0),
							at: .top,
							animated: false
						)
					}

				}
			}
		}

	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		if !historyData.isRefreshing {

			// If the maximum local history count has been reduced, discard extra rows.
			historyData.removeExcessLocalHistory(fromBottom: false)
		}

		NotificationCenter.default.addObserver(self, selector: #selector(self.willResignActive(_:)), name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		saveTopVisibleRow()
		NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		let destinationVC = segue.destination

		if let identifier = segue.identifier, identifier == "BrowserToPlaylistCreation",
			let navController = destinationVC as? UINavigationController,
			let vc = navController.topViewController as? PlaylistViewController {

			let songData = historyData.dataForSpotifyTracks()
			vc.localPlaylist = LocalPlaylistSongs(songs: songData)

			for cell in tableView.visibleCells as! [PlainHistoryTableViewCell] {
				if let _ = cell.spotifyTrackId, let indexPath = tableView.indexPath(for: cell) {
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
				let indexPath = tableView.indexPath(for: cell),
				let songData = historyData.songDataForObjectAtIndexPath(indexPath) else {
					print("Unable to get song data for selected row for showing detail view")
					return
			}
			vc.songInfo = songData
		}
	}

	@IBAction func selectDate(_ sender: UIBarButtonItem) {
		guard let datePickerVC = storyboard?.instantiateViewController(withIdentifier: "HistoryDateSelectorViewController") as? HistoryDateSelectorViewController else {
			return
		}

		datePickerVC.modalPresentationStyle = .overCurrentContext
		let displayDate = historyData.extremityDateInList(newest: true) ?? Foundation.Date()
		datePickerVC.startingDate = displayDate
		datePickerVC.delegate = self

		DispatchQueue.main.async {
			self.present(datePickerVC, animated: true, completion: nil)

			guard let popover = datePickerVC.popoverPresentationController else {
				return
			}
			popover.permittedArrowDirections = .up
			popover.barButtonItem = sender
			popover.delegate = self
		}
	}

	@IBAction func prepareForUnwind(_ segue: UIStoryboardSegue) {
		// Nothing to do here, but this method needs to exist so that the exit segues can be created from other View controllers.
	}

	func hidePlayer() {
		self.playerContainerViewHeightConstraint.constant = 0
	}

	func showPlayer() {
		self.playerContainerViewHeightConstraint.constant = 120
	}

	func willResignActive(_ notification: Notification) {
		saveTopVisibleRow()
	}

	/**
	Save the index of the topmost visible row, so that it can be restored when the app restarts.
	*/
	func saveTopVisibleRow() {
		if let indexPaths = tableView.indexPathsForVisibleRows, indexPaths.count > 0 {
			userSettings.historyBrowserTopVisibleRow = indexPaths[0].row
		} else {
			userSettings.historyBrowserTopVisibleRow = 0
		}
	}
}


extension HistoryBrowserViewController: DateSelectionAcceptingProtocol {
	func dateSelected(_ date: Foundation.Date) {

		// Disable refresh controls while refresh running
		refreshControlsEnabled = false

		dateSelectorActivityIndicator.startAnimating()

		historyData.replaceLocalHistory(date) { success in
			DispatchQueue.main.async {

				// Re-enable refresh controls.
				self.refreshControlsEnabled = true

				self.dateSelectorActivityIndicator.stopAnimating()

				// If there is new data, reload it.

				if success {
					self.tableView.reloadData()

					// Reposition at the bottom of the table, where the selected date is.
					let rowCount = self.historyData.songCount
					if rowCount > 0 {
						self.tableView.scrollToRow(
							at: IndexPath(row: rowCount - 1, section: 0),
							at: .bottom,
							animated: true
						)
					}
				}
			}
		}
	}
}


extension HistoryBrowserViewController: UIPopoverPresentationControllerDelegate {
	func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
		return .none
	}
}


extension HistoryBrowserViewController: AudioStatusObserver {
	func playerStatusChanged(_ newStatus: AudioPlayerViewController.PlayerStatus) {
		if newStatus == .active {
			DispatchQueue.main.async {
				self.shouldScrollPlayingSongCellToVisible = true
				self.showPlayer()
			}
		} else {
			DispatchQueue.main.async {
				self.hidePlayer()
				// trackStoppedPlaying() was already called, but the track that was
				// playing might have been hidden underneath the player at that time,
				// and might still be highlighted as the currently playing track.
				// Reload all visible rows to ensure that no row remains highlighted as playing.
				if let visibleIndexPaths = self.tableView.indexPathsForVisibleRows {
					self.tableView.reloadRows(at: visibleIndexPaths, with: .automatic)
				}
			}
		}
	}

	func trackStartedPlaying(_ spotifyShortTrackId: String) {
		currentlyPlayingTrackId = spotifyShortTrackId
		updatePlayingStatusOfVisibleCell(spotifyShortTrackId, isPlaying: true)
	}

	func trackStoppedPlaying(_ spotifyShortTrackId: String) {
		currentlyPlayingTrackId = nil
		updatePlayingStatusOfVisibleCell(spotifyShortTrackId, isPlaying: false)
	}

	/**
	Inspect the currently visisble cells.  If one of them has a matching track id,
	trigger a reload, so that it's playing status will be updated.
	*/
	func updatePlayingStatusOfVisibleCell(_ trackId: String, isPlaying: Bool) {
		DispatchQueue.main.async {
			let ensurePlayingCellVisible = self.shouldScrollPlayingSongCellToVisible
			self.shouldScrollPlayingSongCellToVisible = false

			guard let indexPaths = self.tableView.indexPathsForVisibleRows, indexPaths.count > 0 else {
				return
			}

			for path in indexPaths {
				if let cell = self.tableView.cellForRow(at: path) as? PlainHistoryTableViewCell, cell.spotifyTrackId == trackId {
					self.tableView.reloadRows(at: [path], with: .fade)
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
			let searchIndexPaths = Array(lastVisibleRow + 1 ... maxRowToTry).map({ IndexPath(row: $0, section: section) })
			if let indexPath = self.historyData.indexPathWithMatchingTrackId(trackId, inIndexPaths: searchIndexPaths) {
				self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
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
	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

		switch type {
		case .delete:
			deleteIndexPaths.append(indexPath!)

		case .insert:
			insertIndexPaths.append(newIndexPath!)

		case .update:
			updateIndexPaths.append(indexPath!)

		default:
			print("Unexpected change type in controllerDidChangeContent: \(type.rawValue), indexPath: \(indexPath), newIndexPath: \(newIndexPath), object: \(anObject)")
		}
	}

	/**
	Apply all changes that have been collected.
	*/
	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		// When adding items to the end of the table view, there is a noticeable flicker and small jump unless
		// the table view insert / delete animations are suppressed.
		let disableRowAnimations = historyData.isFetchingNewer

		if disableRowAnimations {
			CATransaction.begin()
			CATransaction.setDisableActions(true)
		}

		tableView.beginUpdates()

		let rowsToDelete = deleteIndexPaths.removeAllReturningValues()
		tableView.insertRows(at: insertIndexPaths.removeAllReturningValues(), with: .none)
		tableView.deleteRows(at: rowsToDelete, with: .none)
		tableView.reloadRows(at: updateIndexPaths.removeAllReturningValues(), with: .none)

		if historyData.isFetchingNewer {
			// If rows above have been deleted at the top of the table view, shift the current contenteOffset up an appropriate amount:
			tableView.contentOffset = CGPoint(x: tableView.contentOffset.x, y: tableView.contentOffset.y - tableView.rowHeight * CGFloat(rowsToDelete.count))
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
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryBrowserCell", for: indexPath) as! PlainHistoryTableViewCell

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

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return historyData.numberOfRowsInSection(section)
	}
}


// MARK: UITableViewDelegate methods

extension HistoryBrowserViewController: UITableViewDelegate {

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		// Only Spotify Premium accounts can stream music.
		guard userSettings.canStreamSpotifyTracks != false else {
			return
		}

		// If selected row has no spotify track, do not start playing
		historyData.context.perform {

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
		refreshManager.backgroundView.backgroundColor = Constant.Color.lightGrey.color()
		refreshManager.addRefreshControl(.top, target: self, refreshAction: #selector(self.refreshWithOlderHistory))
		refreshManager.addRefreshControl(.bottom, target: self, refreshAction: #selector(self.refreshWithNewerHistory))
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

	func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
		refreshManager.didEndDragging(scrollView)
	}

	func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		refreshManager.willBeginDragging(scrollView)
	}

	func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
		refreshManager.didEndDecelerating(scrollView)
	}
}
