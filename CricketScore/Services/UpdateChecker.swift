import AppKit
import Foundation
import Observation

/// Lightweight update check: reads `{server}/version.json` (published by Scripts/release.sh)
/// once at launch and then daily, and offers a download link when a newer version exists.
@MainActor
@Observable
final class UpdateChecker {
    struct Release: Decodable, Equatable {
        let version: String
        let url: String
        let notes: String?
    }

    private(set) var available: Release?
    private(set) var lastChecked: Date?
    private(set) var isChecking = false
    private(set) var lastError: String?

    @ObservationIgnored private var serverURL: () -> URL
    @ObservationIgnored private var timer: Timer?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    init(serverURL: @escaping () -> URL) {
        self.serverURL = serverURL
    }

    func start() {
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
        timer?.tolerance = 3600
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false; lastChecked = Date() }
        let url = serverURL().appendingPathComponent("version.json")
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { lastError = nil; available = nil; return }
            let release = try JSONDecoder().decode(Release.self, from: data)
            lastError = nil
            available = Self.isNewer(release.version, than: Self.currentVersion) ? release : nil
        } catch {
            lastError = "Couldn't check for updates"
        }
    }

    func openDownload() {
        guard let release = available,
              let url = URL(string: release.url, relativeTo: serverURL())?.absoluteURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Numeric dotted comparison: "1.10" > "1.9".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
