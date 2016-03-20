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

	var isRotating = false				// Will be true during rotation
	var activeTextField: UITextField?	// Keeps track of the active text field.

	override func viewDidLoad() {
		let sageGreen = Constant.Color.SageGreen.color()
		controlsView.backgroundColor = sageGreen
		scrollView.backgroundColor = sageGreen
		playlistTitle.backgroundColor = Constant.Color.LightGrey.color()
		playlistTitle.delegate = self
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

	@IBAction func createPlaylist(sender: UIButton) {
	}
	
	@IBAction func openInSpotify(sender: UIButton) {
	}

	@IBAction func back(sender: UIBarButtonItem) {
		dismissViewControllerAnimated(true, completion: nil)
	}
}

extension PlaylistCreationViewController: UITextFieldDelegate {

	/**
	The create playlist button should only be enabled if there's valid text for the playlist name.
	*/
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