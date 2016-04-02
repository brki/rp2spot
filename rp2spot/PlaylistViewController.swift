//
//  PlaylistViewController.swift
//  rp2spot
//
//  Created by Brian on 14/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

class PlaylistViewController: UIViewController {
	var localPlaylist: LocalPlaylistSongs!
	var firstVisibleDate: NSDate?

	@IBOutlet weak var tableView: UITableView!
	@IBOutlet weak var instructionsLabel: UILabel!
	@IBOutlet weak var nextButton: UIBarButtonItem!

	var instructionsHidden: Bool = false {
		didSet {
			if oldValue != instructionsHidden {
				showOrHideInstructions(instructionsHidden)
			}
		}
	}

	override func viewDidLoad() {
		tableView.rowHeight = 64
		tableView.dataSource = self
		tableView.delegate = self
		let lightGrey = Constant.Color.LightGrey.color()
		tableView.backgroundColor = lightGrey
		instructionsLabel.backgroundColor = lightGrey
	}

	override func viewWillAppear(animated: Bool) {
		// Scroll to a song with the date firstVisibleDate, if set:
		if let date = firstVisibleDate,
			index = localPlaylist.songs.indexOf({ date.earlierDate($0.playedAt) == date }) {

			// Unset the variable, so the table won't get scrolled back
			// to this point if it the view re-appears (e.g. user
			// taps the back button from the next view controller).
			firstVisibleDate = nil

			let indexPath = NSIndexPath(forRow: index, inSection: 0)
			tableView.scrollToRowAtIndexPath(indexPath, atScrollPosition: .Top, animated: false)
		}

		nextButton.enabled = localPlaylist.selected.count > 0
	}

	override func viewDidAppear(animated: Bool) {
		super.viewDidAppear(animated)
		instructionsHidden = false
	}

	@IBAction func cancel(sender: AnyObject) {
		dismissViewControllerAnimated(true, completion: nil)
	}

	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		super.prepareForSegue(segue, sender: sender)
		let destinationVC = segue.destinationViewController
		if let vc = destinationVC as? PlaylistCreationViewController {
			vc.localPlaylist = localPlaylist
		}
	}

	func showOrHideInstructions(hide: Bool) {
		let targetAlpha = hide ? 0.0 : 1.0
		UIView.animateWithDuration(0.5) {
			self.instructionsLabel.alpha = CGFloat(targetAlpha)
		}
	}
}

extension PlaylistViewController: UITableViewDataSource {

	func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("PlaylistCell", forIndexPath: indexPath) as! PlaylistTableViewCell
		configureCell(cell, indexPath: indexPath)
		return cell
	}

	func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return localPlaylist.songs.count
	}

	func configureCell(cell: PlaylistTableViewCell, indexPath: NSIndexPath) {
		let (songData, selected) = localPlaylist.songAtIndex(indexPath.row)
		cell.configureForSong(songData, selected: selected)
	}
}

extension PlaylistViewController: UITableViewDelegate {
	func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		localPlaylist.toggleSelection(indexPath.row)
		tableView.cellForRowAtIndexPath(indexPath)?.accessoryType = .Checkmark
		nextButton.enabled = true
	}

	func tableView(tableView: UITableView, didDeselectRowAtIndexPath indexPath: NSIndexPath) {
		localPlaylist.toggleSelection(indexPath.row)
		tableView.cellForRowAtIndexPath(indexPath)?.accessoryType = .None
		nextButton.enabled = localPlaylist.selected.count > 0
	}

	func scrollViewDidScroll(scrollView: UIScrollView) {
		instructionsHidden = tableView.contentOffset.y > 0
	}
}