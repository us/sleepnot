import AppKit
import SwiftUI

@main
struct SleepnotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Left click: indefinite on/off toggle. Right click (or control+click): duration menu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let durations: [(label: String, seconds: TimeInterval)] = [
        ("5 Minutes", 5 * 60),
        ("15 Minutes", 15 * 60),
        ("30 Minutes", 30 * 60),
        ("1 Hour", 3600),
        ("2 Hours", 7200),
        ("5 Hours", 18000),
    ]

    private let awake = AwakeController()
    private let updater = Updater()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(buttonClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        awake.onChange = { [weak self] in self?.refresh() }
        // A crashed run can leave lid-closed sleep disabled; every launch starts OFF.
        if LidGuard.isActive { LidGuard.disable() }
        refresh()
        // Update checks: shortly after launch, then daily. Silent
        // unless a new version (or a manual check) needs attention.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.updater.check()
        }
        Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.updater.check()
        }
    }

    func applicationWillTerminate(_: Notification) {
        awake.stop()
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        // Synthesized clicks (e.g. accessibility) may arrive with no
        // currentEvent; treat that as a plain left click and toggle.
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu(sender)
        } else {
            awake.toggle()
            refresh()
        }
    }

    private func refresh() {
        statusItem?.button?.image = statusIcon(isAwake: awake.isAwake)
        statusItem?.button?.toolTip = awake.isAwake ? "SLEEPNOT is awake" : "SLEEPNOT"
    }

    private func showMenu(_ button: NSStatusBarButton) {
        let menu = NSMenu()
        let title = menu.addItem(withTitle: "SLEEPNOT", action: nil, keyEquivalent: "")
        title.isEnabled = false
        let status = menu.addItem(withTitle: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(.separator())
        let indefinite = menu.addItem(
            withTitle: "Indefinitely", action: #selector(activateFromMenu(_:)), keyEquivalent: ""
        )
        indefinite.target = self
        indefinite.tag = -1
        indefinite.state = awake.isAwake && awake.activeDuration == nil ? .on : .off
        for (index, duration) in Self.durations.enumerated() {
            let item = menu.addItem(
                withTitle: duration.label, action: #selector(activateFromMenu(_:)), keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = awake.activeDuration == duration.seconds ? .on : .off
        }
        menu.addItem(.separator())
        switch updater.state {
        case let .available(version, _):
            let update = menu.addItem(
                withTitle: "Update to v\(version)…", action: #selector(installUpdate), keyEquivalent: ""
            )
            update.target = self
        case .checking:
            let item = menu.addItem(withTitle: "Checking for Updates…", action: nil, keyEquivalent: "")
            item.isEnabled = false
        case .idle, .upToDate, .failed:
            let check = menu.addItem(
                withTitle: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: ""
            )
            check.target = self
        }
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit SLEEPNOT", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
    }

    private func statusLine() -> String {
        guard awake.isAwake else { return "Sleep allowed." }
        guard awake.lidProtected else { return "Awake, but closing the lid may sleep." }
        guard let remaining = awake.remaining else { return "Awake. Sleep is for humans." }
        return "Awake for \(Self.format(remaining)) more."
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 { return "\(total / 3600)h \((total % 3600) / 60)m" }
        if total >= 60 { return "\(total / 60) min" }
        return "\(total) sec"
    }

    @objc private func activateFromMenu(_ sender: NSMenuItem) {
        if sender.tag < 0 {
            awake.start()
        } else {
            awake.start(duration: Self.durations[sender.tag].seconds)
        }
        refresh()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func checkUpdates() {
        updater.check(notify: true)
    }

    @objc private func installUpdate() {
        updater.installAvailable()
    }
}

/// ON = filled glyph, OFF = hollow outline. Rendered as a template so
/// macOS tints it for light/dark mode. Falls back to an SF Symbol
/// when the bundled PNGs are missing.
private func statusIcon(isAwake: Bool) -> NSImage? {
    let name = isAwake ? "IconOn" : "IconOff"
    if let url = Bundle.main.url(forResource: name, withExtension: "png"),
       let image = NSImage(contentsOf: url) {
        image.isTemplate = true
        image.size = NSSize(width: 20, height: 20)
        return image
    }
    let fallback = NSImage(systemSymbolName: isAwake ? "moon.fill" : "moon.zzz", accessibilityDescription: "SLEEPNOT")
    fallback?.isTemplate = true
    return fallback
}
