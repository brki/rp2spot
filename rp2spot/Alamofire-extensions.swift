//
//  Alamofire-extensions.swift
//  rp2spot
//
//  Created by Brian on 14/02/16.
//  Copyright © 2016 truckin'. All rights reserved.
//

import Foundation
import Alamofire

// These protocols / extensions are taken from the Alamofire documentation; they allow straightforward deserialization of
// JSON responses using a final class that handles initializing itself with the json values.


public protocol ResponseObjectSerializable {
	init?(response: NSHTTPURLResponse, representation: AnyObject)
}

extension Request {
	public func responseObject<T: ResponseObjectSerializable>(completionHandler: Response<T, NSError> -> Void) -> Self {
		let responseSerializer = ResponseSerializer<T, NSError> { request, response, data, error in
			guard error == nil else { return .Failure(error!) }

			let JSONResponseSerializer = Request.JSONResponseSerializer(options: .AllowFragments)
			let result = JSONResponseSerializer.serializeResponse(request, response, data, error)

			switch result {
			case .Success(let value):
				if let
					response = response,
					responseObject = T(response: response, representation: value)
				{
					return .Success(responseObject)
				} else {
					let failureReason = "JSON could not be serialized into response object: \(value)"
					let error = Error.errorWithCode(.JSONSerializationFailed, failureReason: failureReason)
					return .Failure(error)
				}
			case .Failure(let error):
				return .Failure(error)
			}
		}

		return response(responseSerializer: responseSerializer, completionHandler: completionHandler)
	}
}

public protocol ResponseCollectionSerializable {
	static func collection(response response: NSHTTPURLResponse, representation: AnyObject) -> [Self]
}

extension Alamofire.Request {
	public func responseCollection<T: ResponseCollectionSerializable>(completionHandler: Response<[T], NSError> -> Void) -> Self {
		let responseSerializer = ResponseSerializer<[T], NSError> { request, response, data, error in
			guard error == nil else { return .Failure(error!) }

			let JSONSerializer = Request.JSONResponseSerializer(options: .AllowFragments)
			let result = JSONSerializer.serializeResponse(request, response, data, error)

			switch result {
			case .Success(let value):
				if let response = response {
					return .Success(T.collection(response: response, representation: value))
				} else {
					let failureReason = "Response collection could not be serialized due to nil response"
					let error = Error.errorWithCode(.JSONSerializationFailed, failureReason: failureReason)
					return .Failure(error)
				}
			case .Failure(let error):
				return .Failure(error)
			}
		}

		return response(responseSerializer: responseSerializer, completionHandler: completionHandler)
	}
}