import Testing
@testable import OstrichApp

/// Day 1 烟囱测试 —— 确认 test target build 通过。
/// 实际单测从 Day 2+ 写起。
struct SmokeTests {
    @Test func appNameMatches() {
        #expect("鸵鸟" == "鸵鸟")
    }
}
