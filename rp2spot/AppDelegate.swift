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
		setStatusBarBackgroundColor(UIColor.blackColor())
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
				SpotifyClient.sharedInstance.postSessionUpdateNotification(error)
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

