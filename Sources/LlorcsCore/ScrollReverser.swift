import ApplicationServices
import CoreGraphics
import Foundation

public final class ScrollReverser: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var permissionGranted = AXIsProcessTrusted()

    private let settings: SettingsStore
    private let mouseMonitor: MouseDeviceMonitor
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?

    public init(settings: SettingsStore, mouseMonitor: MouseDeviceMonitor) {
        self.settings = settings
        self.mouseMonitor = mouseMonitor
    }

    public func start() {
        permissionGranted = AXIsProcessTrusted()
        guard permissionGranted else {
            beginPermissionPolling()
            return
        }
        guard eventTap == nil else { return }

        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollEventCallback,
            userInfo: pointer
        )

        guard let eventTap else {
            isRunning = false
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
    }

    public func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
        eventTap = nil
        isRunning = false
    }

    public func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        beginPermissionPolling()
    }

    public func refreshPermission() {
        permissionGranted = AXIsProcessTrusted()
    }

    private func beginPermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            self.permissionGranted = AXIsProcessTrusted()
            if self.permissionGranted {
                timer.invalidate()
                self.permissionTimer = nil
                self.start()
            }
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

        let signals = ScrollEventSignals(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            recentMouseDeviceID: mouseMonitor.recentWheelDeviceID()
        )
        let kind = ScrollClassifier.classify(signals)
        guard settings.shouldReverse(kind) else { return Unmanaged.passUnretained(event) }

        Self.reverseDeltas(in: event)
        return Unmanaged.passUnretained(event)
    }

    private static func reverseDeltas(in event: CGEvent) {
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

        for field in integerFields {
            event.setIntegerValueField(field, value: -event.getIntegerValueField(field))
        }
        for field in doubleFields {
            event.setDoubleValueField(field, value: -event.getDoubleValueField(field))
        }
    }
}

private let scrollEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let reverser = Unmanaged<ScrollReverser>.fromOpaque(userInfo).takeUnretainedValue()
    return reverser.handle(type: type, event: event)
}
