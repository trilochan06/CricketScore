import SwiftUI

struct SettingsView: View {
    let settings: AppSettings
    let viewModel: ScoreViewModel

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            DisplaySettings(settings: settings)
                .tabItem { Label("Display", systemImage: "macwindow") }
            DataSettings(settings: settings, viewModel: viewModel)
                .tabItem { Label("Data", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .frame(width: 480, height: 470)
    }
}

// MARK: General

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    @ViewState private var launchAtLogin = LaunchAtLogin.isEnabled
    @ViewState private var loginError: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show live score overlay", isOn: $settings.showOverlay)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .disabled(!LaunchAtLogin.isAvailable)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if !LaunchAtLogin.isAvailable {
                    Text("Available when running the built CricketScore.app (not `swift run`).")
                        .font(.caption).foregroundStyle(.secondary)
                } else if LaunchAtLogin.needsApproval {
                    HStack {
                        Text("Approve Cricket Score in Login Items.").font(.caption).foregroundStyle(.secondary)
                        Button("Open Login Items…", action: LaunchAtLogin.openLoginItemsSettings).controlSize(.small)
                    }
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                if !settings.showMenuBarIcon {
                    Text("To reopen Settings, launch Cricket Score again from Finder or Spotlight.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Behavior") {
                Toggle("Automatically show when a match starts", isOn: $settings.autoShowOnMatchStart)
                Toggle("Hide when no matches are live", isOn: $settings.hideWhenNoLiveMatches)
                Toggle("Remember selected match", isOn: $settings.rememberSelectedMatch)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != LaunchAtLogin.isEnabled else { return }
        do {
            try LaunchAtLogin.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = "Couldn't update Login Items: \(error.localizedDescription)"
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

// MARK: Display

private struct DisplaySettings: View {
    @Bindable var settings: AppSettings

    private var hasNotch: Bool {
        ScreenGeometry.targetScreen().flatMap(ScreenGeometry.notchRect(on:)) != nil
    }

    var body: some View {
        Form {
            Section {
                Picker("Position", selection: Binding(
                    get: { settings.position },
                    set: { settings.position = $0; settings.customAnchor = nil })) {
                    ForEach(OverlayPosition.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(hasNotch
                     ? "Top Center wraps the widget around the camera notch. Below Notch floats it under the menu bar."
                     : "This display has no notch, so Top Center and Below Notch both float under the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Allow dragging the widget to a custom position", isOn: $settings.allowDragging)
                if settings.allowDragging {
                    HStack {
                        Text(settings.customAnchor == nil ? "Drag the collapsed widget to move it." : "Using a custom position.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset Position") { settings.customAnchor = nil }
                            .disabled(settings.customAnchor == nil)
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Position")
            }
            Section {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                if hasNotch && settings.position == .topCenter && !settings.allowDragging {
                    Text("Around the notch the widget is always dark so it blends with the camera housing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Appearance")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Data

private struct DataSettings: View {
    @Bindable var settings: AppSettings
    let viewModel: ScoreViewModel
    @ViewState private var apiKey = ""
    @ViewState private var hasStoredKey = APIKeyStore.read() != nil
    @ViewState private var keyMessage: String?

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Update frequency", selection: $settings.refreshInterval) {
                    ForEach(AppSettings.refreshOptions, id: \.self) { Text("\($0) seconds").tag($0) }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: settings.refreshInterval) { _, seconds in viewModel.setRefreshInterval(seconds) }
                Text("Scores refresh at this rate only while a match is live. Otherwise the app checks every few minutes, and pauses while offline or asleep.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Source") {
                Picker("Score provider", selection: $settings.dataSource) {
                    ForEach(DataSource.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.dataSource) { _, source in viewModel.setDataSource(source) }

                switch settings.dataSource {
                case .demo:
                    Picker("Simulate", selection: Binding(get: { viewModel.mockScenario },
                                                           set: { viewModel.setMockScenario($0) })) {
                        ForEach(MockScenario.allCases) { Text($0.title).tag($0) }
                    }
                    Text("Demo data works offline with no API key. Use Simulate to preview every state of the widget.")
                        .font(.caption).foregroundStyle(.secondary)
                case .cricketData:
                    apiKeySection
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var apiKeySection: some View {
        if APIKeyStore.isUsingEnvironment {
            Label("Using the \(APIKeyStore.environmentVariable) environment variable.", systemImage: "terminal")
                .font(.caption)
        }
        HStack {
            SecureField("API key", text: $apiKey, prompt: Text(hasStoredKey ? "••••••••  (saved in Keychain)" : "Paste your API key"))
            Button("Save") {
                if APIKeyStore.save(apiKey) {
                    apiKey = ""
                    hasStoredKey = true
                    keyMessage = "Saved to your Keychain."
                    viewModel.refresh()
                } else {
                    keyMessage = "Couldn't save the key."
                }
            }
            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            if hasStoredKey {
                Button("Remove", role: .destructive) {
                    APIKeyStore.delete()
                    hasStoredKey = false
                    keyMessage = "Key removed."
                }
            }
        }
        if let keyMessage {
            Text(keyMessage).font(.caption).foregroundStyle(.secondary)
        }
        HStack(spacing: 4) {
            Text("Get a free key at")
            Link("cricketdata.org", destination: URL(string: "https://cricketdata.org/")!)
            Text("· Free plans allow ~100 requests/day, so 60 seconds is recommended.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
