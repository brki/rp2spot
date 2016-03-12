	//
//  CoreDataStack.swift
//  rp2spot
//
//  Created by Brian on 13/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation
import CoreData

class CoreDataStack {
	typealias saveCompletionHandler = ((error: NSError?, isChildContext: Bool) -> Void)

	static let sharedInstance = CoreDataStack()

	static func childContextForContext(context: NSManagedObjectContext, concurrencyType: NSManagedObjectContextConcurrencyType = .MainQueueConcurrencyType) -> NSManagedObjectContext {
		let childContext = NSManagedObjectContext(concurrencyType: concurrencyType)
		childContext.parentContext = context
		return childContext
	}

	/**
	Saves the given context and any ancestor contexts, too.

	The handler will be called when the final save completes, or when an error occurs.
	*/
	static func saveContext(context: NSManagedObjectContext, includeParentContexts: Bool = true, handler: saveCompletionHandler? = nil) {

		let isChildContext = context.parentContext != nil

		func saveCurrentContext(completion: () -> Void) {
			var nserror: NSError?
			if context.hasChanges {
				do {
					try context.save()
				} catch {
					nserror = error as NSError
					handler?(error: nserror, isChildContext: isChildContext)
				}
				completion()
			}
		}

		if isChildContext {
			context.performBlock {
				saveCurrentContext {
					if includeParentContexts, let parentContext = context.parentContext {
						CoreDataStack.saveContext(parentContext, includeParentContexts: true, handler: handler)
					} else {
						handler?(error: nil, isChildContext: true)
					}
				}
			}
		} else {
			context.performBlock {
				saveCurrentContext {
					handler?(error: nil, isChildContext: false)
				}
			}
		}
	}

	lazy var applicationDocumentsDirectory: NSURL = {
		// The directory the application uses to store the Core Data store file. This code uses a directory named "ch.truckin.rp2spot" in the application's documents Application Support directory.
		let urls = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
		return urls[urls.count-1]
	}()

	lazy var managedObjectModel: NSManagedObjectModel = {
		// The managed object model for the application. This property is not optional. It is a fatal error for the application not to be able to find and load its model.
		let modelURL = NSBundle.mainBundle().URLForResource("rp2spot", withExtension: "momd")!
		return NSManagedObjectModel(contentsOfURL: modelURL)!
	}()

	lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
		// The persistent store coordinator for the application. This implementation creates and returns a coordinator, having added the store for the application to it. This property is optional since there are legitimate error conditions that could cause the creation of the store to fail.
		// Create the coordinator and store
		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
		let url = self.applicationDocumentsDirectory.URLByAppendingPathComponent("rp2spot.sqlite")
		var failureReason = "There was an error creating or loading the application's saved data."
		do {
			try coordinator.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: url, options: nil)
		} catch {
			// Report any error we got.
			var dict = [String: AnyObject]()
			dict[NSLocalizedDescriptionKey] = "Failed to initialize the application's saved data"
			dict[NSLocalizedFailureReasonErrorKey] = failureReason

			dict[NSUnderlyingErrorKey] = error as NSError
			let wrappedError = NSError(domain: "rp2spot-CoreData", code: 9999, userInfo: dict)
			NSLog("Unresolved error \(wrappedError), \(wrappedError.userInfo)")

			Utility.presentAlert("Error accessing data store",
				message: "This is a serious error.  Try completely quitting the app before opening it again.")
		}

		return coordinator
	}()

	lazy var managedObjectContext: NSManagedObjectContext = {
		// Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.) This property is optional since there are legitimate error conditions that could cause the creation of the context to fail.
		let coordinator = self.persistentStoreCoordinator
		var managedObjectContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
		managedObjectContext.persistentStoreCoordinator = coordinator
		return managedObjectContext
	}()
}