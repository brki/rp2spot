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

	var trackIds: [String]
	var handler: ((NSError?, [SpotifyTrackInfo]?) -> Void)?

	init(trackIds: [String], handler: ((NSError?, [SpotifyTrackInfo]?) -> Void)? = nil) {
		self.trackIds = trackIds
		self.handler = handler
	}

	override func wasCancelledBeforeStarting() {
		handler?(nil, nil)
	}

	override func main() {
		let spotify = SpotifyClient.sharedInstance
		let trackURIS = spotify.URIsForTrackIds(trackIds)
		let token = spotify.auth.session?.accessToken
		let market = token == nil ? UserSetting.sharedInstance.spotifyRegionValue : "from_token"
		SPTTrack.tracks(withURIs: trackURIS, accessToken: token, market: market) { error, trackInfoList in
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
				print("When trying to fetch metadata for tracks: trackInfoList is nil or does not contain expected SPTTrack types: \(trackInfoList)")
				let err = NSError(domain: "SpotifyTrackMetadataOperation", code: 1,
				                  userInfo: [NSLocalizedDescriptionKey: "Error processing track metadata"])
				self.handler?(err, nil)
				self.state = .Finished
				return
			}

			let trackInfos = infos.map {SpotifyTrackInfo(track: $0)}

			self.handler?(nil, trackInfos)
			self.state = .Finished
		}
	}
}
