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
	@IBOutlet weak var scrollView: UIScrollView!
	@IBOutlet weak var controlsViewHeightConstraint: NSLayoutConstraint!
	@IBOutlet weak var cancelDoneButton: UIBarButtonItem!

	var localPlaylist: LocalPlaylistSongs!
	var playlistURI: URL?
	let spotify = SpotifyClient.sharedInstance
	var postLoginBlock: (() -> Void)?

	var activeTextField: UITextField?	// Keeps track of the active text field.

	override func viewDidLoad() {
		let sageGreen = Constant.Color.sageGreen.color()
		controlsView.backgroundColor = sageGreen
		scrollView.backgroundColor = sageGreen
		playlistTitle.backgroundColor = Constant.Color.lightGrey.color()
		playlistTitle.delegate = self

		let count = localPlaylist.selected.count
		instructionsLabel.text = "Create Spotify playlist (\(count) \(count > 1 ? "songs" : "song"))"

		if let title = localPlaylist.playlistTitle {
			playlistTitle.text = title
		}
		enableCreatePlaylistButtonIfValidTitlePresent(playlistTitle.text)

		// Add a tap recognizer so that keyboard will be dismissed when user taps view outisde of text field:
		let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.viewTapped(_:)))
		tapRecognizer.numberOfTapsRequired = 1
		view.addGestureRecognizer(tapRecognizer)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		registerForKeyboardAndStatusBarNotifications()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		setHeightConstraintIfNeeded()
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		unregisterForNotifications()
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let id = segue.identifier, id == "PlaylistCreationExit" {
			view.endEditing(true)
		}
	}

	@IBAction func openInSpotify(_ sender: UIButton) {
		guard let uri = playlistURI else {
			print("Open in Spotify tapped, but no playlist URI available")
			return
		}
		UIApplication.shared.openURL(uri)
	}

	@IBAction func createPlaylist(_ sender: UIButton) {
		view.endEditing(true)
		let title = (playlistTitle.text ?? "").trim()
		guard title.characters.count > 0 else {
			Utility.presentAlert("Playlist title is empty", message: "Give the playlist a name, then try again")
			return
		}
		let selectedTrackIds = localPlaylist.selectedTrackIds()
		guard selectedTrackIds.count > 0 else {
			Utility.presentAlert("No tracks selected", message: "Select some tracks first, then try again")
			return
		}

		tryCreatePlaylist(title, selectedTrackIds: selectedTrackIds)
	}

	/**
	Try to create the playlist.
	
	This may not be immediately possible if the user needs to log in first.  If that is the case, save a closure that
	can be executed on sucessful login, and register to get notified when the session is updated.
	*/
	func tryCreatePlaylist(_ title: String, selectedTrackIds: [String]) {
		enableEditingControls(false)
		activityIndicator.startAnimating()

		spotify.createPlaylistWithTracks(title, trackIds: selectedTrackIds, publicFlag: publicPlaylistSwitch.isOn) { playlistSnapshot, willTriggerLogin, error in

			self.activityIndicator.stopAnimating()

			guard error == nil else {
				let info = error!.localizedDescription
				Utility.presentAlert("Failed to create playlist", message: "Playlist '\(title)' could not be created: \(info)")
				self.enableEditingControls(true)
				return
			}

			guard !willTriggerLogin else {
				self.postLoginBlock = { [unowned self] in
					self.postLoginBlock = nil
					self.tryCreatePlaylist(title, selectedTrackIds: selectedTrackIds)
				}
				NotificationCenter.default.addObserver(
					self,
					selector: #selector(self.spotifySessionUpdated(_:)),
					name: NSNotification.Name(rawValue: SpotifyClient.SESSION_UPDATE_NOTIFICATION), object: self.spotify
				)
				return
			}

			guard let playlist = playlistSnapshot else {
				Utility.presentAlert("Failed to create playlist", message: "Playlist '\(title)' could not be created: no error information available")
				self.enableEditingControls(true)
				return
			}

			self.playlistURI = playlist.uri
			async_main  {
				self.creationStatusLabel.text = "Playlist created"
				self.creationStatusLabel.isHidden = false
				self.creationStatusLabel.alpha = 0
				UIView.animate(withDuration: 0.4, animations: {
					self.cancelDoneButton.title = "Done"
					self.cancelDoneButton.isEnabled = true
					self.creationStatusLabel.alpha = 1.0
					self.showOpenInSpotify()
				}) 
			}
		}
	}

	func enableEditingControls(_ enabled: Bool) {
		async_main {
			self.createPlaylistButton.isEnabled = enabled
			self.playlistTitle.isEnabled = enabled
			self.publicPlaylistSwitch.isEnabled = enabled
			self.navigationItem.hidesBackButton = !enabled
		}
	}

	func spotifySessionUpdated(_ notification: Notification) {
		NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: SpotifyClient.SESSION_UPDATE_NOTIFICATION), object: self.spotify)
		guard let postLogin = postLoginBlock else {
			return
		}
		guard (spotify.auth.session.isValid()) else {
			print("No valid session after session update: discarding postLogin block")
			enableCreatePlaylistButtonIfValidTitlePresent(playlistTitle.text)
			postLoginBlock = nil
			return
		}
		postLogin()
	}

	func showOpenInSpotify() {
		guard let uri = playlistURI else {
			print("No playlist URI available")
			return
		}
		guard UIApplication.shared.canOpenURL(uri) else {
			print("Spotify application not available")
			return
		}
		openInSpotifyButton.isHidden = false
		openInSpotifyButton.isEnabled = true
	}

	func viewTapped(_ sender: UITapGestureRecognizer) {
		view.endEditing(true)
	}
}


