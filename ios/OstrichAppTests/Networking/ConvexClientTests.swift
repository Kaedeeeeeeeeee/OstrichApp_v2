// ConvexClientTests.swift
// 用 URLProtocol mock 拦截请求，验证 ConvexClient 的序列化 / 反序列化 / 错误翻译。

import Foundation
import Testing
@testable import OstrichApp

// MARK: - URLProtocol Stub

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let statusCode: Int
        let body: Data
        let headers: [String: String]
        let error: Error?
    }

    nonisolated(unsafe) private static var stubProvider: ((URLRequest) -> Stub)?
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []
    private static let lock = NSLock()

    static func set(provider: @escaping (URLRequest) -> Stub) {
        lock.lock(); defer { lock.unlock() }
        stubProvider = provider
        capturedRequests = []
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        stubProvider = nil
        capturedRequests = []
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return capturedRequests
    }

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(request)
        let provider = Self.stubProvider
        Self.lock.unlock()

        guard let stub = provider?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        if let err = stub.error {
            client?.urlProtocol(self, didFailWithError: err)
            return
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"),
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!  // swiftlint:disable:this force_unwrapping
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeClient() -> (ConvexClient, URLSession) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    // swiftlint:disable:next force_unwrapping
    let base = URL(string: "https://test.convex.cloud")!
    let client = ConvexClient(baseURL: base, session: session)
    return (client, session)
}

private func jsonData(_ object: Any) -> Data {
    // swiftlint:disable:next force_try
    return try! JSONSerialization.data(withJSONObject: object, options: [])
}

// MARK: - Tests

struct ConvexClientTests {

    @Test func happyPathDecodesOstrichDTO() async throws {
        let (client, _) = makeClient()

        let payload: [String: Any] = [
            "ok": true,
            "data": [
                "id": "ost_1",
                "ownerId": "usr_1",
                "name": "豆豆",
                "eggType": 3,
                "archetype": "POET",
                "awakenedAt": "2026-05-16T10:00:00Z",
                "state": "wandering",
                "currentLocation": [
                    "lat": 35.66, "lng": 139.70, "friendlyName": "涩谷 神南"
                ],
                "currentActivity": "walking",
                "daysTogether": 1
            ]
        ]
        StubURLProtocol.set { _ in
            .init(statusCode: 200, body: jsonData(payload), headers: ["Content-Type": "application/json"], error: nil)
        }
        defer { StubURLProtocol.clear() }

        let dto: OstrichDTO = try await client.get(Endpoints.ostrichSelf)
        #expect(dto.id == "ost_1")
        #expect(dto.name == "豆豆")
        #expect(dto.eggType == 3)
        #expect(dto.currentLocation.friendlyName == "涩谷 神南")
        #expect(dto.daysTogether == 1)
    }

    @Test func sendsAuthorizationHeader() async throws {
        let (client, _) = makeClient()
        client.sessionToken = "tok_abc"

        StubURLProtocol.set { _ in
            .init(statusCode: 200, body: jsonData(["ok": true, "data": ["ok": true]]), headers: [:], error: nil)
        }
        defer { StubURLProtocol.clear() }

        let _: OkResponseDTO = try await client.call(Endpoints.signOut, body: nil)
        let req = StubURLProtocol.requests.first
        #expect(req?.value(forHTTPHeaderField: "Authorization") == "Bearer tok_abc")
        #expect(req?.httpMethod == "POST")
    }

    @Test func error401MapsToAuthRequired() async throws {
        let (client, _) = makeClient()
        StubURLProtocol.set { _ in
            .init(
                statusCode: 401,
                body: jsonData(["ok": false, "error": ["code": "AUTH_REQUIRED", "message": "no token"]]),
                headers: [:],
                error: nil
            )
        }
        defer { StubURLProtocol.clear() }
        do {
            let _: OstrichDTO = try await client.get(Endpoints.ostrichSelf)
            Issue.record("应该抛错")
        } catch let err as ConvexError {
            #expect(err == .authRequired)
        }
    }

    @Test func error429MapsToRateLimited() async throws {
        let (client, _) = makeClient()
        StubURLProtocol.set { _ in
            .init(
                statusCode: 429,
                body: jsonData(["ok": false, "error": ["code": "RATE_LIMITED", "message": "slow down"]]),
                headers: [:],
                error: nil
            )
        }
        defer { StubURLProtocol.clear() }
        do {
            let _: OstrichDTO = try await client.get(Endpoints.ostrichSelf)
            Issue.record("应该抛错")
        } catch let err as ConvexError {
            #expect(err == .rateLimited)
        }
    }

    @Test func error503ClaudeUnavailable() async throws {
        let (client, _) = makeClient()
        StubURLProtocol.set { _ in
            .init(
                statusCode: 503,
                body: jsonData(["ok": false, "error": ["code": "CLAUDE_UNAVAILABLE", "message": "claude down"]]),
                headers: [:],
                error: nil
            )
        }
        defer { StubURLProtocol.clear() }
        do {
            let _: ChatSendResponseDTO = try await client.call(Endpoints.chatSend, body: ["roomId": "r1", "content": "hi"] as [String: String])
            Issue.record("应该抛错")
        } catch let err as ConvexError {
            #expect(err == .claudeUnavailable)
        }
    }

