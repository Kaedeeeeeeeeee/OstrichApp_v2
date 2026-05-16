// AppEnvironment.swift
// 提供 Convex base URL。
// - Debug: 优先读 Info.plist `ConvexURL`；缺省回落 http://localhost:3210（Convex dev 端口）。
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
        } else if let fallback = URL(string: "http://localhost:3210") {
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
