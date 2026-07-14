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
                .frame(width: 340)
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
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var reverser: ScrollReverser
    @ObservedObject private var mouseMonitor: MouseDeviceMonitor
    @ObservedObject private var launchAtLogin: LaunchAtLoginController

    init(model: AppModel) {
        self.model = model
        _settings = ObservedObject(wrappedValue: model.settings)
        _reverser = ObservedObject(wrappedValue: model.reverser)
        _mouseMonitor = ObservedObject(wrappedValue: model.mouseMonitor)
        _launchAtLogin = ObservedObject(wrappedValue: model.launchAtLogin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if reverser.state == .accessibilityPermissionNeeded {
                accessibilityPermissionCard
            }

            if mouseMonitor.accessState != .granted {
                inputMonitoringCard
            }

            if reverser.state == .eventTapFailed {
                eventTapFailureCard
            }

            VStack(spacing: 0) {
                Toggle("Reverse trackpad", isOn: $settings.reverseTrackpad)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                Divider().padding(.leading, 14)
                Toggle("Reverse mouse", isOn: $settings.reverseMouse)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
            }
            .settingsSurface()

            if !mouseMonitor.devices.isEmpty {
                deviceSection
            }

            VStack(spacing: 0) {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
            .settingsSurface()

            HStack {
                status
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 40)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onAppear {
            reverser.refreshPermissionAndState()
            mouseMonitor.refreshAccessState()
            launchAtLogin.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("llorcs")
                    .font(.headline)
                Text("Choose a direction for each input")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: $settings.enabled)
                .labelsHidden()
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var accessibilityPermissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accessibility permission needed", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
            Text("llorcs needs permission to adjust scroll events. After allowing it in System Settings, return here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Permission Prompt") { reverser.requestPermission() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var inputMonitoringCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Input Monitoring for per-mouse rules", systemImage: "computermouse.fill")
                .font(.subheadline.weight(.semibold))
            Text("The main mouse and trackpad settings still work without this. Allow Input Monitoring to identify individual wheel mice.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            Button("Allow Input Monitoring") { requestInputMonitoring() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsSurface()
    }

    private var eventTapFailureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Scroll handler could not start", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            Text("Accessibility is allowed, but macOS did not create the scroll event tap. Retry, or toggle Accessibility off and on in System Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") { reverser.start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONNECTED MICE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(mouseMonitor.devices.enumerated()), id: \.element.id) { index, device in
                    HStack(spacing: 10) {
                        Image(systemName: "computermouse")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(device.name)
                            .lineLimit(1)
                        Spacer()
                        Picker("Direction", selection: ruleBinding(for: device.id)) {
                            ForEach(DeviceScrollRule.allCases) { rule in
                                Text(rule.title).tag(rule)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 150)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)

                    if index < mouseMonitor.devices.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .settingsSurface()

            Text("Per-device rules are best-effort for physical scroll wheels. Gesture mice may be detected as a trackpad.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)

            Label(attributionStatusText, systemImage: attributionStatusIcon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        }
    }

    private var status: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption)
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
        case .permissionNeeded: "Per-device detection needs Input Monitoring"
        case .awaitingWheelInput: "Per-device detection ready; scroll a mouse to verify"
        case .ready: "Per-device wheel detection active"
        }
    }

    private var attributionStatusIcon: String {
        switch mouseMonitor.attributionState {
        case .permissionNeeded: "lock.fill"
        case .awaitingWheelInput: "waveform.path"
        case .ready: "checkmark.circle.fill"
        }
    }

    private func ruleBinding(for deviceID: String) -> Binding<DeviceScrollRule> {
        Binding(
            get: { settings.rule(for: deviceID) },
            set: { settings.setRule($0, for: deviceID) }
        )
    }
}

private extension View {
    func settingsSurface() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.82),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}
