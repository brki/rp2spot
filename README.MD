## rp2spot

This is an application that shows a history of the songs that have been played on
[Radio Paradise](http://www.radioparadise.com/).  If you have a Spotify account
this app allows you to create Spotify playlists based on songs that you choose out
of the Radio Paradise history.  Note that not all songs that have been played on
Radio Paradise are available on Spotify, and the availability of songs varies for
different Spotify regions.

If you have a Premium Spotify account, you can stream the available songs from
the Radio Paradise history list directly in this app.

### Implementation notes
* The [Spotify ios-sdk](https://github.com/spotify/ios-sdk/) did not (at the time of
  writing this README) provide a possibility to include their framework via Carthage,
  so it has been included directly in this repository.

### Building notes

#### Carthage
Run ``carthage bootstrap --platform ios``

Or, to update to the latest versions of the carthage-managed libraries: ``carthage update --platform ios``

#### Secrets.swift
Copy ``rp2spot/Secrets.swift-dist`` to ``rp2spot/Secrets.swift`` and edit it, setting
values for the Spotify client ID and related values.
