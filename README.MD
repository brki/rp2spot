## rp2pot

This is an application that shows a history of the songs that have been played on
[Radio Paradise](http://www.radioparadise.com/) and allows streaming these songs
from [Spotify](https://www.spotify.com/).  It also allows you to create Spotify
playlists based on songs that you choose out of the Radio Paradise history.  Note
that not all songs that have been played on Radio Paradise are available on Spotify,
and the availability of songs varies for different Spotify regions.


### Implementation notes
* The [Spotify ios-sdk](https://github.com/spotify/ios-sdk/) did not (at the time of
  writing this README) provide a possibility to include their framework via Carthage,
  so it has been included directly in this repository.

### Building notes

#### Carthage
Run ``carthage update --platform ios`` 

#### Secrets.swift
Copy ``rp2spot/Secrets.swift-dist`` to ``rp2spot/Secrets.swift`` and edit it, setting
values for the Spotify client ID and related values.
