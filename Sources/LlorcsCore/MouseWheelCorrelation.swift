import Foundation

enum MouseWheelCorrelation {
    static func deviceID(
        in reports: [(deviceID: String, time: UInt64)],
        now: UInt64,
        maxAgeNanoseconds: UInt64
    ) -> String? {
        for report in reports.reversed() {
            guard now >= report.time else { continue }
            guard now - report.time <= maxAgeNanoseconds else { break }
            return report.deviceID
        }
        return nil
    }
}
