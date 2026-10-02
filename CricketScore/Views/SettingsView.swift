import SwiftUI

struct SettingsView: View {
    let settings: AppSettings
    let viewModel: ScoreViewModel

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            TeamsSettings(settings: settings, viewModel: viewModel)
                .tabItem { Label("Teams & Alerts", systemImage: "star") }
            DisplaySettings(settings: settings)
                .tabItem { Label("Display", systemImage: "macwindow") }
            DataSettings(settings: settings, viewModel: viewModel)
                .tabItem { Label("Data", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .frame(width: 500, height: 520)
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
            Section {
                Toggle("Hide when a full-screen app is in front", isOn: $settings.hideInFullScreen)
                Toggle("Hide during video calls (while a camera is on)", isOn: $settings.hideDuringCalls)
                Toggle("Hide from screen sharing and recordings", isOn: $settings.hideFromScreenSharing)
                Text("The widget comes back on its own as soon as you leave full screen or end the call.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Focus")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Teams & Alerts

private struct TeamsSettings: View {
    @Bindable var settings: AppSettings
    let viewModel: ScoreViewModel
    @ViewState private var customTeam = ""

    /// Suggestions: well-known teams plus everything currently in the match list.
    private var suggestions: [String] {
        let current = viewModel.matches.flatMap { $0.teams.map(\.name) }
        let all = AppSettings.suggestedTeams + current.filter { !AppSettings.suggestedTeams.contains($0) }.sorted()
        return all.filter { name in !settings.favoriteTeams.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
    }

    var body: some View {
        Form {
            Section {
                if settings.favoriteTeams.isEmpty {
                    Text("No favorite teams yet. Add one and the widget will follow their matches automatically.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(settings.favoriteTeams, id: \.self) { team in
                    HStack {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(team)
                        Spacer()
                        Button(role: .destructive) { remove(team) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                            .help("Remove \(team)")
                    }
                }
                HStack {
                    Menu("Add Team") {
                        ForEach(suggestions, id: \.self) { name in
                            Button(name) { add(name) }
                        }
                    }
                    .fixedSize()
                    TextField("or type a team name", text: $customTeam)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { add(customTeam) }
                    Button("Add") { add(customTeam) }
                        .disabled(customTeam.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Toggle("Include women's, A and Under-19 teams (e.g. India → India Women)", isOn: $settings.includeTeamVariants)
                    .onChange(of: settings.includeTeamVariants) { _, _ in viewModel.favoritesChanged() }
                Toggle("Only show my teams' matches", isOn: $settings.onlyFavorites)
                    .disabled(settings.favoriteTeams.isEmpty)
                    .onChange(of: settings.onlyFavorites) { _, _ in viewModel.favoritesChanged() }
            } header: {
                Text("Favorite teams")
            } footer: {
                Text("When a favorite team starts playing, the widget switches to that match and appears on its own.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Notch alerts", isOn: $settings.alertsEnabled)
                Group {
                    Toggle("Wickets in my other teams' matches", isOn: $settings.alertWickets)
                    Toggle("Batter milestones (50, 100…)", isOn: $settings.alertMilestones)
                    Toggle("Match start, last over and result", isOn: $settings.alertMatchEvents)
                    Toggle("Show alerts even when the widget is paused or hidden", isOn: $settings.alertsWhilePaused)
                }
                .disabled(!settings.alertsEnabled)
                .padding(.leading, 12)
            } header: {
                Text("Alerts")
            } footer: {
                Text("Alerts flash briefly in the notch and never while you're in full screen or on a call.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func add(_ name: String) {
        let team = name.trimmingCharacters(in: .whitespaces)
        guard !team.isEmpty, !settings.favoriteTeams.contains(where: { $0.caseInsensitiveCompare(team) == .orderedSame }) else { return }
        settings.favoriteTeams.append(team)
        customTeam = ""
        viewModel.favoritesChanged()
    }

    private func remove(_ team: String) {
        settings.favoriteTeams.removeAll { $0 == team }
        if settings.favoriteTeams.isEmpty { settings.onlyFavorites = false }
        viewModel.favoritesChanged()
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
                case .espn:
                    Text("Real ball-by-ball scores, read directly by this Mac — no account, no API key.")
                        .font(.caption).foregroundStyle(.secondary)
                case .liveServer:
                    HStack {
                        TextField("Server URL", text: $settings.serverURL, prompt: Text(AppSettings.defaultServerURL.absoluteString))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { viewModel.setDataSource(.liveServer) }
                        Button("Connect") { viewModel.setDataSource(.liveServer) }
                    }
                    Text("Real ball-by-ball scores from your Cricket Live server — no API key needed.")
                        .font(.caption).foregroundStyle(.secondary)
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
