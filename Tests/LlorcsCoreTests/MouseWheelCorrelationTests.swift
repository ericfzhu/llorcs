import XCTest
@testable import LlorcsCore

final class MouseWheelCorrelationTests: XCTestCase {
    func testReturnsSingleRecentDevice() {
        let reports = [
            (deviceID: "mouse-a", time: UInt64(940)),
            (deviceID: "mouse-a", time: UInt64(980))
        ]
        XCTAssertEqual(
            MouseWheelCorrelation.deviceID(in: reports, now: 1_000, maxAgeNanoseconds: 100),
            "mouse-a"
        )
    }

    func testNewestRecentDeviceWinsWhenSwitchingMice() {
        let reports = [
            (deviceID: "mouse-a", time: UInt64(960)),
            (deviceID: "mouse-b", time: UInt64(980))
        ]
        XCTAssertEqual(
            MouseWheelCorrelation.deviceID(in: reports, now: 1_000, maxAgeNanoseconds: 100),
            "mouse-b"
        )
    }

    func testIgnoresExpiredReportFromAnotherDevice() {
        let reports = [
            (deviceID: "mouse-b", time: UInt64(800)),
            (deviceID: "mouse-a", time: UInt64(980))
        ]
        XCTAssertEqual(
            MouseWheelCorrelation.deviceID(in: reports, now: 1_000, maxAgeNanoseconds: 100),
            "mouse-a"
        )
    }
}
