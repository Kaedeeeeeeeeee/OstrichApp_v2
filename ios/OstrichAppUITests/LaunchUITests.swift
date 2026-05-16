import XCTest

/// Day 1 UI 烟囱测试 —— App 启动且不 crash。
final class LaunchUITests: XCTestCase {
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["鸵鸟"].waitForExistence(timeout: 5))
    }
}
