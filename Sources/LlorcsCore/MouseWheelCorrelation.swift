import Foundation

enum MouseWheelCorrelation {
    static func deviceID(
        in reports: [(deviceID: String, time: UInt64)],
        now: UInt64,
        maxAgeNanoseconds: UInt64
    ) -> String? {
        var candidate: String?
        for report in reports.reversed() {
            guard now >= report.time, now - report.time <= maxAgeNanoseconds else { break }
            if let candidate, candidate != report.deviceID {
                return nil
            }
            candidate = report.deviceID
        }
        return candidate
    }
}
