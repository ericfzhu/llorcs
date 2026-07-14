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

        let deltaFields: [CGEventField] = [
            .scrollWheelEventDeltaAxis1,
            .scrollWheelEventDeltaAxis2,
            .scrollWheelEventDeltaAxis3
        ]
        let fixedPointFields: [CGEventField] = [
            .scrollWheelEventFixedPtDeltaAxis1,
            .scrollWheelEventFixedPtDeltaAxis2,
            .scrollWheelEventFixedPtDeltaAxis3
        ]
        let pointFields: [CGEventField] = [
            .scrollWheelEventPointDeltaAxis1,
            .scrollWheelEventPointDeltaAxis2,
            .scrollWheelEventPointDeltaAxis3
        ]
        let deltasBefore = deltaFields.map { event.getIntegerValueField($0) }
        let fixedPointsBefore = fixedPointFields.map { event.getDoubleValueField($0) }
        let pointsBefore = pointFields.map { event.getIntegerValueField($0) }

        ScrollReverser.reverseDeltas(in: event)

        for (field, value) in zip(deltaFields, deltasBefore) {
            XCTAssertEqual(event.getIntegerValueField(field), -value)
        }
        for (field, value) in zip(fixedPointFields, fixedPointsBefore) {
            XCTAssertEqual(event.getDoubleValueField(field), -value, accuracy: 0.0001)
        }
        for (field, value) in zip(pointFields, pointsBefore) {
            XCTAssertEqual(event.getIntegerValueField(field), -value)
        }
    }
}
