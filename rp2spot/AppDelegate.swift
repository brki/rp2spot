//
//  AppDelegate.swift
//  rp2spot
//
//  Created by Brian on 03/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit
import CoreData

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	var window: UIWindow?

	func setStatusBarBackgroundColor(color: UIColor) {
		guard  let statusBar = UIApplication.sharedApplication().valueForKey("statusBarWindow")?.valueForKey("statusBar") as? UIView else {
			return
		}
		statusBar.backgroundColor = color
	}

	func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
		let black = UIColor.blackColor()
		let brightGreen = Constant.Color.SpotifyGreen.color()
		setStatusBarBackgroundColor(black)

		let toolBarAppearance = UIToolbar.appearance()
		toolBarAppearance.opaque = true
		toolBarAppearance.backgroundColor = black

		let barButtonAppearance = UIBarButtonItem.appearance()
		barButtonAppearance.tintColor = brightGreen

		let navBarAppearance = UINavigationBar.appearance()
		navBarAppearance.barTintColor = black
		navBarAppearance.opaque = true
		navBarAppearance.translucent = false
		navBarAppearance.tintColor = brightGreen

		// The button tint color should be set everyplace except for in the HistoryBrowserViewController (there
		// it should not be set, because the disclosure indicator buttons dissapear when the cell is highlighted
		// in the same tint color (e.g. when a song is playing)).
		UIButton.appearanceWhenContainedInInstancesOfClasses([HistoryDateSelectorViewController.self]).tintColor = brightGreen
		UIButton.appearanceWhenContainedInInstancesOfClasses([SongInfoViewController.self]).tintColor = brightGreen
		UIButton.appearanceWhenContainedInInstancesOfClasses([PlaylistViewController.self]).tintColor = brightGreen
		UIButton.appearanceWhenContainedInInstancesOfClasses([PlaylistCreationViewController.self]).tintColor = brightGreen
		UIButton.appearanceWhenContainedInInstancesOfClasses([UserSettingsViewController.self]).tintColor = brightGreen

		let spinnerAppearance = UIActivityIndicatorView.appearance()
		spinnerAppearance.color = brightGreen

		return true
	}

	func applicationWillResignActive(application: UIApplication) {
		// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
		// Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
	}

	func applicationDidEnterBackground(application: UIApplication) {
		// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
		// If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
	}

	func applicationWillEnterForeground(application: UIApplication) {
		// Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
	}

	func applicationDidBecomeActive(application: UIApplication) {
		// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
	}

	func applicationWillTerminate(application: UIApplication) {
		// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
		// Saves changes in the application's managed object context before the application terminates.
		CoreDataStack.saveContext(CoreDataStack.sharedInstance.managedObjectContext)
	}

	func application(app: UIApplication, openURL url: NSURL, options: [String : AnyObject]) -> Bool {
		let auth = SpotifyClient.sharedInstance.auth

		/*
		Handle the callback from the authentication service. -[SPAuth -canHandleURL:]
		helps us filter out URLs that aren't authentication URLs (i.e., URLs you use elsewhere in the application).
		*/
		if auth.canHandleURL(url) {
			auth.handleAuthCallbackWithTriggeredAuthURL(url) { error, session in
				guard error == nil else {
					// TODO: revisit how to handle this in running app:
					print("Auth error: \(error)")
					SpotifyClient.sharedInstance.postSessionUpdateNotification(error)
					return
				}

				auth.session = session

				// Send the session update notification.
				SpotifyClient.sharedInstance.postSessionUpdateNotification(error)

				// If the user's Spotify region is not yet known, grab that info.
				if UserSetting.sharedInstance.spotifyRegion == nil {
					SpotifyClient.sharedInstance.getUserTerritory { territory in
						guard let userTerritory = territory else {
							return
						}
						UserSetting.sharedInstance.spotifyRegion = userTerritory
					}
				}
			}
			return true
		}

		return false
	}

	func applicationDidReceiveMemoryWarning(application: UIApplication) {
		SpotifyClient.sharedInstance.trackInfo.cache.removeAllObjects()

		// Note: AlamofireImage's AutoPurgingImageCache listens for low memory warnings and purges
		// the in-memory cache when one is received.
	}

}

