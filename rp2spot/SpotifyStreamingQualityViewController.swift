//
//  SpotifyStreamingQualityViewController.swift
//  rp2spot
//
//  Created by Brian on 18.03.17.
//  Copyright © 2017 truckin'. All rights reserved.
//

import CleanroomLogger

class SpotifyStreamingQualityViewController: UITableViewController {
	@IBOutlet weak var SpotifyStreamingQualityLowCell: UITableViewCell!
	@IBOutlet weak var SpotifyStreamingQualityNormalCell: UITableViewCell!
	@IBOutlet weak var SpotifyStreamingQualityHighCell: UITableViewCell!

	lazy var streamingQualityMap: [(SPTBitrate, UITableViewCell)] = [
		(SPTBitrate.low, self.SpotifyStreamingQualityLowCell),			// row 0
		(SPTBitrate.normal, self.SpotifyStreamingQualityNormalCell),	// row 1
		(SPTBitrate.high, self.SpotifyStreamingQualityHighCell)			// row 2
	]
	let SECTION_SPOTIFY_STREAMING_QUALITY = 0

	let settings = UserSetting.sharedInstance
	var networkType: UserSetting.NetworkType!

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.backgroundColor = Constant.Color.lightGrey.color()
		configureSpotifyStreamingQualityCells()
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		switch indexPath.section {
		case SECTION_SPOTIFY_STREAMING_QUALITY:
			let (quality, _) = streamingQualityMap[indexPath.row]
			let previousQuality = settings.spotifyStreamingQuality(forType: networkType)
			if quality != previousQuality {
				settings.setSpotifyStreamingQuality(quality, forType: networkType)
				configureSpotifyStreamingQualityCells()
				SpotifyClient.sharedInstance.updateDesiredBitRate() { error in
					if error != nil {
						Log.warning?.message("Error setting target bit rate: \(error!)")
						self.settings.setSpotifyStreamingQuality(previousQuality, forType: self.networkType)
						self.configureSpotifyStreamingQualityCells()
					}
				}
			}
		default:
			break
		}
	}

	func configureSpotifyStreamingQualityCells() {
		let settingQuality = settings.spotifyStreamingQuality(forType: networkType)
		for (quality, cell) in streamingQualityMap {
			if quality == settingQuality {
				cell.accessoryType = .checkmark
			} else {
				cell.accessoryType = .none
			}
		}
	}
}
