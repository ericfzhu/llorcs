import AppKit
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

    init() {
        let settings = SettingsStore()
        let mouseMonitor = MouseDeviceMonitor()
        self.settings = settings
        self.mouseMonitor = mouseMonitor
        self.reverser = ScrollReverser(settings: settings, mouseMonitor: mouseMonitor)
        reverser.start()
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
        VStack(spacing: 14) {
            header

            if !reverser.permissionGranted {
                permissionCard
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
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !mouseMonitor.devices.isEmpty {
                deviceSection
            }

            VStack(spacing: 0) {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)

                if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                status
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 40)
            }
        }
        .padding(16)
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
        .frame(minHeight: 44)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Accessibility permission needed", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
            Text("llorcs needs permission to adjust scroll events. After allowing it in System Settings, return here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Permission Prompt") { reverser.requestPermission() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Per-device rules are best-effort for physical scroll wheels. Gesture mice may be detected as a trackpad.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }

    private var status: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(reverser.isRunning ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(reverser.isRunning ? "Active" : "Waiting for permission")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func ruleBinding(for deviceID: String) -> Binding<DeviceScrollRule> {
        Binding(
            get: { settings.rule(for: deviceID) },
            set: { settings.setRule($0, for: deviceID) }
        )
    }
}
