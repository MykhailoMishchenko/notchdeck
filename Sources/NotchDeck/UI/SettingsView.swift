import AppKit
import ServiceManagement
import SwiftUI

// inputs {registry}, does {settings UI: per-widget enable toggles, launch-at-login via SMAppService, quit}, returns {View}
struct SettingsView: View {
    @ObservedObject var registry: WidgetRegistry
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?
    @State private var claudeConnected = ClaudeAuth.isConnected
    @State private var claudeError: String?
    @State private var crabEnabled = UserDefaults.standard.object(forKey: ClaudeUsageWidget.crabEnabledKey) == nil
        ? true
        : UserDefaults.standard.bool(forKey: ClaudeUsageWidget.crabEnabledKey)
    @State private var fanError: String?
    @State private var fanStatusTick = 0

    private var fanDaemonLabel: String {
        switch FanControlClient.shared.daemonStatus {
        case .enabled: return "Helper enabled — sliders active in the Fans widget"
        case .requiresApproval: return "Waiting for approval in System Settings → Login Items"
        case .notFound: return "Helper not found in the app bundle"
        default: return "Privileged helper for fan speed control"
        }
    }

    var body: some View {
        Form {
            Section("Widgets") {
                ForEach(registry.widgets, id: \.id) { widget in
                    Toggle(widget.displayName, isOn: Binding(
                        get: { !registry.disabledIds.contains(widget.id) },
                        set: { registry.setEnabled(widget.id, $0) }
                    ))
                }
            }
            Section("Claude") {
                if claudeConnected {
                    HStack {
                        Text("Connected")
                            .foregroundStyle(.secondary)
                        if let plan = ClaudeAuth.plan {
                            Text(plan)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.orange.opacity(0.2)))
                        }
                        Spacer()
                        Button("Disconnect") {
                            ClaudeAuth.disconnect()
                            claudeConnected = false
                        }
                    }
                } else {
                    HStack {
                        Text("Show your plan limits in the notch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Connect") {
                            switch ClaudeAuth.connect() {
                            case .success:
                                claudeConnected = true
                                claudeError = nil
                            case .failure(let error):
                                claudeError = error.message
                            }
                        }
                    }
                    if let claudeError {
                        Text(claudeError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            Section("Fan control") {
                HStack {
                    Text(fanDaemonLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    switch FanControlClient.shared.daemonStatus {
                    case .enabled:
                        Button("Disable") {
                            fanError = FanControlClient.shared.unregisterDaemon()
                            fanStatusTick += 1
                        }
                    case .requiresApproval:
                        Button("Open System Settings") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    default:
                        Button("Enable") {
                            fanError = FanControlClient.shared.registerDaemon()
                            fanStatusTick += 1
                            if FanControlClient.shared.daemonStatus == .requiresApproval {
                                SMAppService.openSystemSettingsLoginItems()
                            }
                        }
                    }
                }
                .id(fanStatusTick)
                if let fanError {
                    Text(fanError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("General") {
                Toggle("Crab easter egg", isOn: $crabEnabled)
                    .onChange(of: crabEnabled) { enabled in
                        UserDefaults.standard.set(enabled, forKey: ClaudeUsageWidget.crabEnabledKey)
                    }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                HStack {
                    Text("NotchDeck \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                    Button("Quit NotchDeck") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// inputs {}, does {owns the single Settings window; shows/fronts it on demand (accessory app has no Dock entry)}, returns {controller singleton}
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    // inputs {registry}, does {creates the window lazily and brings it to front}, returns {}
    func show(registry: WidgetRegistry) {
        if window == nil {
            let panel = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.title = "NotchDeck Settings"
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: SettingsView(registry: registry))
            panel.center()
            window = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
