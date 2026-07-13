import CoreGraphics

public enum ScrollDeviceKind: Equatable {
    case trackpad
    case mouse(deviceID: String?)
}

public struct ScrollEventSignals {
    public let isContinuous: Bool
    public let scrollPhase: Int64
    public let momentumPhase: Int64
    public let recentMouseDeviceID: String?

    public init(
        isContinuous: Bool,
        scrollPhase: Int64,
        momentumPhase: Int64,
        recentMouseDeviceID: String?
    ) {
        self.isContinuous = isContinuous
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.recentMouseDeviceID = recentMouseDeviceID
    }
}

public enum ScrollClassifier {
    public static func classify(_ signals: ScrollEventSignals) -> ScrollDeviceKind {
        // A raw HID wheel report is the strongest public signal we have. CGEvent
        // itself does not include the originating device.
        if let deviceID = signals.recentMouseDeviceID {
            return .mouse(deviceID: deviceID)
        }

        // Discrete wheel events are emitted by conventional mice. Gesture
        // surfaces typically use continuous deltas and phase information.
        if !signals.isContinuous && signals.scrollPhase == 0 && signals.momentumPhase == 0 {
            return .mouse(deviceID: nil)
        }

        return .trackpad
    }
}
