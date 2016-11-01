//
//  PlayedSong+CoreDataProperties.swift
//  rp2spot
//
//  Created by Brian on 14/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension PlayedSong {

    @NSManaged var title: String
    @NSManaged var playedAt: Foundation.Date
    @NSManaged var albumTitle: String
	@NSManaged var asin: String?
    @NSManaged var largeImageURL: String?
    @NSManaged var smallImageURL: String?
    @NSManaged var spotifyTrackId: String?
    @NSManaged var radioParadiseSongId: NSNumber
    @NSManaged var artistName: String

}
