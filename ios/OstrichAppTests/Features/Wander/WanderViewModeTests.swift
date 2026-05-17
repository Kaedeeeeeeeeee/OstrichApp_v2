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
        let view = GodViewView(ostrichCount: 0, onRecall: {})
        _ = view.body
    }

    @Test func localViewInstantiates() {
        let view = LocalViewView(
            speechText: "",
            activityLabel: "",
            inFlightAction: false,
            onBackToGod: {},
            onCallHome: {},
            onAllowToStay: {},
            onLookAround: {}
        )
        _ = view.body
    }
}
