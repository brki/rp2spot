//
//  PlayedSong.swift
//  rp2spot
//
//  Created by Brian on 14/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation
import CoreData


class PlayedSong: NSManagedObject {

	override init(entity: NSEntityDescription, insertIntoManagedObjectContext context: NSManagedObjectContext?) {
		super.init(entity: entity, insertIntoManagedObjectContext: context)
	}

	init(playedSongData: [PlayedSongData], context: NSManagedObjectContext) {
		let entity = NSEntityDescription.entityForName("PlayedSong", inManagedObjectContext: context)!
		super.init(entity: entity, insertIntoManagedObjectContext: context)

		// TODO: initialize object from json
	}
}
