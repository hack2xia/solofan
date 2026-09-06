import SwiftUI

// MARK: - Status bar display options

enum StatusBarDisplayMode: String, CaseIterable {
    case none = "None"
    case temperature = "Temperature"
    case power = "Power Usage"
    case fanSpeedPercentage = "Fan Speed %"

    var description: String { rawValue }
}

// MARK: - Navigation

private enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general = "General"
    case menuBar = "Menu Bar"
    case monitoring = "Monitoring"
    case alerts = "Alerts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .menuBar: return "menubar.rectangle"
        case .monitoring: return "waveform.path.ecg"
        case .alerts: return "bell.badge.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .blue
        case .menuBar: return .cyan
        case .monitoring: return .mint
        case .alerts: return .orange
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Startup and menu bar visibility"
        case .menuBar: return "Status item label"
        case .monitoring: return "Polling and automatic control"
        case .alerts: return "Temperature notifications"
        }
    }
}

// MARK: - Settings shell

private struct LiquidGlassSettingsView: View {
    @ObservedObject var viewModel: FanControlViewModel
    var presentation: SettingsPresentation

    @Environment(\.dismiss) private var dismiss
    @State private var selection: SettingsTab = .general

    @State private var launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    @State private var statusBarDisplayMode = UserDefaults.standard.string(forKey: "statusBarDisplayMode") ?? "temperature"
    @State private var monitoringInterval = UserDefaults.standard.double(forKey: "monitoringInterval") > 0
        ? UserDefaults.standard.double(forKey: "monitoringInterval") : 1.0
    @State private var enableNotifications = UserDefaults.standard.object(forKey: "enableNotifications") as? Bool ?? true
    @State private var highTempAlert = UserDefaults.standard.double(forKey: "highTempAlert") > 0
        ? UserDefaults.standard.double(forKey: "highTempAlert") : 85.0
    @State private var autoSwitchMode = UserDefaults.standard.bool(forKey: "autoSwitchMode")
    @State private var showMenuBarIcon = !MenuBarIconPreferences.isHidden

    private let sidebarWidth: CGFloat = 268

    enum SettingsPresentation {
        case window
        case sheet
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            glassSidebarPanel
            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(presentation == .sheet ? 22 : 28)
        .frame(
            minWidth: presentation == .sheet ? 720 : 920,
            minHeight: presentation == .sheet ? 540 : 600
        )
        .background(settingsChromeBackground)
        .onAppear {
            showMenuBarIcon = !MenuBarIconPreferences.isHidden
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarIconVisibilityChanged)) { notification in
            if let hidden = notification.object as? Bool {
                showMenuBarIcon = !hidden
            }
        }
    }

    /// Flat window chrome — no animated mesh gradient.
    private var settingsChromeBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }

    // MARK: Floating glass sidebar

    private var glassSidebarPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
                .padding(.bottom, 20)

            VStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarTabButton(tab)
                }
            }

            Spacer(minLength: 16)

            if presentation == .sheet {
                Button("Done") { dismiss() }
                    .adaptiveGlassButtonStyle(prominent: true)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .liquidGlass(cornerRadius: 22)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "fan.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.blue.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("SoloFan")
                    .font(.title3.weight(.bold))
                Text("Settings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sidebarTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selection == tab

        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? tab.tint : .secondary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    Text(tab.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tab.tint.opacity(0.18))
                }
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail (content — no glass)

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(selection.rawValue)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text(selection.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 20)

            ScrollView(.vertical, showsIndicators: false) {
                Form {
                    switch selection {
                    case .general:
                        generalForm
                    case .menuBar:
                        menuBarForm
                    case .monitoring:
                        monitoringForm
                    case .alerts:
                        alertsForm
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: Forms

    @ViewBuilder
    private var generalForm: some View {
        Section {
            Toggle(isOn: $showMenuBarIcon) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show menu bar icon")
                    Text(showMenuBarIcon
                        ? "SoloFan stays in the menu bar"
                        : "Hidden — reopen from Applications to access settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: showMenuBarIcon) { visible in
                AppDelegate.shared?.setMenuBarIconVisible(visible)
            }
        } header: {
            Text("Appearance")
        }

        Section {
            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                    Text("Start SoloFan when you sign in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: launchAtLogin) { enabled in
                UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
                viewModel.launchAtLogin = enabled
                LaunchAtLoginManager.shared.isEnabled = enabled
            }
        } header: {
            Text("Startup")
        }
    }

    @ViewBuilder
    private var menuBarForm: some View {
        Section {
            Picker(selection: $statusBarDisplayMode) {
                Label("Icon only", systemImage: "circle.slash").tag("none")
                Label("Temperature", systemImage: "thermometer.medium").tag("temperature")
                Label("Power usage", systemImage: "bolt.fill").tag("power")
                Label("Fan speed %", systemImage: "gauge.with.dots.needle.67percent").tag("fanSpeedPercentage")
            } label: {
                Text("Display")
            }
            .pickerStyle(.inline)
            .onChange(of: statusBarDisplayMode) { tag in
                UserDefaults.standard.set(tag, forKey: "statusBarDisplayMode")
                viewModel.statusBarDisplayMode = tag
                NotificationCenter.default.post(
                    name: NSNotification.Name("StatusBarDisplayModeChanged"),
                    object: tag
                )
            }
        } header: {
            Text("Menu Bar Label")
        } footer: {
            Text("On desktop Macs without a battery, power mode shows fan load or temperature.")
        }
    }

    @ViewBuilder
    private var monitoringForm: some View {
        Section {
            LabeledContent("Interval") {
                Text(String(format: "%.1f s", monitoringInterval))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $monitoringInterval, in: 0.5...5.0, step: 0.5)
                .onChange(of: monitoringInterval) { value in
                    UserDefaults.standard.set(value, forKey: "monitoringInterval")
                }
        } header: {
            Text("Refresh Rate")
        }

        Section {
            Toggle(isOn: $autoSwitchMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-switch mode")
                    Text("Enable automatic fan control when temperature spikes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: autoSwitchMode) { enabled in
                UserDefaults.standard.set(enabled, forKey: "autoSwitchMode")
            }
        } header: {
            Text("Automatic Control")
        }
    }

    @ViewBuilder
    private var alertsForm: some View {
        Section {
            Toggle(isOn: $enableNotifications) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable alerts")
                    Text("System notification when temperatures are high")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: enableNotifications) { enabled in
                UserDefaults.standard.set(enabled, forKey: "enableNotifications")
            }
        } header: {
            Text("Notifications")
        }

        Section {
            LabeledContent("Threshold") {
                Text(String(format: "%.0f °C", highTempAlert))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $highTempAlert, in: 70...95, step: 1)
                .onChange(of: highTempAlert) { value in
                    UserDefaults.standard.set(value, forKey: "highTempAlert")
                }
        } header: {
            Text("Alert Threshold")
        }
    }
}

// MARK: - Public entry points

struct SettingsView: View {
    @ObservedObject var viewModel: FanControlViewModel

    var body: some View {
        LiquidGlassSettingsView(viewModel: viewModel, presentation: .sheet)
    }
}

struct SettingsWindowView: View {
    @Binding var isOpen: Bool
    @ObservedObject var viewModel: FanControlViewModel

    var body: some View {
        LiquidGlassSettingsView(viewModel: viewModel, presentation: .window)
            .onAppear {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
    }
}