    @Test func error503MapsUnavailable() async throws {
        let (client, _) = makeClient()
        StubURLProtocol.set { _ in
            .init(
                statusCode: 503,
                body: jsonData(["ok": false, "error": ["code": "MAPS_UNAVAILABLE", "message": "maps down"]]),
                headers: [:],
                error: nil
            )
        }
        defer { StubURLProtocol.clear() }
        do {
            let _: MapLocalViewResponseDTO = try await client.get(Endpoints.mapLocal)
            Issue.record("应该抛错")
        } catch let err as ConvexError {
            #expect(err == .mapsUnavailable)
        }
    }

    @Test func ostrichWanderingErrorTranslated() async throws {
        let (client, _) = makeClient()
        StubURLProtocol.set { _ in
            .init(
                statusCode: 409,
                body: jsonData(["ok": false, "error": ["code": "OSTRICH_WANDERING", "message": "out"]]),
                headers: [:],
                error: nil
            )
        }
        defer { StubURLProtocol.clear() }
        do {
            let _: ChatSendResponseDTO = try await client.call(Endpoints.chatSend, body: ["roomId": "r1", "content": "hi"] as [String: String])
            Issue.record("应该抛错")
        } catch let err as ConvexError {
            #expect(err == .ostrichWandering)
            #expect(err.errorDescription?.contains("不在家") == true)
        }
    }

    @Test func decodingFailureReturnsDecodingError() async throws {
        let (client, _) = makeClient()
        StubURLProtocol.set { _ in
            // 200 OK 但 body 不是 envelope，也不是合法的 OstrichDTO。
            .init(statusCode: 200, body: Data("{\"not\":\"matching\"}".utf8), headers: [:], error: nil)
        }
        defer { StubURLProtocol.clear() }
        do {
            let _: OstrichDTO = try await client.get(Endpoints.ostrichSelf)
            Issue.record("应该抛错")
        } catch let err as ConvexError {
            if case .decoding = err {
                // ok
            } else {
                Issue.record("期望 decoding error，实际：\(err)")
            }
        }
    }

    @Test func transportFailureReturnsTransportError() async throws {
        let (client, _) = makeClient()
        StubURLProtocol.set { _ in
            .init(statusCode: 0, body: Data(), headers: [:], error: URLError(.notConnectedToInternet))
        }
        defer { StubURLProtocol.clear() }
        do {
            let _: OstrichDTO = try await client.get(Endpoints.ostrichSelf)
            Issue.record("应该抛错")
        } catch let err as ConvexError {
            if case .transport = err {
                // ok
            } else {
                Issue.record("期望 transport error，实际：\(err)")
            }
        }
    }

    @Test func mockClientStubbedResponse() async throws {
        let mock = MockConvexClient()
        let ostrich = OstrichDTO(
            id: "x", ownerId: "y", name: "豆豆", eggType: 1, archetype: "STEADFAST",
            awakenedAt: "2026-05-16T00:00:00Z", state: "awake",
            currentLocation: LocationDTO(lat: 0, lng: 0, friendlyName: "家"),
            currentActivity: "resting", daysTogether: 0
        )
        mock.stub(path: Endpoints.ostrichSelf, response: ostrich)
        let result: OstrichDTO = try await mock.get(Endpoints.ostrichSelf)
        #expect(result.name == "豆豆")
    }

    @Test func mockClientStubbedError() async throws {
        let mock = MockConvexClient()
        mock.stubError(path: Endpoints.ostrichSelf, error: .ostrichWandering)
        do {
            let _: OstrichDTO = try await mock.get(Endpoints.ostrichSelf)
            Issue.record("应该抛错")
        } catch let err as ConvexError {
            #expect(err == .ostrichWandering)
        }
    }

    @Test func mockClientUnstubbedThrowsInternal() async throws {
        let mock = MockConvexClient()
        do {
            let _: OstrichDTO = try await mock.get(Endpoints.ostrichSelf)
            Issue.record("应该抛错")
        } catch let err as ConvexError {
            if case .internalError(let message) = err {
                #expect(message.contains("not stubbed"))
            } else {
                Issue.record("期望 internalError，实际：\(err)")
            }
        }
    }

    @Test func endpointConstantsMatchInterfacesSpec() {
        // 防止有人误改路径常量。这些值必须与 INTERFACES.md §1 完全一致。
        #expect(Endpoints.awaken == "/api/awaken")
        #expect(Endpoints.ostrichSelf == "/api/ostrich/self")
        #expect(Endpoints.callHome == "/api/ostrich/callHome")
        #expect(Endpoints.chatSend == "/api/chat/send")
        #expect(Endpoints.chatRoom == "/api/chat/room/")
        #expect(Endpoints.confirmAddPerson == "/api/chat/confirmAddPerson")
        #expect(Endpoints.graph == "/api/graph")
        #expect(Endpoints.categorize == "/api/graph/categorize")
        #expect(Endpoints.personRoom == "/api/graph/personRoom/")
        #expect(Endpoints.diary == "/api/diary")
        #expect(Endpoints.requestUnlock == "/api/diary/requestUnlock")
        #expect(Endpoints.mapGod == "/api/map/godView")
        #expect(Endpoints.mapLocal == "/api/map/localView")
        #expect(Endpoints.signInWithApple == "/api/auth/signInWithApple")
        #expect(Endpoints.signOut == "/api/auth/signOut")
        #expect(Endpoints.sealOstrichInEgg == "/api/settings/sealOstrichInEgg")
        #expect(Endpoints.release == "/api/settings/release")
        #expect(Endpoints.transfer == "/api/settings/transfer")
    }
}
