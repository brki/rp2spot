//
//  PlaylistCreationViewController.swift
//  rp2spot
//
//  Created by Brian King on 18/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

class PlaylistCreationViewController: UIViewController {

	@IBOutlet weak var controlsView: UIView!
	@IBOutlet weak var instructionsLabel: UILabel!
	@IBOutlet weak var publicPlaylistSwitch: UISwitch!
	@IBOutlet weak var playlistTitle: UITextField!
	@IBOutlet weak var createPlaylistButton: UIButton!
	@IBOutlet weak var activityIndicator: UIActivityIndicatorView!
	@IBOutlet weak var creationStatusLabel: UILabel!
	@IBOutlet weak var openInSpotifyButton: UIButton!

	override func viewDidLoad() {
		controlsView.backgroundColor = Constant.Color.SageGreen.color()
		playlistTitle.backgroundColor = Constant.Color.LightGrey.color()
		playlistTitle.delegate = self
	}
	
	@IBAction func createPlaylist(sender: UIButton) {
	}
	
	@IBAction func openInSpotify(sender: UIButton) {
	}

	@IBAction func back(sender: UIBarButtonItem) {
		dismissViewControllerAnimated(true, completion: nil)
	}
}

extension PlaylistCreationViewController: UITextFieldDelegate {
	func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		if let text = textField.text {
			let newString = (text as NSString).stringByReplacingCharactersInRange(range, withString: string).trim()
			createPlaylistButton.enabled = newString != ""
		}
		return true
	}

	func textFieldShouldClear(textField: UITextField) -> Bool {
		createPlaylistButton.enabled = false
		return true
	}
}