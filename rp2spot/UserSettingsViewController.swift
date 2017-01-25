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
		(SPTBitrate.low, self.SpotifyStreamingQualityLowCell),			// row 0
		(SPTBitrate.normal, self.SpotifyStreamingQualityNormalCell),	// row 1
		(SPTBitrate.high, self.SpotifyStreamingQualityHighCell)			// row 2
	]

	let settings = UserSetting.sharedInstance

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.backgroundColor = Constant.Color.lightGrey.color()

		configureSpotifyStreamingQualityCells()

		configureSongHistoryListControls()
	}

	@IBAction func maximumSongHistoryValueChanged(_ sender: AnyObject) {
		settings.maxLocalSongHistoryCount = Int(maximumSongHistoryStepper.value)
		maximumSongHistoryLabel.text = String(settings.maxLocalSongHistoryCount)
	}

	@IBAction func fetchSizeValueChanged(_ sender: AnyObject) {
		settings.historyFetchSongCount = Int(fetchSizeStepper.value)
		fetchSizeLabel.text = String(settings.historyFetchSongCount)
	}

	@IBAction func doneButtonPressed(_ sender: AnyObject) {
		dismiss(animated: true, completion: nil)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		switch indexPath.section {
		case SECTION_SPOTIFY_STREAMING_QUALITY:
			let (quality, _) = streamingQualityMap[indexPath.row]
			let previousQuality = settings.spotifyStreamingQuality
			if quality != previousQuality {
				settings.spotifyStreamingQuality = quality
				configureSpotifyStreamingQualityCells()
				if let player = SpotifyClient.sharedInstance.player {
					player.setTargetBitrate(quality) { error in
						if error != nil {
							self.settings.spotifyStreamingQuality = previousQuality
							self.configureSpotifyStreamingQualityCells()
						}
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
				cell.accessoryType = .checkmark
			} else {
				cell.accessoryType = .none
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
