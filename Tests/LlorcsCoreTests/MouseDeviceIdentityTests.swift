import XCTest
@testable import LlorcsCore

final class MouseDeviceIdentityTests: XCTestCase {
    func testSerialIdentityDoesNotDependOnConnectionLocation() {
        let first = MouseDeviceMonitor.makeStableDeviceID(
            vendor: 1,
            product: 2,
            serial: " ABC ",
            transport: "USB",
            location: 10
        )
        let second = MouseDeviceMonitor.makeStableDeviceID(
            vendor: 1,
            product: 2,
            serial: "ABC",
            transport: "USB",
            location: 99
        )
        XCTAssertEqual(first, second)
    }

    func testFallbackIdentityIncludesTransportAndLocation() {
        let usb = MouseDeviceMonitor.makeStableDeviceID(
            vendor: 1,
            product: 2,
            serial: nil,
            transport: "USB",
            location: 10
        )
        let bluetooth = MouseDeviceMonitor.makeStableDeviceID(
            vendor: 1,
            product: 2,
            serial: nil,
            transport: "Bluetooth",
            location: 10
        )
        XCTAssertNotEqual(usb, bluetooth)
    }

    func testPhysicalIdentityDistinguishesDevicesWithoutSerialNumbers() {
        let first = MouseDeviceMonitor.makeStableDeviceID(
            vendor: 1,
            product: 2,
            serial: nil,
            physicalID: "mouse-a",
            transport: "USB",
            location: 10
        )
        let second = MouseDeviceMonitor.makeStableDeviceID(
            vendor: 1,
            product: 2,
            serial: nil,
            physicalID: "mouse-b",
            transport: "USB",
            location: 10
        )
        XCTAssertNotEqual(first, second)
    }
}
