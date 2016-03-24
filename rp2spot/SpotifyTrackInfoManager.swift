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

	/**
	Gets the track metadata for the given track URIs.
	
	A network request is made only if some track-metadata objects
	are not locally cached.
	*/
	func trackMetadata(trackURIs: [NSURL], handler: (NSError?, [SPTTrack]?) -> Void) {
		let (found, missing) = getCachedTrackInfo(trackURIs)
		print("Found count: \(found.count), missing count: \(missing.count)")
		if missing.count == 0 {
			handler(nil, found)
			return
		}

		fetchTrackMetadata(missing) { error, trackList in
			guard error == nil else {
				handler(error, found)
				return
			}
			// If there was no error, trackList is an array of SPTTrack.
			handler(nil, found + trackList!)
		}
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

	/**
	Make a network request to the Spotify web service to get track information for the
	given track URIs.
	*/
	func fetchTrackMetadata(trackURIs: [NSURL], handler: (NSError?, [SPTTrack]?) -> Void) {
		// TODO: use a method with access token?
		SPTTrack.tracksWithURIs(trackURIs, accessToken: nil, market: nil) { error, trackInfoList in
			guard error == nil else {
				handler(error, nil)
				return
			}
			guard let infos = trackInfoList as? [SPTTrack] else {
				print("trackInfoList is nil or does not contain expected SPTTrack types: \(trackInfoList)")
				let err = NSError(domain: "SpotifyTrackInfoManager", code: 1,
				                  userInfo: [NSLocalizedDescriptionKey: "Error processing track metadata"])
				handler(err, nil)
				return
			}

			// Add the tracks to the cache
			for info in infos {
				self.cache.setObject(info, forKey: info.identifier)
			}
			handler(nil, infos)
		}
	}
}