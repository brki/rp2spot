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
	var firstVisibleDate: Foundation.Date?

	@IBOutlet weak var tableView: UITableView!
	@IBOutlet weak var nextButton: UIBarButtonItem!

	override func viewDidLoad() {
		tableView.rowHeight = 64
		tableView.dataSource = self
		tableView.delegate = self
		let lightGrey = Constant.Color.lightGrey.color()
		tableView.backgroundColor = lightGrey
	}

	override func viewWillAppear(_ animated: Bool) {
		// Scroll to a song with the date firstVisibleDate, if set:
		if let date = firstVisibleDate,
			let index = localPlaylist.songs.index(where: { (date as NSDate).earlierDate($0.playedAt) == date }) {

			// Unset the variable, so the table won't get scrolled back
			// to this point if it the view re-appears (e.g. user
			// taps the back button from the next view controller).
			firstVisibleDate = nil

			let indexPath = IndexPath(row: index, section: 0)
			tableView.scrollToRow(at: indexPath, at: .top, animated: false)
		}

		nextButton.isEnabled = localPlaylist.selected.count > 0
	}

	@IBAction func cancel(_ sender: AnyObject) {
		dismiss(animated: true, completion: nil)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: sender)
		let destinationVC = segue.destination
		if let vc = destinationVC as? PlaylistCreationViewController {
			vc.localPlaylist = localPlaylist
		}
	}
}

extension PlaylistViewController: UITableViewDataSource {

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "PlaylistCell", for: indexPath) as! PlaylistTableViewCell
		configureCell(cell, indexPath: indexPath)
		return cell
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return localPlaylist.songs.count
	}

	func configureCell(_ cell: PlaylistTableViewCell, indexPath: IndexPath) {
		let (songData, selected) = localPlaylist.songAtIndex(indexPath.row)
		cell.configureForSong(songData, selected: selected)
	}
}

extension PlaylistViewController: UITableViewDelegate {
	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		localPlaylist.toggleSelection(indexPath.row)
		tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
		nextButton.isEnabled = true
	}

	func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
		localPlaylist.toggleSelection(indexPath.row)
		tableView.cellForRow(at: indexPath)?.accessoryType = .none
		nextButton.isEnabled = localPlaylist.selected.count > 0
	}
}
