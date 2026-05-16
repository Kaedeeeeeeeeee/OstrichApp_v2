// ConvexClient.swift
// HTTP 客户端：iOS 端所有 Features 调 Convex 后端的入口。
// INTERFACES.md §1 路径 / §3 DTO / §7 错误码 / §8 轮询策略。

import Foundation

// MARK: - Protocol

public protocol ConvexClientProtocol: AnyObject {
    var sessionToken: String? { get set }

    /// POST <baseURL><path>，body 默认 `{}`。
    /// 解析 `{ ok: true, data: ... }` 后返回 `data` 解码结果。
    func call<R: Decodable>(_ path: String, body: Encodable?) async throws -> R

    /// GET <baseURL><path>?queryItems
    func get<R: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> R
}

public extension ConvexClientProtocol {
    func call<R: Decodable>(_ path: String) async throws -> R {
        try await call(path, body: nil)
    }

    func get<R: Decodable>(_ path: String) async throws -> R {
        try await get(path, query: [])
    }
}

// MARK: - URLSession 抽象（便于注入 mock）

public protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - 实现

public final class ConvexClient: ConvexClientProtocol, @unchecked Sendable {
    public var sessionToken: String?

    private let baseURL: URL
    private let session: URLSessionProtocol
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let tokenLock = NSLock()

    public init(baseURL: URL, session: URLSessionProtocol = URLSession.shared) {
        self.baseURL = baseURL
        self.session = session

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
    }

    // MARK: Public API

    public func call<R: Decodable>(_ path: String, body: Encodable?) async throws -> R {
        let request = try buildRequest(path: path, method: "POST", body: body, query: [])
        return try await execute(request)
    }

    public func get<R: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> R {
        let request = try buildRequest(path: path, method: "GET", body: nil, query: query)
        return try await execute(request)
    }

    // MARK: Request 构建

    private func buildRequest(
        path: String,
        method: String,
        body: Encodable?,
        query: [URLQueryItem]
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(""),
            resolvingAgainstBaseURL: false
        ) else {
            throw ConvexError.internalError(message: "无法解析 baseURL")
        }
        // baseURL 可能不含 path；用直接拼接更稳。
        let absoluteString = baseURL.absoluteString.trimmingTrailing("/") + path
        guard var built = URLComponents(string: absoluteString) else {
            throw ConvexError.internalError(message: "URL 拼装失败：\(absoluteString)")
        }
        if !query.isEmpty {
            built.queryItems = query
        }
        guard let url = built.url else {
            throw ConvexError.internalError(message: "URL 构造失败")
        }
        _ = components // 仅为通过 lint

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = currentToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            do {
                request.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                throw ConvexError.decoding("body 编码失败：\(error.localizedDescription)")
            }
        } else if method == "POST" {
            request.httpBody = Data("{}".utf8)
        }
        return request
    }

    // MARK: 执行 + 错误翻译

    private func execute<R: Decodable>(_ request: URLRequest) async throws -> R {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ConvexError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ConvexError.internalError(message: "非 HTTP 响应")
        }

        // 优先解析 envelope；body 中带 `error.code` 时一律以 body 为准。
        let envelope = try? decoder.decode(ConvexEnvelope<R>.self, from: data)

        if let envelope = envelope, envelope.ok == false, let err = envelope.error {
            throw ConvexError.fromCode(err.code, message: err.message)
        }

        if !(200..<300).contains(http.statusCode) {
            // 4xx/5xx 但 envelope 没解到 → 按状态码兜底
            throw translateStatus(http.statusCode, body: data)
        }

        if let envelope = envelope, envelope.ok == true, let value = envelope.data {
            return value
        }

        // 兜底：直接把 body 当 R 解（部分 endpoint 可能未包 envelope）。
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw ConvexError.decoding(error.localizedDescription)
        }
    }

    private func translateStatus(_ status: Int, body: Data) -> ConvexError {
        // 试着再解一遍 envelope error（避免泛型 R 解码失败掩盖 error 字段）。
        if let envelope = try? decoder.decode(BareErrorEnvelope.self, from: body),
           envelope.ok == false, let err = envelope.error {
            return ConvexError.fromCode(err.code, message: err.message)
        }
        let message = String(data: body, encoding: .utf8) ?? ""
        switch status {
        case 401:           return .authRequired
        case 404:           return .ostrichNotFound
        case 409:           return .ostrichWandering   // 默认 409 翻成 wandering；具体 code 走 envelope
        case 429:           return .rateLimited
        case 503:           return .claudeUnavailable
        default:            return .internalError(message: "HTTP \(status): \(message)")
        }
    }

    private func currentToken() -> String? {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        return sessionToken
    }
}

// MARK: - 内部辅助

/// envelope 仅包含错误（用于 R 解码失败时的二次解析）。
private struct BareErrorEnvelope: Decodable {
    let ok: Bool
    let error: ConvexErrorPayload?
}

/// 将 Encodable 包成具体类型，供 JSONEncoder 编码。
struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        self.encodeFn = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeFn(encoder)
    }
}

private extension String {
    func trimmingTrailing(_ ch: Character) -> String {
        var s = self
        while s.last == ch {
            s.removeLast()
        }
        return s
    }
}
