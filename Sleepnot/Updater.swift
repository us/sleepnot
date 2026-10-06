import AppKit
import Foundation

/// Minimal self-updater with zero dependencies and no update server.
/// Reads github.com/us/sleepnot/releases/latest, compares the tag
/// against the running version, and can install the new zip in place.
final class Updater {
    enum State {
        case idle
        case checking
        case upToDate
        case available(version: String, page: URL)
        case failed(String)
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var onChange: (() -> Void)?

    private(set) var state: State = .idle {
        didSet { DispatchQueue.main.async { [weak self] in self?.onChange?() } }
    }

    private var zipURL: URL?
    private var pending: (version: String, page: URL)?
    private var installing = false

    /// Ask GitHub for the latest release. Shows an alert only when
    /// `notify` is true or when an update (or error) needs attention.
    func check(notify: Bool = false) {
        switch state {
        case .idle, .upToDate, .failed: break
        default: return
        }
        guard !installing else { return }
        state = .checking
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/us/sleepnot/releases/latest")!,
            timeoutInterval: 15
        )
        request.setValue("SLEEPNOT", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            do {
                guard
                    let data,
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let tag = json["tag_name"] as? String,
                    let pageString = json["html_url"] as? String,
                    let page = URL(string: pageString)
                else { throw UpdaterError.badResponse }
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = json["assets"] as? [[String: Any]] ?? []
                self.zipURL = assets
                    .compactMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
                    .first(where: { $0.lastPathComponent.hasSuffix(".zip") })
                if Self.isNewer(version, than: Self.currentVersion) {
                    self.pending = (version, page)
                    self.state = .available(version: version, page: page)
                    if notify { self.offerInstall(version: version) }
                } else {
                    self.state = .upToDate
                    if notify { self.alert("You're up to date.", "SLEEPNOT \(Self.currentVersion) is the latest version.") }
                }
            } catch {
                self.state = .failed("Check failed.")
                if notify { self.alert("Update check failed.", "Could not reach GitHub. Try again later.") }
            }
        }.resume()
    }

    /// Download the new zip and swap it in, then relaunch.
    /// Only runs when the app lives in /Applications; otherwise the
    /// release page is opened so the user can install by hand.
    func installAvailable() {
        guard
            case let .available(version, page) = state,
            !installing,
            let zipURL
        else { return }
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.path.hasPrefix("/Applications/") else {
            NSWorkspace.shared.open(page)
            return
        }
        installing = true
        state = .checking
        URLSession.shared.downloadTask(with: zipURL) { [weak self] location, _, _ in
            guard let self, let location else {
                self?.finishInstall(error: "Download failed.")
                return
            }
            do {
                try self.swap(bundleURL: bundleURL, zip: location, version: version)
            } catch {
                self.finishInstall(error: (error as? LocalizedError)?.errorDescription ?? "Install failed.")
            }
        }.resume()
    }

    // MARK: - Private

    private func swap(bundleURL: URL, zip: URL, version: String) throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        guard let fresh = try FileManager.default
            .contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else { throw UpdaterError.badArchive }
        try run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", fresh.path])
        let backup = bundleURL.deletingLastPathComponent()
            .appendingPathComponent(bundleURL.deletingPathExtension().lastPathComponent + ".old")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.moveItem(at: bundleURL, to: backup)
        do {
            try FileManager.default.moveItem(at: fresh, to: bundleURL)
            try? FileManager.default.removeItem(at: backup)
        } catch {
            try? FileManager.default.moveItem(at: backup, to: bundleURL)
            throw error
        }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(bundleURL)
            NSApplication.shared.terminate(nil)
        }
    }

    private func finishInstall(error: String) {
        installing = false
        if let pending {
            state = .available(version: pending.version, page: pending.page)
            alert("Update failed.", "\(error) You can still download it by hand.")
            NSWorkspace.shared.open(pending.page)
        } else {
            state = .failed(error)
            alert("Update failed.", error)
        }
    }

    private func offerInstall(version: String) {
        let answer = alert(
            "SLEEPNOT \(version) is available.",
            "You're on \(Self.currentVersion). Install it now?",
            buttons: ["Install & Relaunch", "Later"]
        )
        if answer == .alertFirstButtonReturn { installAvailable() }
    }

    @discardableResult
    private func alert(_ title: String, _ body: String, buttons: [String] = ["OK"]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        for button in buttons { alert.addButton(withTitle: button) }
        return alert.runModal()
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) throws -> Int32 {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw UpdaterError.toolFailed(launchPath) }
        return task.terminationStatus
    }

    /// Numeric dot-separated comparison ("1.10" beats "1.9").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(left.count, right.count) {
            let l = i < left.count ? left[i] : 0
            let r = i < right.count ? right[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

private enum UpdaterError: LocalizedError {
    case badResponse
    case badArchive
    case toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Unexpected response from GitHub."
        case .badArchive: return "Downloaded archive has no app inside."
        case .toolFailed(let tool): return "\(tool) failed."
        }
    }
}
