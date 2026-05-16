import Testing
import SwiftUI
@testable import OstrichApp

/// Token 数值与色板 hex 解析正确性测试。
struct TokenTests {

    // MARK: - Colors

    @Test func creamMatchesHexFCFEE8() {
        let (r, g, b) = rgbComponents(of: OstrichColors.cream)
        #expect(approxEqual(r, 0xFC / 255.0))
        #expect(approxEqual(g, 0xFE / 255.0))
        #expect(approxEqual(b, 0xE8 / 255.0))
    }

    @Test func creamDeepMatchesHexF5EAB8() {
        let (r, g, b) = rgbComponents(of: OstrichColors.creamDeep)
        #expect(approxEqual(r, 0xF5 / 255.0))
        #expect(approxEqual(g, 0xEA / 255.0))
        #expect(approxEqual(b, 0xB8 / 255.0))
    }

    @Test func orangeMatchesHexFC8B40() {
        let (r, g, b) = rgbComponents(of: OstrichColors.orange)
        #expect(approxEqual(r, 0xFC / 255.0))
        #expect(approxEqual(g, 0x8B / 255.0))
        #expect(approxEqual(b, 0x40 / 255.0))
    }

    @Test func orangeDeepMatchesHexCD4A0F() {
        let (r, g, b) = rgbComponents(of: OstrichColors.orangeDeep)
        #expect(approxEqual(r, 0xCD / 255.0))
        #expect(approxEqual(g, 0x4A / 255.0))
        #expect(approxEqual(b, 0x0F / 255.0))
    }

    @Test func inkMatchesHex27281D() {
        let (r, g, b) = rgbComponents(of: OstrichColors.ink)
        #expect(approxEqual(r, 0x27 / 255.0))
        #expect(approxEqual(g, 0x28 / 255.0))
        #expect(approxEqual(b, 0x1D / 255.0))
    }

    @Test func bodyBackgroundMatchesHexDBD3B8() {
        let (r, g, b) = rgbComponents(of: OstrichColors.bodyBackground)
        #expect(approxEqual(r, 0xDB / 255.0))
        #expect(approxEqual(g, 0xD3 / 255.0))
        #expect(approxEqual(b, 0xB8 / 255.0))
    }

    // MARK: - Spacing

    @Test func spacingScale() {
        #expect(OstrichSpacing.xs == 4)
        #expect(OstrichSpacing.s == 8)
        #expect(OstrichSpacing.m == 12)
        #expect(OstrichSpacing.l == 16)
        #expect(OstrichSpacing.xl == 20)
        #expect(OstrichSpacing.xxl == 28)
    }

    @Test func radiusScale() {
        #expect(OstrichRadius.small == 10)
        #expect(OstrichRadius.medium == 14)
        #expect(OstrichRadius.large == 18)
        #expect(OstrichRadius.pill == 999)
    }

    // MARK: - Helpers

    private func rgbComponents(of color: Color) -> (CGFloat, CGFloat, CGFloat) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    private func approxEqual(_ a: CGFloat, _ b: CGFloat, tol: CGFloat = 0.005) -> Bool {
        abs(a - b) < tol
    }
}
