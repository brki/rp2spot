//
//  UserSettingsViewController.swift
//  rp2spot
//
//  Created by Brian King on 29/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

class UserSettingsViewController: UITableViewController {

	@IBOutlet weak var maximumSongHistoryLabel: UILabel!
	@IBOutlet weak var maximumSongHistoryStepper: UIStepper!
	@IBOutlet weak var fetchSizeLabel: UILabel!
	@IBOutlet weak var fetchSizeStepper: UIStepper!

	let settings = UserSetting.sharedInstance

	let streamingQualitySection = 0
	let wifiRow = 0
	let cellularRow = 1

	// TODO: show (low / medium / high) text in wifi cells

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.backgroundColor = Constant.Color.lightGrey.color()

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

	func configureSongHistoryListControls() {
		let maxSongHistoryCount = settings.maxLocalSongHistoryCount
		maximumSongHistoryStepper.value = Double(maxSongHistoryCount)
		maximumSongHistoryLabel.text = String(maxSongHistoryCount)

		let fetchSize = settings.historyFetchSongCount
		fetchSizeStepper.value = Double(fetchSize)
		fetchSizeLabel.text = String(fetchSize)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let indexPath = self.tableView.indexPathForSelectedRow, indexPath.section == 0,
			let destinationVC = segue.destination as? SpotifyStreamingQualityViewController {
			let networkType = indexPath.row == wifiRow ? UserSetting.NetworkType.wifi : UserSetting.NetworkType.cellular
			destinationVC.networkType = networkType
		}
	}
}
