//
// Created by Brian on 11.03.17.
// Copyright (c) 2017 truckin'. All rights reserved.
//

class SpotifyTrackInfo {
	let identifier: String
	let regionTrackId: String?
	let duration: TimeInterval
	let name: String
	let artists: [String]
	let albumTitle: String
	let smallCover: SPTImage?
	let mediumCover: SPTImage?
	let largeCover: SPTImage?

	init(track: SPTTrack) {
		// TODO: double check that isPlayable is correct enough (it seems that at some point, it was saying isPlayable=true when it wasn't really; this may be because that request for metadata was not restricted to a specific market).
		if track.isPlayable {
			self.regionTrackId = track.identifier
		} else {
			self.regionTrackId = nil
		}
		if let data = track.decodedJSONObject as? [String: Any],
		   let linkedFrom = data["linked_from"] as? [String: Any],
		   let originalId = linkedFrom["id"] as? String {
			self.identifier = originalId
		} else {
			self.identifier = track.identifier
		}
		duration = track.duration
		name = track.name
		if let trackArtists = track.artists as? [SPTPartialArtist] {
			self.artists = trackArtists.filter({$0.name != nil}).map({$0.name!})
		} else {
			self.artists = ["Unknown"]
		}
		self.albumTitle = track.album?.name ?? "Unknown"
		self.smallCover = track.album?.smallestCover
		if let covers = track.album?.covers, covers.count > 1, let mediumCover = covers[1] as? SPTImage {
			self.mediumCover = mediumCover
		} else {
			self.mediumCover = nil
		}
		self.largeCover = track.album?.largestCover
	}

	/**
	Returns the playable trackURI as a String.
	*/
	var trackURIString: String? {
		guard let trackId = regionTrackId else {
			return nil
		}
		return SpotifyClient.fullSpotifyTrackId(trackId)
	}
}
