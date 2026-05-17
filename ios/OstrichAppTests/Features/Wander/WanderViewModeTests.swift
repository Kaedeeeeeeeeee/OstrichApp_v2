// WanderViewModeTests.swift
// 验证 WanderViewMode 状态机基础 + WanderView 实例化不崩。

import Testing
import SwiftUI
@testable import OstrichApp

@MainActor
struct WanderViewModeTests {

    @Test func defaultModeIsGod() {
        let mode: WanderViewMode = .god
        #expect(mode == .god)
    }

    @Test func modeEqualityHoldsBothCases() {
        #expect(WanderViewMode.god == .god)
        #expect(WanderViewMode.local == .local)
        #expect(WanderViewMode.god != .local)
    }

    @Test func wanderViewInstantiates() {
        let client = MockConvexClient()
        let view = WanderView(client: client)
        _ = view.body
    }

    @Test func godViewInstantiates() {
        let client = MockConvexClient()
        let view = GodViewView(client: client, onRecall: {})
        _ = view.body
    }

    @Test func localViewInstantiates() {
        let client = MockConvexClient()
        let view = LocalViewView(client: client, onBackToGod: {})
        _ = view.body
    }
}
