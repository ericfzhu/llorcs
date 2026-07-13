import Foundation

public enum DeviceScrollRule: Int, CaseIterable, Identifiable {
    case inherit = 0
    case reverse = 1
    case standard = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .inherit: "Use mouse default"
        case .reverse: "Reverse"
        case .standard: "Standard"
        }
    }
}

public final class SettingsStore: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let reverseTrackpad = "reverseTrackpad"
        static let reverseMouse = "reverseMouse"
        static let deviceRules = "deviceRules"
    }

    private struct Snapshot {
        var enabled: Bool
        var reverseTrackpad: Bool
        var reverseMouse: Bool
        var deviceRules: [String: Int]
    }

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var snapshot: Snapshot

    @Published public var enabled: Bool { didSet { save() } }
    @Published public var reverseTrackpad: Bool { didSet { save() } }
    @Published public var reverseMouse: Bool { didSet { save() } }
    @Published private var deviceRules: [String: Int] { didSet { save() } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.reverseTrackpad: false,
            Key.reverseMouse: true
        ])

        let enabled = defaults.bool(forKey: Key.enabled)
        let reverseTrackpad = defaults.bool(forKey: Key.reverseTrackpad)
        let reverseMouse = defaults.bool(forKey: Key.reverseMouse)
        let rules = defaults.dictionary(forKey: Key.deviceRules) as? [String: Int] ?? [:]

        self.enabled = enabled
        self.reverseTrackpad = reverseTrackpad
        self.reverseMouse = reverseMouse
        self.deviceRules = rules
        self.snapshot = Snapshot(
            enabled: enabled,
            reverseTrackpad: reverseTrackpad,
            reverseMouse: reverseMouse,
            deviceRules: rules
        )
    }

    public func rule(for deviceID: String) -> DeviceScrollRule {
        DeviceScrollRule(rawValue: deviceRules[deviceID] ?? 0) ?? .inherit
    }

    public func setRule(_ rule: DeviceScrollRule, for deviceID: String) {
        if rule == .inherit {
            deviceRules.removeValue(forKey: deviceID)
        } else {
            deviceRules[deviceID] = rule.rawValue
        }
    }

    public func shouldReverse(_ kind: ScrollDeviceKind) -> Bool {
        lock.lock()
        let current = snapshot
        lock.unlock()

        guard current.enabled else { return false }
        switch kind {
        case .trackpad:
            return current.reverseTrackpad
        case .mouse(let deviceID):
            guard let deviceID,
                  let rawRule = current.deviceRules[deviceID],
                  let rule = DeviceScrollRule(rawValue: rawRule)
            else { return current.reverseMouse }

            switch rule {
            case .inherit: return current.reverseMouse
            case .reverse: return true
            case .standard: return false
            }
        }
    }

    private func save() {
        let updated = Snapshot(
            enabled: enabled,
            reverseTrackpad: reverseTrackpad,
            reverseMouse: reverseMouse,
            deviceRules: deviceRules
        )

        lock.lock()
        snapshot = updated
        lock.unlock()

        defaults.set(enabled, forKey: Key.enabled)
        defaults.set(reverseTrackpad, forKey: Key.reverseTrackpad)
        defaults.set(reverseMouse, forKey: Key.reverseMouse)
        defaults.set(deviceRules, forKey: Key.deviceRules)
    }
}
