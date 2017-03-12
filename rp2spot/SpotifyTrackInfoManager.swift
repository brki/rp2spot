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
	
	The cache key is the short Spotify track id, the value is a SpotifyTrackInfo
	*/
	lazy var cache: NSCache<NSString, SpotifyTrackInfo> = {
		let cache = NSCache<NSString, SpotifyTrackInfo>()
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
	func fetchTrackMetadata(_ trackIds: [String], handler: @escaping (NSError?, [SpotifyTrackInfo]?) -> Void) {
		let operation = SpotifyTrackMetadataOperation(trackIds: trackIds, handler: handler)
		operationQueue.addOperation(operation)
	}

	func trackMetadata(_ trackIds: [String], handler: @escaping (NSError?, [SpotifyTrackInfo]?) -> Void) {
		let (cachedTracks, missingTrackIds) = getCachedTrackInfo(trackIds)
		guard missingTrackIds.count > 0 else {
			handler(nil, cachedTracks)
			return
		}
		fetchTrackMetadata(missingTrackIds) { error, trackInfos in
			guard error == nil, let infos = trackInfos else {
				handler(error, cachedTracks)
				return
			}
			self.addTracksToCache(infos)
			handler(nil, cachedTracks + infos)
		}
	}

	/**
	Gets the track metadata for the given track.
	*/
	func trackInfo(_ trackId: String, handler: @escaping (NSError?, SpotifyTrackInfo?) -> Void) {
		if let trackInfo = cache.object(forKey: trackId as NSString) {
			handler(nil, trackInfo)
			return
		}

		fetchTrackMetadata([trackId]) { error, trackInfos in
			handler(error, trackInfos?[0])
		}
	}

	/**
	Finds locally cached tracks.

	Given the list of URIs, return a tuple containg an array of track metadata for tracks
	found in the cache, and an array of URLs for the tracks not found in the cache.
	*/
	func getCachedTrackInfo(_ trackIds: [String]) -> (found: [SpotifyTrackInfo], missing: [String]) {
		var found = [SpotifyTrackInfo]()
		var missing = [String]()
		for trackId in trackIds {
			if let trackInfo = cache.object(forKey: trackId as NSString) {
				found.append(trackInfo)
			} else {
				missing.append(trackId)
			}
		}
		return (found: found, missing: missing)
	}

	func addTracksToCache(_ tracks: [SpotifyTrackInfo]) {
		for track in tracks {
			cache.setObject(track, forKey: track.identifier as NSString)
		}
	}
}
