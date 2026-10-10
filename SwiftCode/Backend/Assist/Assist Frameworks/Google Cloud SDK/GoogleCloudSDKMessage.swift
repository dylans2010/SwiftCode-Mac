//
//  GoogleCloudSDKMessage.swift
//  SwiftCode
//
//  Message and attachment domain models for Antigravity sessions.
//

import Foundation

public struct GoogleCloudSDKAttachment: Identifiable, Sendable, Codable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let mimeType: String?
    public let content: String?

    public init(name: String, path: String, mimeType: String? = nil, content: String? = nil) {
        self.name = name
        self.path = path
        self.mimeType = mimeType
        self.content = content
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "path": path,
        ]
        if let mimeType = mimeType { dict["mimeType"] = mimeType }
        if let content = content { dict["content"] = content }
        return dict
    }
}

public struct GoogleCloudSDKResponse: Sendable {
    public let data: [String: JSONValue]

    public init(_ data: [String: JSONValue] = [:]) {
        self.data = data
    }

    public subscript(key: String) -> JSONValue? {
        data[key]
    }

    public var status: String? {
        if case .string(let str) = data["status"] { return str }
        return nil
    }

    public var conversationId: String? {
        if case .string(let str) = data["conversationId"] { return str }
        return nil
    }

    public var sdkVersion: String? {
        if case .string(let str) = data["sdkVersion"] { return str }
        return nil
    }
}
