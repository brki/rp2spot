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
	init?(response: HTTPURLResponse, representation: AnyObject)
}

extension Request {
	public func responseObject<T: ResponseObjectSerializable>(_ completionHandler: (Response<T, NSError>) -> Void) -> Self {
		let responseSerializer = ResponseSerializer<T, NSError> { request, response, data, error in
			guard error == nil else { return .failure(error!) }

			let JSONResponseSerializer = Request.JSONResponseSerializer(options: .allowFragments)
			let result = JSONResponseSerializer.serializeResponse(request, response, data, error)

			switch result {
			case .success(let value):
				if let
					response = response,
					let responseObject = T(response: response, representation: value)
				{
					return .success(responseObject)
				} else {
					let failureReason = "JSON could not be serialized into response object: \(value)"
					let error = Alamofire.Error.errorWithCode(.jsonSerializationFailed, failureReason: failureReason)
					return .failure(error)
				}
			case .failure(let error):
				return .failure(error)
			}
		}

		return response(responseSerializer: responseSerializer, completionHandler: completionHandler)
	}
}

public protocol ResponseCollectionSerializable {
	static func collection(response: HTTPURLResponse, representation: AnyObject) -> [Self]
}

extension Alamofire.Request {
	public func responseCollection<T: ResponseCollectionSerializable>(_ completionHandler: (Response<[T], NSError>) -> Void) -> Self {
		let responseSerializer = ResponseSerializer<[T], NSError> { request, response, data, error in
			guard error == nil else { return .failure(error!) }

			let JSONSerializer = Request.JSONResponseSerializer(options: .allowFragments)
			let result = JSONSerializer.serializeResponse(request, response, data, error)

			switch result {
			case .success(let value):
				if let response = response {
					return .success(T.collection(response: response, representation: value))
				} else {
					let failureReason = "Response collection could not be serialized due to nil response"
					let error = Alamofire.Error.errorWithCode(.jsonSerializationFailed, failureReason: failureReason)
					return .failure(error)
				}
			case .failure(let error):
				return .failure(error)
			}
		}

		return response(responseSerializer: responseSerializer, completionHandler: completionHandler)
	}
}
