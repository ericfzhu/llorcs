import Foundation
import XCTest
@testable import LlorcsCore

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsReverseMouseButNotTrackpad() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.shouldReverse(.mouse(deviceID: nil)))
        XCTAssertFalse(store.shouldReverse(.trackpad))
    }

    func testDeviceRuleOverridesMouseDefault() {
        let store = SettingsStore(defaults: defaults)
        store.reverseMouse = false
        store.setRule(.reverse, for: "mouse-a")
        store.setRule(.standard, for: "mouse-b")

        XCTAssertTrue(store.shouldReverse(.mouse(deviceID: "mouse-a")))
        XCTAssertFalse(store.shouldReverse(.mouse(deviceID: "mouse-b")))
        XCTAssertFalse(store.shouldReverse(.mouse(deviceID: "mouse-c")))
    }

    func testDisabledStoreNeverReverses() {
        let store = SettingsStore(defaults: defaults)
        store.reverseTrackpad = true
        store.setRule(.reverse, for: "mouse-a")
        store.enabled = false

        XCTAssertFalse(store.isEnabledForEventTap())
        XCTAssertFalse(store.shouldReverse(.trackpad))
        XCTAssertFalse(store.shouldReverse(.mouse(deviceID: "mouse-a")))
    }
}