extension PlaylistCreationViewController: UITextFieldDelegate {

	/**
	The create playlist button should only be enabled if there's valid text for the playlist name.
	*/
	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		if let text = textField.text {
			let newString = (text as NSString).replacingCharacters(in: range, with: string)
			enableCreatePlaylistButtonIfValidTitlePresent(newString)
		}
		localPlaylist.playlistTitle = textField.text
		return true
	}

	func enableCreatePlaylistButtonIfValidTitlePresent(_ title: String?) {
		let titleText = title ?? ""
		createPlaylistButton.isEnabled = titleText.trim() != ""
	}

	func textFieldShouldClear(_ textField: UITextField) -> Bool {
		createPlaylistButton.isEnabled = false
		return true
	}

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
}


// MARK: keeping the text field visible while editing

extension PlaylistCreationViewController {

	/**
	The status bar may or may not be visible in the new orientation.
	*/
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		// Before the animation is a good time to call invalidateIntrinsicContentSize() on a toolbar.
		// This makes it's new height available during the animation.
		coordinator.animate(
			alongsideTransition: { context in
				self.setHeightConstraintIfNeeded()
			},
			completion: nil
		)
	}

	/**
	Keep track of the currently active text field.
	*/
	func textFieldDidBeginEditing(_ textField: UITextField) {
		activeTextField = textField
	}

	/**
	Unset the currently active text field when the text field resigns as a first responder.
	*/
	func textFieldDidEndEditing(_ textField: UITextField) {
		if activeTextField == textField {
			activeTextField = nil
		}
		if textField == playlistTitle {
			localPlaylist.playlistTitle = textField.text
		}
	}

	func registerForKeyboardAndStatusBarNotifications() {
		NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardChangingSize(_:)), name: NSNotification.Name.UIKeyboardWillChangeFrame, object: nil)
	}

	func unregisterForNotifications() {
		NotificationCenter.default.removeObserver(self)
	}

	/**
	The content view height.

	The lowest element that can be interacted with while the text field
	is editable is the createPlaylistButton, use it's bottom for the
	content view height.
	*/
	var contentViewHeight: CGFloat {
		return createPlaylistButton.frame.maxY
	}

	/**
	Set the content view height constraint based on the space available.
	*/
	func setHeightConstraintIfNeeded() {
		if let constraint = controlsViewHeightConstraint {
			let currentHeight = contentViewHeight
			if currentHeight != constraint.constant {
				constraint.constant = currentHeight
			}
		}
	}

	/**
	Change the UIScrollView's contentInset when the keyboard appears / disappears / changes size.
	If necessary, scroll so that the currently active text field is visible.
	*/
	func keyboardChangingSize(_ notification: Notification) {

		guard let userInfo = notification.userInfo as [AnyHashable: Any]?,
			let endFrame = (userInfo[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
				// Needed information not available.
				return
		}

		let convertedEndFrame = view.convert(endFrame, from: view.window)
		if convertedEndFrame.origin.y == view.bounds.height {

			// Keyboard is hidden.
			let contentInset = UIEdgeInsets.zero
			scrollView.contentInset = contentInset
			scrollView.scrollIndicatorInsets = contentInset

		} else {
			// Keyboard is visible.
			guard let textField = activeTextField else {
				// No active text field ...
				return
			}

			let textFieldRect = textField.convert(textField.bounds, to: view)

			// Adjust the scroll view content inset.
			let contentInset = UIEdgeInsets(top:0.0, left:0.0, bottom:convertedEndFrame.height, right:0.0)
			scrollView.contentInset = contentInset
			scrollView.scrollIndicatorInsets = contentInset

			// Animate the text field into view.
			let animationDuration = userInfo[UIKeyboardAnimationDurationUserInfoKey] as? Double ?? 0.0
			let animationOption = userInfo[UIKeyboardAnimationCurveUserInfoKey] as? UIViewAnimationOptions ?? UIViewAnimationOptions()
			UIView.animate(
				withDuration: animationDuration,
				delay: 0.0,
				options: animationOption,
				animations: {
					self.scrollView.scrollRectToVisible(textFieldRect, animated: false)
				},
				completion: nil)			
		}
	}
}
