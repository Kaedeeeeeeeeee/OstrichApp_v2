// SettingsViewTests.swift
// 实例化 smoke + IfImGoneView 三个选项可枚举。

import Testing
import SwiftUI
@testable import OstrichApp

@MainActor
struct SettingsViewTests {

    @Test func settingsViewInstantiates() {
        let view = SettingsView()
        _ = view.body
    }

    @Test func ifImGoneViewInstantiates() {
        let view = IfImGoneView()
        _ = view.body
    }

    @Test func ifImGoneHasThreeDispositions() {
        let all = IfImGoneView.Disposition.allCases
        #expect(all.count == 3)
        #expect(all.contains(.takeAway))
        #expect(all.contains(.transfer))
        #expect(all.contains(.release))
    }

    @Test func eachDispositionHasNonEmptyCopy() {
        for option in IfImGoneView.Disposition.allCases {
            #expect(!option.title.isEmpty)
            #expect(!option.subtitle.isEmpty)
            #expect(!option.detail.isEmpty)
            #expect(!option.icon.isEmpty)
        }
    }
}
