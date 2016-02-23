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

class HistoryViewController: UITableViewController {

	let context = CoreDataStack.sharedInstance.managedObjectContext

	let albumThumbnailFilter =  AspectScaledToFillSizeWithRoundedCornersFilter(
		size: CGSize(width: 128, height: 128),
		radius: 15.0
	)

	let albumThumbnailPlaceholder = UIImage(named: "vinyl")

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.rowHeight = 64
		refreshFetchRequest()
		refreshSongHistory()
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	lazy var fetchedResultsController: NSFetchedResultsController = {
		var frc: NSFetchedResultsController!
		self.context.performBlockAndWait {
			let fetchRequest = NSFetchRequest(entityName: "PlayedSong")
			fetchRequest.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: false)]
			frc = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: self.context, sectionNameKeyPath: nil, cacheName: nil)
		}
		return frc
	}()

	@IBAction func refreshRequested(sender: UIRefreshControl) {
		refreshSongHistory()
		sender.endRefreshing()
	}

	func refreshSongHistory() {
		var fromDate: NSDate?
		if let fetchedObjects = fetchedResultsController.fetchedObjects where fetchedObjects.count > 0 {
			context.performBlockAndWait {
				// If the last locally available song was broadcast less than a day ago, refresh only since that song.
				if let song = fetchedObjects[0] as? PlayedSong {
					let oneDayAgo = Date.sharedInstance.oneDayAgo()
					if song.playedAt.earlierDate(oneDayAgo) == oneDayAgo {
						fromDate = song.playedAt
					}
				}
			}
		}
		fetchRPSongs(fromDate)
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

	func fetchRPSongs(fromDate: NSDate? = nil, toDate: NSDate? = nil, completionHandler: ((success: Bool, fetchedCount: Int, error: NSError?) -> Void)? = nil) {
		RadioParadise.fetchPeriod("CH", fromDate: fromDate, toDate: toDate) { playedSongs, error, response in
			print("error: \(error)")  // on network timeout: Error Domain=NSURLErrorDomain Code=-1001 "The request timed out."
			print("response: \(response)")  // NSURLHTTPResponse

			guard let songHistory = playedSongs else {
				let status = "playedSong list is unexpectedly nil"
				print(status)

				completionHandler?(
					success: false,
					fetchedCount: 0,
					error: NSError(domain: "HistoryViewController", code: 1, userInfo: [NSLocalizedDescriptionKey: status]))

				return
			}

			guard songHistory.count > 0 else {
				completionHandler?(success: true, fetchedCount: 0, error: nil)
				return
			}

			PlayedSong.upsertSongs(songHistory, context: self.context)
			completionHandler?(success: true, fetchedCount: songHistory.count, error: nil)

			// TODO: remove songs from the store if the max-song-count constant exceeded.
			// TODO: make the max-song-count constant a configurable variable.
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
}


// MARK: UITableViewDataSource methods

extension HistoryViewController {
	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("PlainSongHistoryCell", forIndexPath: indexPath) as! PlainHistoryTableViewCell
		if let song = fetchedResultsController.objectAtIndexPath(indexPath) as? PlayedSong {

			var imageURL: NSURL?
			var spotifyTrackAvailable = false
			context.performBlockAndWait {
				cell.songTitle.text = song.title
				cell.artist.text = song.artistName
				cell.date.text = song.playedAt.description // TODO: use a date format w/ user's locale settings
				if let imageURLText = song.smallImageURL, spotifyImageURL = NSURL(string: imageURLText) {
					imageURL = spotifyImageURL
				} else if let asin = song.asin, radioParadiseImageURL = NSURL(string: RadioParadise.imageURLText(asin, size: .Medium)) {
					imageURL = radioParadiseImageURL
				}
				spotifyTrackAvailable = song.spotifyTrackId != nil
			}

			if let url = imageURL {
				cell.albumImageView.af_setImageWithURL(url, placeholderImage: albumThumbnailPlaceholder, filter: albumThumbnailFilter)
			} else {
				cell.albumImageView.image = albumThumbnailPlaceholder
			}

			if spotifyTrackAvailable {
				cell.backgroundColor = Constant.Color.SageGreen.color()
			} else {
				cell.backgroundColor = Constant.Color.LightGrey.color()
			}
		}
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