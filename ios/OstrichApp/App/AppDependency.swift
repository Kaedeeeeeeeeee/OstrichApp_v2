// AppDependency.swift
// 应用级依赖容器：持有 ConvexClientProtocol 实例，由 @main 注入到 environmentObject。
// Features 通过 @EnvironmentObject var deps: AppDependency 取 client。

import Foundation
import SwiftUI

@MainActor
public final class AppDependency: ObservableObject {
    public let client: ConvexClientProtocol

    public init(client: ConvexClientProtocol) {
        self.client = client
    }

    /// 默认构造：使用真实的 ConvexClient + AppEnvironment.shared.convexURL。
    public static func makeDefault() -> AppDependency {
        AppDependency(
            client: ConvexClient(baseURL: AppEnvironment.shared.convexURL)
        )
    }
}
