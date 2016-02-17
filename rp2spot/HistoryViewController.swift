//
//  HistoryController.swift
//  rp2spot
//
//  Created by Brian on 03/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import UIKit

class HistoryViewController: UIViewController {

	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
		RadioParadise.fetchPeriod("CH") { playedSongs, error, response in
			print("error: \(error)")  // on network timeout: Error Domain=NSURLErrorDomain Code=-1001 "The request timed out."
			print("response: \(response)")  // NSURLHTTPResponse
			print("playedSongs: \(playedSongs)")  // The array of PlayedSongdata, if no error
		}
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}



}

