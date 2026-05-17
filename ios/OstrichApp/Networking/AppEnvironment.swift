// AppEnvironment.swift
// 提供 Convex base URL。
// - Debug: 优先读 Info.plist `ConvexURL`；缺省回落 http://localhost:3211。
//   注意：本地 anonymous Convex 部署有两个端口
//     - 3210 (CONVEX_URL):       function call 端点 (/api/run/<fn>)
//     - 3211 (CONVEX_SITE_URL):  httpRouter 端点 (/api/awaken 等 REST)
//   iOS ConvexClient 调的是 REST routes，所以必须用 3211。
// - Release: hardcoded prod URL（占位 https://ostrich-prod.convex.cloud）。

import Foundation

public struct AppEnvironment {
    public static let shared = AppEnvironment()

    public let convexURL: URL

    public init(bundle: Bundle = .main) {
        #if DEBUG
        if let raw = bundle.object(forInfoDictionaryKey: "ConvexURL") as? String,
           let url = URL(string: raw),
           !raw.isEmpty {
            self.convexURL = url
        } else if let fallback = URL(string: "http://localhost:3211") {
            self.convexURL = fallback
        } else {
            preconditionFailure("Failed to construct fallback Convex URL")
        }
        #else
        if let url = URL(string: "https://ostrich-prod.convex.cloud") {
            self.convexURL = url
        } else {
            preconditionFailure("Failed to construct prod Convex URL")
        }
        #endif
    }
}
