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
            // AppKit is main-thread only: never touch state or alerts here.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.handleCheck(data: data, notify: notify)
            }
        }.resume()
    }

    /// Runs on the main thread. Parses the release JSON and updates state.
    private func handleCheck(data: Data?, notify: Bool) {
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
            let urls = assets
                .compactMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
            // Prefer the exact release artifact; never install a surprise file,
            // and never download from outside GitHub.
            let expected = "SLEEPNOT-\(version).zip"
            guard let url = urls.first(where: { $0.lastPathComponent == expected })
                ?? urls.first(where: { $0.lastPathComponent.hasSuffix(".zip") }),
                url.host?.hasSuffix("github.com") == true
            else {
                pending = nil
                zipURL = nil
                state = .failed("No download found.")
                if notify { alert("Update check failed.", "The release has no usable download.") }
                return
            }
            zipURL = url
            if Self.isNewer(version, than: Self.currentVersion) {
                pending = (version, page)
                state = .available(version: version, page: page)
                if notify { offerInstall(version: version) }
            } else {
                pending = nil
                state = .upToDate
                if notify { alert("You're up to date.", "SLEEPNOT \(Self.currentVersion) is the latest version.") }
            }
        } catch {
            pending = nil
            state = .failed("Check failed.")
            if notify { alert("Update check failed.", "Could not reach GitHub. Try again later.") }
        }
    }

    /// Download the new zip and swap it in, then relaunch.
    /// Only runs when the app lives in /Applications; otherwise the
    /// release page is opened so the user can install by hand.
    func installAvailable() {
        guard case let .available(_, page) = state, !installing else { return }
        guard let zipURL else {
            alert("Update unavailable.", "The release has no download. Get it from the release page.")
            NSWorkspace.shared.open(page)
            return
        }
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.path.hasPrefix("/Applications/") else {
            NSWorkspace.shared.open(page)
            return
        }
        guard FileManager.default.isWritableFile(atPath: bundleURL.path) else {
            alert("Can't update in place.", "/Applications is not writable. Get it from the release page.")
            NSWorkspace.shared.open(page)
            return
        }
        installing = true
        state = .checking
        URLSession.shared.downloadTask(with: zipURL) { [weak self] location, _, _ in
            guard let self, let location else {
                DispatchQueue.main.async { [weak self] in
                    self?.finishInstall(error: "Download failed.")
                }
                return
            }
            // Heavy work stays off the main thread; UI hops back after.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                do {
                    try self.swap(bundleURL: bundleURL, zip: location)
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(bundleURL)
                        NSApplication.shared.terminate(nil)
                    }
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? "Install failed."
                    DispatchQueue.main.async { [weak self] in
                        self?.finishInstall(error: message)
                    }
                }
            }
        }.resume()
    }

    // MARK: - Private

    private func swap(bundleURL: URL, zip: URL) throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        guard let fresh = try FileManager.default
            .contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.lastPathComponent == "SLEEPNOT.app" })
        else { throw UpdaterError.badArchive }
        try run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", fresh.path])
        // Atomic in-place replacement: either the new app is there or the
        // old one is untouched. No half-moved state, no stray backup.
        _ = try FileManager.default.replaceItemAt(bundleURL, withItemAt: fresh)
    }

    private func finishInstall(error: String) {
        installing = false
        if let pending {
            state = .available(version: pending.version, page: pending.page)
            let answer = alert("Update failed.", error, buttons: ["Get It by Hand", "Not Now"])
            if answer == .alertFirstButtonReturn { NSWorkspace.shared.open(pending.page) }
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
        dispatchPrecondition(condition: .onQueue(.main))
        // Agent app with no Dock icon: bring the alert forward.
        NSApp.activate(ignoringOtherApps: true)
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
