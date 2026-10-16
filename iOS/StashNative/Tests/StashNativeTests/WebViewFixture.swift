import XCTest

enum WebViewFixture {
    static let startupTimeout: TimeInterval = 60

    @MainActor static func waitForLoad(_ expectation: XCTestExpectation,
                                       file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        let result = await XCTWaiter.fulfillment(of:[expectation], timeout:startupTimeout)
        XCTAssertEqual(result, .completed, "WebView fixture must finish loading: \(expectation.expectationDescription)",
                       file:file, line:line)
        return result == .completed
    }
}
