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
	@IBOutlet weak var bottomToolbar: UIToolbar!
	@IBOutlet weak var scrollView: UIScrollView!
	@IBOutlet weak var controlsViewHeightConstraint: NSLayoutConstraint!

	var localPlaylist: LocalPlaylistSongs!
	var playlistURI: NSURL?
	let spotify = SpotifyClient.sharedInstance
	var postLoginBlock: (() -> Void)?


	var isRotating = false				// Will be true during rotation
	var activeTextField: UITextField?	// Keeps track of the active text field.


	override func viewDidLoad() {
		let sageGreen = Constant.Color.SageGreen.color()
		controlsView.backgroundColor = sageGreen
		scrollView.backgroundColor = sageGreen
		playlistTitle.backgroundColor = Constant.Color.LightGrey.color()
		playlistTitle.delegate = self

		// Add a tap recognizer so that keyboard will be dismissed when user taps view outisde of text field:
		let tapRecognizer = UITapGestureRecognizer(target: self, action: "viewTapped:")
		tapRecognizer.numberOfTapsRequired = 1
		view.addGestureRecognizer(tapRecognizer)
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		// Make the toolbar resize itself appropriately for the current orientation:
		bottomToolbar.invalidateIntrinsicContentSize()
		registerForKeyboardAndStatusBarNotifications()
	}

	override func viewDidAppear(animated: Bool) {
		super.viewDidAppear(animated)
		setHeightConstraintIfNeeded()
	}

	override func viewWillDisappear(animated: Bool) {
		super.viewWillDisappear(animated)
		unregisterForKeyboardAndStatusBarNotifications()
	}

	@IBAction func openInSpotify(sender: UIButton) {
		guard let uri = playlistURI else {
			print("Open in Spotify tapped, but no playlist URI available")
			return
		}
		UIApplication.sharedApplication().openURL(uri)
	}

	@IBAction func back(sender: UIBarButtonItem) {
		dismissViewControllerAnimated(true, completion: nil)
	}


	@IBAction func createPlaylist(sender: UIButton) {
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
	func tryCreatePlaylist(title: String, selectedTrackIds: [String]) {
		createPlaylistButton.enabled = false

		spotify.createPlaylistWithTracks(title, trackIds: selectedTrackIds, publicFlag: publicPlaylistSwitch.selected) { playlistSnapshot, willTriggerLogin, error in
			guard error == nil else {
				let info = error!.localizedDescription
				Utility.presentAlert("Failed to create playlist", message: "Playlist '\(title)' could not be created: \(info)")
				return
			}

			guard !willTriggerLogin else {
				self.postLoginBlock = { [unowned self] in
					self.postLoginBlock = nil
					self.tryCreatePlaylist(title, selectedTrackIds: selectedTrackIds)
				}
				NSNotificationCenter.defaultCenter().addObserver(self, selector: "spotifySessionUpdated:", name: SpotifyClient.SESSION_UPDATE_NOTIFICATION, object: self.spotify)
				return
			}

			guard let playlist = playlistSnapshot else {
				Utility.presentAlert("Failed to create playlist", message: "Playlist '\(title)' could not be created: no error information available")
				return
			}

			self.playlistURI = playlist.uri
			async_main  {
				self.creationStatusLabel.text = "Playlist created"
				self.creationStatusLabel.hidden = false
				self.creationStatusLabel.alpha = 0
				UIView.animateWithDuration(0.4) {
					self.creationStatusLabel.alpha = 1.0
					self.showOpenInSpotify()
				}
			}
		}
	}

	func spotifySessionUpdated(notification: NSNotification) {
		NSNotificationCenter.defaultCenter().removeObserver(self, name: SpotifyClient.SESSION_UPDATE_NOTIFICATION, object: self.spotify)
		guard let postLogin = postLoginBlock else {
			return
		}
		guard spotify.auth.session.isValid() else {
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
		guard UIApplication.sharedApplication().canOpenURL(uri) else {
			print("Spotify application not available")
			return
		}
		openInSpotifyButton.hidden = false
		openInSpotifyButton.enabled = true
	}

	func viewTapped(sender: UITapGestureRecognizer) {
		view.endEditing(true)
	}
}

extension PlaylistCreationViewController: UITextFieldDelegate {

	/**
	The create playlist button should only be enabled if there's valid text for the playlist name.
	*/
	func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		if let text = textField.text {
			let newString = (text as NSString).stringByReplacingCharactersInRange(range, withString: string)
			enableCreatePlaylistButtonIfValidTitlePresent(newString)
		}
		return true
	}

	func enableCreatePlaylistButtonIfValidTitlePresent(title: String?) {
		let titleText = title ?? ""
		createPlaylistButton.enabled = titleText.trim() != ""
	}

	func textFieldShouldClear(textField: UITextField) -> Bool {
		createPlaylistButton.enabled = false
		return true
	}

	func textFieldShouldReturn(textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
}


// MARK: keeping the text field visible while editing

extension PlaylistCreationViewController {

	/**
	The status bar may or may not be visible in the new orientation.
	Keep track of the rotation status.  When the keyboard is present, some UIKeyboardWillChangeFrameNotification
	notifications are sent during rotation, but we can ignore those.
	*/
	override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)
		// Before the animation is a good time to call invalidateIntrinsicContentSize() on a toolbar.
		// This makes it's new height available during the animation.
		bottomToolbar.invalidateIntrinsicContentSize()
		isRotating = true
		coordinator.animateAlongsideTransition(
			{ context in
				self.setHeightConstraintIfNeeded()
			},
			completion: { context in
				self.isRotating = false
		})
	}

	/**
	Keep track of the currently active text field.
	*/
	func textFieldDidBeginEditing(textField: UITextField) {
		activeTextField = textField
	}

	/**
	Unset the currently active text field when the text field resigns as a first responder.
	*/
	func textFieldDidEndEditing(textField: UITextField) {
		if activeTextField == textField {
			activeTextField = nil
		}
	}

	func registerForKeyboardAndStatusBarNotifications() {
		NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardChangingSize:", name: UIKeyboardWillChangeFrameNotification, object: nil)
		NSNotificationCenter.defaultCenter().addObserver(self, selector: "statusBarChangingSize:", name: UIApplicationWillChangeStatusBarFrameNotification, object: nil)

	}

	func unregisterForKeyboardAndStatusBarNotifications() {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	/**
	The content view height.
	*/
	var contentViewHeight: CGFloat {
		let windowHeight = UIScreen.mainScreen().bounds.size.height
		return windowHeight - topBarHeight - bottomBarHeight
	}

	// This may need some adjustment if a navigation bar / tab bar / tool bar is present.
	var topBarHeight: CGFloat {
		return UIApplication.sharedApplication().statusBarFrame.size.height
	}

	// This may need some adjustment if a tab bar / tool bar is present.
	// Note that a toolbar may have a different height in landscape / portrait mode.
	var bottomBarHeight: CGFloat {
		return bottomToolbar.frame.height
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
	Reset the content view's height when the status bar changes size.
	*/
	func statusBarChangingSize(notification: NSNotification) {
		if !isRotating {
			setHeightConstraintIfNeeded()
		}
	}

	/**
	Change the UIScrollView's contentInset when the keyboard appears / disappears / changes size.
	If necessary, scroll so that the currently active text field is visible.
	*/
	func keyboardChangingSize(notification: NSNotification) {
		if isRotating {
			// No need to handle notifications during rotation
			return
		}

		guard let userInfo = notification.userInfo as [NSObject: AnyObject]?,
			endFrame = (userInfo[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.CGRectValue() else {
				// Needed information not available.
				return
		}

		let convertedEndFrame = view.convertRect(endFrame, fromView: view.window)
		if convertedEndFrame.origin.y == view.bounds.height {

			// Keyboard is hidden.
			let contentInset = UIEdgeInsetsZero
			scrollView.contentInset = contentInset
			scrollView.scrollIndicatorInsets = contentInset

		} else {
			// Keyboard is visible.
			guard let textField = activeTextField else {
				// No active text field ...
				return
			}

			let keyboardTop = convertedEndFrame.origin.y
			let textFieldRect = textField.convertRect(textField.bounds, toView: view)
			let textFieldBottom = textFieldRect.origin.y + textFieldRect.height
			let offset = textFieldBottom - keyboardTop
			guard offset > 0 else {
				// Text field is already above the top of the keyboard.
				return
			}

			// Adjust the scroll view content inset.
			let contentInset = UIEdgeInsets(top:0.0, left:0.0, bottom:convertedEndFrame.height, right:0.0)
			scrollView.contentInset = contentInset
			scrollView.scrollIndicatorInsets = contentInset

			// Animate the text field into view.
			let animationDuration = userInfo[UIKeyboardAnimationDurationUserInfoKey] as? Double ?? 0.0
			let animationOption = userInfo[UIKeyboardAnimationCurveUserInfoKey] as? UIViewAnimationOptions ?? UIViewAnimationOptions.TransitionNone
			UIView.animateWithDuration(
				animationDuration,
				delay: 0.0,
				options: animationOption,
				animations: {
					self.scrollView.scrollRectToVisible(textFieldRect, animated: false)
				},
				completion: nil)			
		}
	}

}