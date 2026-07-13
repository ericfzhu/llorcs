import Foundation
import IOKit.hid

public struct MouseDevice: Identifiable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public final class MouseDeviceMonitor: ObservableObject {
    @Published public private(set) var devices: [MouseDevice] = []

    private let manager: IOHIDManager
    private let queue = DispatchQueue(label: "app.llorcs.hid")
    private let lock = NSLock()
    private var lastWheelDeviceID: String?
    private var lastWheelTime: UInt64 = 0

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let mouseMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
        ]
        IOHIDManagerSetDeviceMatching(manager, mouseMatch as CFDictionary)

        let wheelInputs: [[String: Any]] = [
            [
                kIOHIDElementUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDElementUsageKey: kHIDUsage_GD_Wheel
            ],
            [
                kIOHIDElementUsagePageKey: kHIDPage_Consumer,
                kIOHIDElementUsageKey: kHIDUsage_Csmr_ACPan
            ]
        ]
        IOHIDManagerSetInputValueMatchingMultiple(manager, wheelInputs as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, context)
        IOHIDManagerRegisterInputValueCallback(manager, inputValueCallback, context)
        IOHIDManagerSetDispatchQueue(manager, queue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        refreshDevices()
    }

    deinit {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public func recentWheelDeviceID(maxAgeNanoseconds: UInt64 = 80_000_000) -> String? {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        defer { lock.unlock() }
        guard lastWheelTime > 0, now >= lastWheelTime, now - lastWheelTime <= maxAgeNanoseconds else {
            return nil
        }
        return lastWheelDeviceID
    }

    fileprivate func recordWheel(from device: IOHIDDevice) {
        let id = Self.deviceID(device)
        lock.lock()
        lastWheelDeviceID = id
        lastWheelTime = DispatchTime.now().uptimeNanoseconds
        lock.unlock()
    }

    fileprivate func refreshDevices() {
        let connected = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? [])
            .map { MouseDevice(id: Self.deviceID($0), name: Self.deviceName($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        DispatchQueue.main.async { [weak self] in
            self?.devices = connected
        }
    }

    private static func property(_ key: String, from device: IOHIDDevice) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    private static func deviceName(_ device: IOHIDDevice) -> String {
        (property(kIOHIDProductKey, from: device) as? String) ?? "Mouse"
    }

    private static func deviceID(_ device: IOHIDDevice) -> String {
        let vendor = property(kIOHIDVendorIDKey, from: device) as? Int ?? 0
        let product = property(kIOHIDProductIDKey, from: device) as? Int ?? 0
        let location = property(kIOHIDLocationIDKey, from: device) as? Int ?? 0
        let serial = property(kIOHIDSerialNumberKey, from: device) as? String ?? ""
        return "\(vendor):\(product):\(location):\(serial)"
    }
}

private func monitor(from context: UnsafeMutableRawPointer?) -> MouseDeviceMonitor? {
    guard let context else { return nil }
    return Unmanaged<MouseDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
}

private let deviceMatchedCallback: IOHIDDeviceCallback = { context, _, _, _ in
    monitor(from: context)?.refreshDevices()
}

private let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, _ in
    monitor(from: context)?.refreshDevices()
}

private let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)

    let isVerticalWheel = usagePage == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Wheel
    let isHorizontalWheel = usagePage == kHIDPage_Consumer && usage == kHIDUsage_Csmr_ACPan
    guard isVerticalWheel || isHorizontalWheel else { return }

    let device = IOHIDElementGetDevice(element)
    monitor(from: context)?.recordWheel(from: device)
}
