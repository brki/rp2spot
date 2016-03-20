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
	@IBOutlet weak var tableView: UITableView!
	@IBOutlet weak var instructionsLabel: UILabel!

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
		instructionsLabel.backgroundColor = Constant.Color.LightGrey.color()
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
	}

	func tableView(tableView: UITableView, didDeselectRowAtIndexPath indexPath: NSIndexPath) {
		localPlaylist.toggleSelection(indexPath.row)
		tableView.cellForRowAtIndexPath(indexPath)?.accessoryType = .None
	}

	func scrollViewDidScroll(scrollView: UIScrollView) {
		instructionsHidden = tableView.contentOffset.y > 0
	}
}