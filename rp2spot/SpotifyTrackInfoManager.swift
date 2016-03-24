//
//  SpotifyTrackInfoManager.swift
//  rp2spot
//
//  Created by Brian King on 24/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

class SpotifyTrackInfoManager {

	static let sharedInstance = SpotifyTrackInfoManager()

	lazy var cache: NSCache = {
		let cache = NSCache()
		cache.countLimit = Constant.CACHE_SPOTIFY_TRACK_INFO_MAX_COUNT
		return cache
	}()

	lazy var operationQueue: NSOperationQueue = {
		let queue = NSOperationQueue()
		queue.maxConcurrentOperationCount = 1
		return queue
	}()


	/**
	Gets the track metadata for the given track URIs.
	
	A network request is made only if some track-metadata objects
	are not locally cached.
	*/
	func trackMetadata(trackURIs: [NSURL], handler: (NSError?, [SPTTrack]?) -> Void) {
		let operation = SpotifyTrackMetadataOperation(trackURIs: trackURIs, handler:handler)
		operationQueue.addOperation(operation)
	}

	/**
	Finds locally cached tracks.

	Given the list of URIs, return a tuple containg an array of track metadata for tracks
	found in the cache, and an array of NSURLs for the tracks not found in the cache.
	*/
	func getCachedTrackInfo(trackURIs: [NSURL]) -> (found: [SPTTrack], missing: [NSURL]) {
		var found = [SPTTrack]()
		var missing = [NSURL]()
		for uri in trackURIs {
			let key = SpotifyClient.shortSpotifyTrackId(uri.absoluteString)
			if let trackInfo = cache.objectForKey(key) as? SPTTrack {
				found.append(trackInfo)
			} else {
				missing.append(uri)
			}
		}
		return (found: found, missing: missing)
	}

	func addTracksToCache(tracks: [SPTTrack]) {
		for track in tracks {
			cache.setObject(track, forKey: track.identifier)
		}
	}
}