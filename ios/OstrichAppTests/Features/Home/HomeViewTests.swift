// HomeViewTests.swift
// 简单 smoke：实例化 HomeView 不崩。

import Testing
import SwiftUI
@testable import OstrichApp

@MainActor
struct HomeViewTests {
    @Test func homeViewInstantiates() {
        let view = HomeView()
        _ = view.body
    }
}
