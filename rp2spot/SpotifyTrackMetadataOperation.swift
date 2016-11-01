//
//  SpotifyTrackMetadataOperation.swift
//  rp2spot
//
//  Created by Brian King on 24/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

/**
A concurrent operation that fetches metadata for the given track URIs.

The handler will be called with error == nil, trackList == nil if the operation was
cancelled.
*/
class SpotifyTrackMetadataOperation: ConcurrentOperation {

	var trackURIs: [URL]
	var handler: ((NSError?, [SPTTrack]?) -> Void)?

	init(trackURIs: [URL], handler: ((NSError?, [SPTTrack]?) -> Void)? = nil) {
		self.trackURIs = trackURIs
		self.handler = handler
	}

	override func wasCancelledBeforeStarting() {
		handler?(nil, nil)
	}

	override func main() {

		let infoManager = SpotifyClient.sharedInstance.trackInfo
		let (found, missing) = infoManager.getCachedTrackInfo(trackURIs)
		guard missing.count > 0 else {
			handler?(nil, found)
			self.state = .Finished
			return
		}

		SPTTrack.tracks(withURIs: missing, accessToken: nil, market: nil) { error, trackInfoList in
			guard !self.isCancelled else {
				self.handler?(nil, nil)
				self.state = .Finished
				return
			}

			guard error == nil else {
				self.handler?(error! as NSError, nil)
				self.state = .Finished
				return
			}

			guard let infos = trackInfoList as? [SPTTrack] else {
				print("When trying to fetch metadata for \(missing.count) tracks: trackInfoList is nil or does not contain expected SPTTrack types: \(trackInfoList)")
				let err = NSError(domain: "SpotifyTrackMetadataOperation", code: 1,
				                  userInfo: [NSLocalizedDescriptionKey: "Error processing track metadata"])
				self.handler?(err, nil)
				self.state = .Finished
				return
			}

			infoManager.addTracksToCache(infos)
			self.handler?(nil, infos + found)
			self.state = .Finished
		}
	}
}
