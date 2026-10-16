import XCTest
import UIKit

final class HostReadinessTests: XCTestCase {
    @MainActor func testHostHasActiveApplicationAndKeyWindowScene() async {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.stash.stashnative.testhost")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            UIApplication.shared.applicationState == .active &&
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.contains { scene in
                    scene.activationState == .foregroundActive &&
                        scene.windows.contains { $0.isKeyWindow && $0.rootViewController != nil }
                }
        }, object: nil)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 10)
        XCTAssertEqual(result, .completed, "UIKit tests require an active app and a foreground key window")
    }
}
