import CoreGraphics
import Foundation
import IOKit.hid

public enum HIDAccessState: Equatable {
    case granted
    case denied
    case unknown
}

public enum MouseAttributionState: Equatable {
    case permissionNeeded
    case awaitingWheelInput
    case ready
}

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
    @Published public private(set) var accessState: HIDAccessState = .unknown
    @Published public private(set) var hasObservedWheelInput = false
    @Published public private(set) var lastDetectedDeviceName: String?

    private let manager: IOHIDManager
    private let queue = DispatchQueue(label: "app.llorcs.hid")
    private let lock = NSLock()
    private var monitoringEnabled: Bool
    private var managerIsOpen = false
    private var deviceCache: [UInt: MouseDevice] = [:]
    private var observedWheelInput = false
    private var lastDetectedDeviceID: String?
    private var recentWheelReports: [(deviceID: String, time: UInt64)] = []

    public init(enabled: Bool = true) {
        monitoringEnabled = enabled
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
        // Dispatch-queue based HID managers are created inactive. Without this,
        // device and input callbacks are not guaranteed to be delivered.
        IOHIDManagerActivate(manager)
        refreshAccessState()
    }

    deinit {
        lock.lock()
        let shouldClose = managerIsOpen
        managerIsOpen = false
        lock.unlock()
        if shouldClose { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        IOHIDManagerCancel(manager)
    }

    public func recentWheelDeviceID(maxAgeNanoseconds: UInt64 = 150_000_000) -> String? {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        defer { lock.unlock() }
        // The newest HID report identifies the active mouse. Older reports
        // from another mouse must not force a fallback to the global rule.
        return MouseWheelCorrelation.deviceID(
            in: recentWheelReports,
            now: now,
            maxAgeNanoseconds: maxAgeNanoseconds
        )
    }

    public var attributionState: MouseAttributionState {
        switch accessState {
        case .granted:
            return hasObservedWheelInput ? .ready : .awaitingWheelInput
        case .denied, .unknown:
            return .permissionNeeded
        }
    }

    @discardableResult
    public func requestAccess() -> Bool {
        let coreGraphicsGranted = CGRequestListenEventAccess()
        let hidGranted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshAccessState()
        return coreGraphicsGranted || hidGranted || Self.hasListenAccess()
    }

    public func setMonitoringEnabled(_ enabled: Bool) {
        lock.lock()
        monitoringEnabled = enabled
        lock.unlock()
        refreshAccessState()
    }

    public func refreshAccessState() {
        let state: HIDAccessState
        switch (Self.hasListenAccess(), IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)) {
        case (true, _):
            state = .granted
        case (false, kIOHIDAccessTypeDenied):
            state = .denied
        default:
            state = .unknown
        }

        if Thread.isMainThread {
            accessState = state
        } else {
            DispatchQueue.main.async { [weak self] in self?.accessState = state }
        }
        updateManager(for: state)
    }

    private static func hasListenAccess() -> Bool {
        CGPreflightListenEventAccess()
            || IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private func updateManager(for state: HIDAccessState) {
        queue.async { [weak self] in
            guard let self else { return }

            self.lock.lock()
            let isOpen = self.managerIsOpen
            let shouldMonitor = self.monitoringEnabled
            self.lock.unlock()

            if state == .granted && shouldMonitor && !isOpen {
                let result = IOHIDManagerOpen(self.manager, IOOptionBits(kIOHIDOptionsTypeNone))
                self.lock.lock()
                self.managerIsOpen = result == kIOReturnSuccess
                self.lock.unlock()
                if result == kIOReturnSuccess { self.refreshDevices() }
            } else if (state != .granted || !shouldMonitor) && isOpen {
                IOHIDManagerClose(self.manager, IOOptionBits(kIOHIDOptionsTypeNone))
                self.lock.lock()
                self.managerIsOpen = false
                self.deviceCache.removeAll()
                self.recentWheelReports.removeAll()
                self.observedWheelInput = false
                self.lastDetectedDeviceID = nil
                self.lock.unlock()
                DispatchQueue.main.async { [weak self] in
                    self?.devices = []
                    self?.hasObservedWheelInput = false
                    self?.lastDetectedDeviceName = nil
                }
            }
        }
    }

    fileprivate func recordWheel(from device: IOHIDDevice) {
        let key = Self.deviceKey(device)
        lock.lock()
        let cachedDevice = deviceCache[key]
        lock.unlock()

        let mouse = cachedDevice ?? Self.makeDevice(device)

        lock.lock()
        deviceCache[key] = mouse
        let now = DispatchTime.now().uptimeNanoseconds
        recentWheelReports.append((mouse.id, now))
        recentWheelReports.removeAll { now >= $0.time && now - $0.time > 200_000_000 }
        if recentWheelReports.count > 16 {
            recentWheelReports.removeFirst(recentWheelReports.count - 16)
        }
        let isFirstWheelInput = !observedWheelInput
        let didChangeDevice = lastDetectedDeviceID != mouse.id
        observedWheelInput = true
        lastDetectedDeviceID = mouse.id
        lock.unlock()

        if isFirstWheelInput || didChangeDevice {
            DispatchQueue.main.async { [weak self] in
                self?.lastDetectedDeviceName = mouse.name
                if isFirstWheelInput { self?.hasObservedWheelInput = true }
            }
        }
    }

    fileprivate func deviceAdded(_ device: IOHIDDevice) {
        let mouse = Self.makeDevice(device)
        lock.lock()
        deviceCache[Self.deviceKey(device)] = mouse
        lock.unlock()
        refreshDevices()
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        lock.lock()
        let removed = deviceCache.removeValue(forKey: Self.deviceKey(device))
        if let removed {
            recentWheelReports.removeAll { $0.deviceID == removed.id }
        }
        lock.unlock()
        refreshDevices()
    }

    fileprivate func refreshDevices() {
        let hidDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        let pairs = hidDevices.map { (Self.deviceKey($0), Self.makeDevice($0)) }

        lock.lock()
        deviceCache = Dictionary(uniqueKeysWithValues: pairs)
        lock.unlock()

        let connected = Dictionary(pairs.map { ($0.1.id, $0.1) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        DispatchQueue.main.async { [weak self] in
            self?.devices = connected
        }
    }

    private static func property(_ key: String, from device: IOHIDDevice) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    private static func makeDevice(_ device: IOHIDDevice) -> MouseDevice {
        MouseDevice(
            id: deviceID(device),
            name: (property(kIOHIDProductKey, from: device) as? String) ?? "Mouse"
        )
    }

    private static func deviceKey(_ device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private static func deviceID(_ device: IOHIDDevice) -> String {
        let vendor = property(kIOHIDVendorIDKey, from: device) as? Int ?? 0
        let product = property(kIOHIDProductIDKey, from: device) as? Int ?? 0
        let location = property(kIOHIDLocationIDKey, from: device) as? Int ?? 0
        let serial = property(kIOHIDSerialNumberKey, from: device) as? String
        let physicalID = property(kIOHIDPhysicalDeviceUniqueIDKey, from: device) as? String
        let transport = property(kIOHIDTransportKey, from: device) as? String ?? "unknown"
        return makeStableDeviceID(
            vendor: vendor,
            product: product,
            serial: serial,
            physicalID: physicalID,
            transport: transport,
            location: location
        )
    }

    static func makeStableDeviceID(
        vendor: Int,
        product: Int,
        serial: String?,
        physicalID: String? = nil,
        transport: String,
        location: Int
    ) -> String {
        let cleanedSerial = serial?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanedSerial.isEmpty {
            return "\(vendor):\(product):serial:\(cleanedSerial)"
        }
        let cleanedPhysicalID = physicalID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanedPhysicalID.isEmpty {
            return "\(vendor):\(product):physical:\(cleanedPhysicalID)"
        }
        return "\(vendor):\(product):\(transport):location:\(location)"
    }
}

private func monitor(from context: UnsafeMutableRawPointer?) -> MouseDeviceMonitor? {
    guard let context else { return nil }
    return Unmanaged<MouseDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
}

private let deviceMatchedCallback: IOHIDDeviceCallback = { context, _, _, device in
    monitor(from: context)?.deviceAdded(device)
}

private let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
    monitor(from: context)?.deviceRemoved(device)
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
