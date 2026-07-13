import CoreGraphics
import XCTest
@testable import LlorcsCore

final class ScrollReverserTests: XCTestCase {
    func testReverseDeltasNegatesEveryDeltaRepresentation() throws {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 14,
            wheel2: -9,
            wheel3: 0
        ))

        let integerFields: [CGEventField] = [
            .scrollWheelEventDeltaAxis1,
            .scrollWheelEventDeltaAxis2,
            .scrollWheelEventDeltaAxis3
        ]
        let doubleFields: [CGEventField] = [
            .scrollWheelEventFixedPtDeltaAxis1,
            .scrollWheelEventFixedPtDeltaAxis2,
            .scrollWheelEventFixedPtDeltaAxis3,
            .scrollWheelEventPointDeltaAxis1,
            .scrollWheelEventPointDeltaAxis2,
            .scrollWheelEventPointDeltaAxis3
        ]
        let integersBefore = integerFields.map { event.getIntegerValueField($0) }
        let doublesBefore = doubleFields.map { event.getDoubleValueField($0) }

        ScrollReverser.reverseDeltas(in: event)

        for (field, value) in zip(integerFields, integersBefore) {
            XCTAssertEqual(event.getIntegerValueField(field), -value)
        }
        for (field, value) in zip(doubleFields, doublesBefore) {
            XCTAssertEqual(event.getDoubleValueField(field), -value, accuracy: 0.0001)
        }
    }
}
