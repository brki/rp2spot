//
//  UserSettingsViewController.swift
//  rp2spot
//
//  Created by Brian King on 29/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

class UserSettingsViewController: UITableViewController {

	@IBOutlet weak var SpotifyStreamingQualityLowCell: UITableViewCell!
	@IBOutlet weak var SpotifyStreamingQualityNormalCell: UITableViewCell!
	@IBOutlet weak var SpotifyStreamingQualityHighCell: UITableViewCell!
	@IBOutlet weak var maximumSongHistoryLabel: UILabel!
	@IBOutlet weak var maximumSongHistoryStepper: UIStepper!
	@IBOutlet weak var fetchSizeLabel: UILabel!
	@IBOutlet weak var fetchSizeStepper: UIStepper!

	let SECTION_SPOTIFY_STREAMING_QUALITY = 0

	lazy var streamingQualityMap: [(SPTBitrate, UITableViewCell)] = [
		(SPTBitrate.Low, self.SpotifyStreamingQualityLowCell),			// row 0
		(SPTBitrate.Normal, self.SpotifyStreamingQualityNormalCell),	// row 1
		(SPTBitrate.High, self.SpotifyStreamingQualityHighCell)			// row 2
	]

	let settings = UserSetting.sharedInstance

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.backgroundColor = Constant.Color.LightGrey.color()

		configureSpotifyStreamingQualityCells()

		configureSongHistoryListControls()
	}

	@IBAction func maximumSongHistoryValueChanged(sender: AnyObject) {
		settings.maxLocalSongHistoryCount = Int(maximumSongHistoryStepper.value)
		maximumSongHistoryLabel.text = String(settings.maxLocalSongHistoryCount)
	}

	@IBAction func fetchSizeValueChanged(sender: AnyObject) {
		settings.historyFetchSongCount = Int(fetchSizeStepper.value)
		fetchSizeLabel.text = String(settings.historyFetchSongCount)
	}

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		switch indexPath.section {
		case SECTION_SPOTIFY_STREAMING_QUALITY:
			let (quality, _) = streamingQualityMap[indexPath.row]
			let previousQuality = settings.spotifyStreamingQuality
			if quality != previousQuality {
				settings.spotifyStreamingQuality = quality
				configureSpotifyStreamingQualityCells()
				SpotifyClient.sharedInstance.player.setTargetBitrate(quality) { error in
					if error != nil {
						self.settings.spotifyStreamingQuality = previousQuality
						self.configureSpotifyStreamingQualityCells()
					}
				}
			}
		default:
			break
		}
	}

	func configureSpotifyStreamingQualityCells() {
		let settingQuality = settings.spotifyStreamingQuality
		for (quality, cell) in streamingQualityMap {
			if quality == settingQuality {
				cell.accessoryType = .Checkmark
			} else {
				cell.accessoryType = .None
			}
		}
	}

	func configureSongHistoryListControls() {
		let maxSongHistoryCount = settings.maxLocalSongHistoryCount
		maximumSongHistoryStepper.value = Double(maxSongHistoryCount)
		maximumSongHistoryLabel.text = String(maxSongHistoryCount)

		let fetchSize = settings.historyFetchSongCount
		fetchSizeStepper.value = Double(fetchSize)
		fetchSizeLabel.text = String(fetchSize)
	}
}