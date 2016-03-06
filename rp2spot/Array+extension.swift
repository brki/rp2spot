//
//  Array+extension.swift
//  rp2spot
//
//  Created by Brian on 06/03/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation

extension Array {

	/**
	Remove all the values from the array, returning a new array with those values.

	This is a thread-safe, lockless way to get all of the values in the array, leaving the original
	array empty (at least empty according to this thread).

	If preserveOrder == false, the values will be returned in reverse order.
	*/
	mutating func removeAllReturningValues(preserveOrder preserveOrder: Bool = false) -> [Element] {
		var values = [Element]()
		while let value = self.popLast() {
			values.append(value)
		}
		if preserveOrder {
			return values.reverse()
		}
		return values
	}
}