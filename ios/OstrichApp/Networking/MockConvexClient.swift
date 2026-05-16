// MockConvexClient.swift
// 单测 + SwiftUI Preview 用：按 path 注入返回值或错误。
// 默认所有未 stub 的调用抛 ConvexError.internalError(message: "not stubbed: <path>")。

import Foundation

public final class MockConvexClient: ConvexClientProtocol, @unchecked Sendable {
    public var sessionToken: String?

    private let lock = NSLock()
    private var responses: [String: Any] = [:]
    private var errors: [String: ConvexError] = [:]

    /// 记录最近一次调用，便于断言。
    public private(set) var calls: [(path: String, body: Encodable?)] = []

    public init() {}

    // MARK: Stub API

    public func stub<R>(path: String, response: R) {
        lock.lock(); defer { lock.unlock() }
        responses[path] = response
        errors.removeValue(forKey: path)
    }

    public func stubError(path: String, error: ConvexError) {
        lock.lock(); defer { lock.unlock() }
        errors[path] = error
        responses.removeValue(forKey: path)
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        responses.removeAll()
        errors.removeAll()
        calls.removeAll()
    }

    // MARK: Protocol

    public func call<R: Decodable>(_ path: String, body: Encodable?) async throws -> R {
        try await dispatch(path: path, body: body)
    }

    public func get<R: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> R {
        // 路径里也带上 query，方便测试针对带 query 的 path 单独 stub。
        let fullPath: String
        if query.isEmpty {
            fullPath = path
        } else {
            var comps = URLComponents()
            comps.queryItems = query
            fullPath = path + (comps.percentEncodedQuery.map { "?\($0)" } ?? "")
        }
        return try await dispatch(path: fullPath, body: nil)
    }

    private func dispatch<R>(path: String, body: Encodable?) async throws -> R {
        lock.lock()
        let stubbed = responses[path]
        let err = errors[path]
        calls.append((path, body))
        lock.unlock()

        if let err = err {
            throw err
        }
        if let value = stubbed as? R {
            return value
        }
        if stubbed != nil {
            throw ConvexError.internalError(
                message: "MockConvexClient: stubbed response 类型不匹配 (\(path))"
            )
        }
        throw ConvexError.internalError(message: "not stubbed: \(path)")
    }
}
