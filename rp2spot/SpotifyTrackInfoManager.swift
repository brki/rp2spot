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

	/**
	An in-memory cache of the track metadata.
	
	The cache key is the short Spotify track id, the value is a SPTTrack.
	*/
	lazy var cache: NSCache<NSString, SPTTrack> = {
		let cache = NSCache<NSString, SPTTrack>()
		cache.countLimit = Constant.CACHE_SPOTIFY_TRACK_INFO_MAX_COUNT
		return cache
	}()

	lazy var operationQueue: OperationQueue = {
		let queue = OperationQueue()
		queue.maxConcurrentOperationCount = 1
		return queue
	}()


	/**
	Gets the track metadata for the given track URIs.
	
	A network request is made only if some track-metadata objects
	are not locally cached.
	*/
	func trackMetadata(_ trackURIs: [URL], handler: @escaping (NSError?, [SPTTrack]?) -> Void) {
		let operation = SpotifyTrackMetadataOperation(trackURIs: trackURIs, handler:handler)
		operationQueue.addOperation(operation)
	}

	/**
	Gets the track metadata for the given track.
	*/
	func trackInfo(_ trackId: String, handler: @escaping (NSError?, SPTTrack?) -> Void) {
		if let trackInfo = cache.object(forKey: trackId as NSString) {
			handler(nil, trackInfo)
			return
		}

		guard let URI = SpotifyClient.sharedInstance.trackURI(trackId) else {
			let error = NSError(domain: "SpotifyTrackInfoManager",
			                    code: 1,
			                    userInfo: [NSLocalizedDescriptionKey: "Unable to generate spotify URL from provided trackId (\(trackId))"])
			handler(error, nil)
			return
		}

		trackMetadata([URI]) { error, trackInfos in
			handler(error, trackInfos?[0])
		}
	}



	/**
	Finds locally cached tracks.

	Given the list of URIs, return a tuple containg an array of track metadata for tracks
	found in the cache, and an array of URLs for the tracks not found in the cache.
	*/
	func getCachedTrackInfo(_ trackURIs: [URL]) -> (found: [SPTTrack], missing: [URL]) {
		var found = [SPTTrack]()
		var missing = [URL]()
		for uri in trackURIs {
			let key = SpotifyClient.shortSpotifyTrackId(uri.absoluteString) as NSString
			if let trackInfo = cache.object(forKey: key) {
				found.append(trackInfo)
			} else {
				missing.append(uri)
			}
		}
		return (found: found, missing: missing)
	}

	func addTracksToCache(_ tracks: [SPTTrack]) {
		for track in tracks {
			cache.setObject(track, forKey: track.identifier as NSString)
		}
	}
}
