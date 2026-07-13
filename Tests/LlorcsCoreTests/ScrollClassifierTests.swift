import XCTest
@testable import LlorcsCore

final class ScrollClassifierTests: XCTestCase {
    func testRecentHIDWheelWinsOverContinuousSignal() {
        let result = ScrollClassifier.classify(.init(
            isContinuous: true,
            scrollPhase: 1,
            momentumPhase: 0,
            recentMouseDeviceID: "mouse-1"
        ))
        XCTAssertEqual(result, .mouse(deviceID: "mouse-1"))
    }

    func testDiscreteWheelIsMouse() {
        let result = ScrollClassifier.classify(.init(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            recentMouseDeviceID: nil
        ))
        XCTAssertEqual(result, .mouse(deviceID: nil))
    }

    func testContinuousPhasedEventIsTrackpad() {
        let result = ScrollClassifier.classify(.init(
            isContinuous: true,
            scrollPhase: 1,
            momentumPhase: 0,
            recentMouseDeviceID: nil
        ))
        XCTAssertEqual(result, .trackpad)
    }
}
