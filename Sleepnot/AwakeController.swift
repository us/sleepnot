import Foundation

/// Holds a single `ProcessInfo` activity: blocks idle system sleep,
/// never touches display sleep. Also vetoes lid-closed sleep via `LidGuard`.
/// Supports timed runs; stops automatically when the timer fires.
final class AwakeController {
    private(set) var isAwake = false
    private(set) var activeUntil: Date?
    private(set) var activeDuration: TimeInterval?
    /// False when the admin prompt was declined: closing the lid may still sleep.
    private(set) var lidProtected = false

    /// Called on state changes (used to refresh the icon).
    var onChange: (() -> Void)?

    private var activity: NSObjectProtocol?
    private var timer: Timer?

    /// Block sleep indefinitely.
    func start() {
        start(duration: nil)
    }

    /// Block sleep for the given seconds, then stop automatically.
    /// Main thread only: the timer needs the main runloop to fire.
    func start(duration: TimeInterval?) {
        dispatchPrecondition(condition: .onQueue(.main))
        stop()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled],
            reason: "SLEEPNOT is keeping the Mac awake"
        )
        lidProtected = LidGuard.enable()
        activeDuration = duration
        if let duration {
            activeUntil = Date().addingTimeInterval(duration)
            timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.stop()
            }
        }
        isAwake = true
        onChange?()
    }

    /// Restore normal sleep behavior.
    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        timer?.invalidate()
        timer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        LidGuard.disable()
        lidProtected = false
        activeUntil = nil
        activeDuration = nil
        isAwake = false
        onChange?()
    }

    func toggle() {
        isAwake ? stop() : start()
    }

    /// Remaining time (nil when indefinite).
    var remaining: TimeInterval? {
        guard let activeUntil else { return nil }
        return max(activeUntil.timeIntervalSinceNow, 0)
    }

    deinit {
        timer?.invalidate()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }
}
