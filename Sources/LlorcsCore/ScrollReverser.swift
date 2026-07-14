import ApplicationServices
import CoreGraphics
import Foundation

public enum ScrollReverserState: Equatable {
    case disabled
    case accessibilityPermissionNeeded
    case starting
    case active
    case eventTapFailed
}

public final class ScrollReverser: ObservableObject {
    @Published public private(set) var state: ScrollReverserState = .disabled
    @Published public private(set) var permissionGranted = AXIsProcessTrusted()

    public var isRunning: Bool { state == .active }

    private let settings: SettingsStore
    private let mouseMonitor: MouseDeviceMonitor
    private let lifecycleLock = NSLock()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var desiredRunning = false
    private var generation: UInt = 0

    private var permissionTimer: Timer?
    private var permissionPollCount = 0
    private let maximumPermissionPolls = 30

    public init(settings: SettingsStore, mouseMonitor: MouseDeviceMonitor) {
        self.settings = settings
        self.mouseMonitor = mouseMonitor
    }

    deinit {
        stopPublishingState(false)
        permissionTimer?.invalidate()
    }

    public func start() {
        guard settings.isEnabledForEventTap() else {
            publishState(.disabled)
            return
        }

        let trusted = AXIsProcessTrusted()
        publishPermission(trusted)
        guard trusted else {
            publishState(.accessibilityPermissionNeeded)
            return
        }

        lifecycleLock.lock()
        guard !desiredRunning else {
            lifecycleLock.unlock()
            return
        }
        desiredRunning = true
        generation &+= 1
        let token = generation
        lifecycleLock.unlock()

        publishState(.starting)

        let thread = Thread { [weak self] in
            self?.runEventTap(generation: token)
        }
        thread.name = "app.llorcs.scroll-event-tap"
        thread.qualityOfService = .userInitiated

        lifecycleLock.lock()
        tapThread = thread
        lifecycleLock.unlock()
        thread.start()
    }

    public func stop() {
        stopPublishingState(true)
    }

    public func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        publishState(.accessibilityPermissionNeeded)
        beginPermissionPolling()
    }

    public func refreshPermissionAndState() {
        let trusted = AXIsProcessTrusted()
        publishPermission(trusted)

        guard settings.isEnabledForEventTap() else {
            stop()
            return
        }

        if trusted {
            start()
        } else {
            stopPublishingState(false)
            publishState(.accessibilityPermissionNeeded)
        }
    }

    private func runEventTap(generation token: UInt) {
        autoreleasepool {
            let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .tailAppendEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: scrollEventCallback,
                userInfo: pointer
            ) else {
                failEventTapIfCurrent(generation: token)
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let runLoop = CFRunLoopGetCurrent()

            lifecycleLock.lock()
            guard desiredRunning && generation == token else {
                lifecycleLock.unlock()
                return
            }
            eventTap = tap
            runLoopSource = source
            tapRunLoop = runLoop
            lifecycleLock.unlock()

            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            publishState(.active, generation: token)
            CFRunLoopRun()
            CFRunLoopRemoveSource(runLoop, source, .commonModes)

            lifecycleLock.lock()
            let stoppedUnexpectedly = desiredRunning && generation == token
            if generation == token {
                eventTap = nil
                runLoopSource = nil
                tapRunLoop = nil
                tapThread = nil
                if stoppedUnexpectedly { desiredRunning = false }
            }
            lifecycleLock.unlock()

            if stoppedUnexpectedly {
                publishState(.eventTapFailed)
            }
        }
    }

    private func stopPublishingState(_ shouldPublish: Bool) {
        permissionTimer?.invalidate()
        permissionTimer = nil
        permissionPollCount = 0

        lifecycleLock.lock()
        desiredRunning = false
        generation &+= 1
        let tap = eventTap
        let runLoop = tapRunLoop
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
        lifecycleLock.unlock()

        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
        if shouldPublish { publishState(.disabled) }
    }

    private func beginPermissionPolling() {
        permissionTimer?.invalidate()
        permissionPollCount = 0
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            self.permissionPollCount += 1
            let trusted = AXIsProcessTrusted()
            self.publishPermission(trusted)

            if trusted {
                timer.invalidate()
                self.permissionTimer = nil
                self.permissionPollCount = 0
                self.start()
            } else if self.permissionPollCount >= self.maximumPermissionPolls {
                timer.invalidate()
                self.permissionTimer = nil
                self.permissionPollCount = 0
                self.publishState(.accessibilityPermissionNeeded)
            }
        }
    }

    private func failEventTapIfCurrent(generation token: UInt) {
        lifecycleLock.lock()
        let isCurrent = desiredRunning && generation == token
        if isCurrent {
            desiredRunning = false
            tapThread = nil
        }
        lifecycleLock.unlock()
        if isCurrent {
            let trusted = AXIsProcessTrusted()
            publishPermission(trusted)
            publishState(trusted ? .eventTapFailed : .accessibilityPermissionNeeded)
        }
    }

    private func reenableEventTap() {
        lifecycleLock.lock()
        let tap = desiredRunning ? eventTap : nil
        lifecycleLock.unlock()
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func isCurrent(generation token: UInt) -> Bool {
        lifecycleLock.lock()
        let current = desiredRunning && generation == token
        lifecycleLock.unlock()
        return current
    }

    private func publishState(_ newState: ScrollReverserState, generation token: UInt? = nil) {
        let update = { [weak self] in
            guard let self else { return }
            if let token, !self.isCurrent(generation: token) { return }
            self.state = newState
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    private func publishPermission(_ granted: Bool) {
        let update: () -> Void = { [weak self] in
            self?.permissionGranted = granted
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if !AXIsProcessTrusted() {
                publishPermission(false)
                DispatchQueue.main.async { [weak self] in self?.refreshPermissionAndState() }
                return Unmanaged.passUnretained(event)
            }
            reenableEventTap()
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel, settings.isEnabledForEventTap() else {
            return Unmanaged.passUnretained(event)
        }

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

    static func reverseDeltas(in event: CGEvent) {
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

        // Snapshot all representations before modifying any field. Setting a
        // DeltaAxis field makes macOS recalculate the fixed-point and point
        // deltas, so reading those values afterward would reverse them twice.
        let deltaValues = deltaFields.map { event.getIntegerValueField($0) }
        let fixedPointValues = fixedPointFields.map { event.getDoubleValueField($0) }
        let pointValues = pointFields.map { event.getIntegerValueField($0) }

        for (field, value) in zip(deltaFields, deltaValues) {
            event.setIntegerValueField(field, value: -value)
        }
        for (field, value) in zip(fixedPointFields, fixedPointValues) {
            event.setDoubleValueField(field, value: -value)
        }
        // Point deltas must be written last; applications commonly consume
        // these pixel values, and DeltaAxis writes update them implicitly.
        for (field, value) in zip(pointFields, pointValues) {
            event.setIntegerValueField(field, value: -value)
        }
    }
}

private let scrollEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let reverser = Unmanaged<ScrollReverser>.fromOpaque(userInfo).takeUnretainedValue()
    return reverser.handle(type: type, event: event)
}
