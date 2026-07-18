import AppKit
import Combine
import LlorcsCore
import SwiftUI

@main
struct LlorcsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
                .frame(width: 372)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            Label("llorcs", systemImage: model.settings.enabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

final class AppModel: ObservableObject {
    let settings: SettingsStore
    let mouseMonitor: MouseDeviceMonitor
    let reverser: ScrollReverser
    let launchAtLogin = LaunchAtLoginController()
    private var cancellables = Set<AnyCancellable>()

    init() {
        let settings = SettingsStore()
        let mouseMonitor = MouseDeviceMonitor(enabled: settings.enabled)
        self.settings = settings
        self.mouseMonitor = mouseMonitor
        self.reverser = ScrollReverser(settings: settings, mouseMonitor: mouseMonitor)

        settings.$enabled
            .removeDuplicates()
            .sink { [weak reverser, weak mouseMonitor] enabled in
                DispatchQueue.main.async {
                    mouseMonitor?.setMonitoringEnabled(enabled)
                    if enabled {
                        reverser?.refreshPermissionAndState()
                    } else {
                        reverser?.stop()
                    }
                }
            }
            .store(in: &cancellables)
    }
}

private struct MenuContent: View {
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var reverser: ScrollReverser
    @ObservedObject private var mouseMonitor: MouseDeviceMonitor
    @ObservedObject private var launchAtLogin: LaunchAtLoginController

    init(model: AppModel) {
        _settings = ObservedObject(wrappedValue: model.settings)
        _reverser = ObservedObject(wrappedValue: model.reverser)
        _mouseMonitor = ObservedObject(wrappedValue: model.mouseMonitor)
        _launchAtLogin = ObservedObject(wrappedValue: model.launchAtLogin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            directionSection

            if mouseMonitor.devices.isEmpty {
                emptyDeviceSection
            } else {
                deviceSection
            }

            if reverser.state == .accessibilityPermissionNeeded {
                accessibilityAction
            }

            if reverser.state == .eventTapFailed {
                eventTapFailureAction
            }

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .onAppear {
            reverser.refreshPermissionAndState()
            mouseMonitor.refreshAccessState()
            launchAtLogin.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            AppMark()

            VStack(alignment: .leading, spacing: 3) {
                Text("llorcs")
                    .font(.system(size: 15, weight: .semibold))
                Text("Choose a direction for each input")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Enabled", isOn: $settings.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
    }

    private var directionSection: some View {
        VStack(spacing: 0) {
            SettingsToggleRow(title: "Reverse trackpad", isOn: $settings.reverseTrackpad)
            Divider()
                .padding(.leading, 14)
            SettingsToggleRow(title: "Reverse mouse", isOn: $settings.reverseMouse)
        }
        .settingsSurface()
    }

    private var accessibilityAction: some View {
        CompactActionRow(
            icon: "hand.raised.fill",
            title: "Accessibility required",
            detail: "Needed to adjust scroll events",
            buttonTitle: "Allow",
            isPrimary: true,
            action: reverser.requestPermission
        )
    }

    private var eventTapFailureAction: some View {
        CompactActionRow(
            icon: "exclamationmark.triangle.fill",
            title: "Scroll handler stopped",
            detail: "Could not start the event handler",
            buttonTitle: "Retry",
            isPrimary: true,
            action: reverser.start
        )
    }

    private func requestInputMonitoring() {
        guard !mouseMonitor.requestAccess() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            mouseMonitor.refreshAccessState()
            guard mouseMonitor.accessState != .granted,
                  let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
            else { return }
            NSWorkspace.shared.open(url)
        }
    }

    private var emptyDeviceSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("CONNECTED MOUSE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            HStack(spacing: 10) {
                Image(systemName: mouseMonitor.accessState == .granted ? "computermouse" : "lock.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 19)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mouseMonitor.accessState == .granted ? "No wheel mouse detected" : "Per-mouse rules locked")
                        .font(.system(size: 13))
                    Text(mouseMonitor.accessState == .granted ? "Scroll a mouse to connect it" : "Input Monitoring required")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if mouseMonitor.accessState != .granted {
                    Button("Allow") { requestInputMonitoring() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58)
            .settingsSurface()
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(mouseMonitor.devices.count == 1 ? "CONNECTED MOUSE" : "CONNECTED MICE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(mouseMonitor.devices.enumerated()), id: \.element.id) { index, device in
                    HStack(spacing: 9) {
                        Image(systemName: "computermouse")
                            .foregroundStyle(.secondary)
                            .frame(width: 19)
                        Text(device.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Spacer()
                        Picker("Direction", selection: ruleBinding(for: device.id)) {
                            ForEach(DeviceScrollRule.allCases) { rule in
                                Text(menuTitle(for: rule)).tag(rule)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)

                    if index < mouseMonitor.devices.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .settingsSurface()

            Label(attributionStatusText, systemImage: attributionStatusIcon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                status

                Spacer()

                Button {
                    launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
                } label: {
                    Label(
                        "Launch at login",
                        systemImage: launchAtLogin.isEnabled ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 40)

                Divider()
                    .frame(height: 14)

                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, minHeight: 40)
            }
            .frame(maxWidth: .infinity, minHeight: 40)

            if let error = launchAtLogin.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
            }
        }
    }

    private var status: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                    .frame(width: 13, height: 13)
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch reverser.state {
        case .disabled: "Disabled"
        case .accessibilityPermissionNeeded: "Accessibility needed"
        case .starting: "Starting…"
        case .active: "Active"
        case .eventTapFailed: "Scroll handler failed"
        }
    }

    private var statusColor: Color {
        switch reverser.state {
        case .active: .green
        case .starting: .yellow
        case .disabled: .secondary
        case .accessibilityPermissionNeeded, .eventTapFailed: .orange
        }
    }

    private var attributionStatusText: String {
        switch mouseMonitor.attributionState {
        case .permissionNeeded: "Per-device rules need Input Monitoring"
        case .awaitingWheelInput: "Scroll a mouse to verify per-device detection"
        case .ready:
            if let name = mouseMonitor.lastDetectedDeviceName {
                "Last detected: \(name)"
            } else {
                "Per-device wheel detection active"
            }
        }
    }

    private var attributionStatusIcon: String {
        switch mouseMonitor.attributionState {
        case .permissionNeeded: "lock.fill"
        case .awaitingWheelInput: "waveform.path"
        case .ready: "checkmark.circle.fill"
        }
    }

    private func menuTitle(for rule: DeviceScrollRule) -> String {
        switch rule {
        case .inherit: "Use default"
        case .reverse: "Reverse"
        case .standard: "Standard"
        }
    }

    private func ruleBinding(for deviceID: String) -> Binding<DeviceScrollRule> {
        Binding(
            get: { settings.rule(for: deviceID) },
            set: { settings.setRule($0, for: deviceID) }
        )
    }
}

private struct AppMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 2, y: 1)

            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(width: 44, height: 44)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1),
                    lineWidth: 1
                )
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 13))

            Spacer(minLength: 0)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 52)
    }
}

private struct CompactActionRow: View {
    let icon: String
    let title: String
    let detail: String
    let buttonTitle: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 19)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if isPrimary {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 58)
        .settingsSurface()
    }
}

private extension View {
    func settingsSurface() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.76),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .shadow(color: .black.opacity(0.045), radius: 2, y: 1)
    }
}
