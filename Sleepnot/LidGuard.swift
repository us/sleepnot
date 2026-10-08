import Foundation

/// Lid-closed sleep is handled below the assertion layer, so the only veto is
/// `pmset disablesleep`, which needs root. A one-time admin prompt installs a
/// sudoers rule limited to exactly that command; every later toggle is silent.
enum LidGuard {
    private static let pmset = "/usr/bin/pmset"
    private static let sudoersPath = "/etc/sudoers.d/sleepnot"

    /// True while `pmset disablesleep 1` is in effect.
    static var isActive: Bool {
        guard let output = run("/usr/bin/pmset", ["-g"]).output else { return false }
        return output.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
    }

    /// Turns the guard on, asking for the admin password once if needed.
    static func enable() -> Bool {
        set(true) || (install() && set(true))
    }

    @discardableResult
    static func disable() -> Bool {
        set(false)
    }

    private static func set(_ on: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", pmset, "disablesleep", on ? "1" : "0"]).ok
    }

    private static func install() -> Bool {
        let user = NSUserName()
        guard user.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else { return false }
        let rule = "\(user) ALL=(root) NOPASSWD: \(pmset) disablesleep 0, \(pmset) disablesleep 1"
        let tmp = "/tmp/sleepnot-sudoers.\(getpid())"
        let script = """
        echo '\(rule)' > \(tmp) \
        && /usr/sbin/visudo -cf \(tmp) \
        && install -m 0440 -o root -g wheel \(tmp) \(sudoersPath); \
        status=$?; rm -f \(tmp); exit $status
        """
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let prompt = "do shell script \"\(escaped)\" with administrator privileges "
            + "with prompt \"SLEEPNOT needs permission to keep your Mac awake with the lid closed.\""
        return run("/usr/bin/osascript", ["-e", prompt]).ok
    }

    private static func run(_ path: String, _ args: [String]) -> (ok: Bool, output: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (false, nil)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus == 0, String(data: data, encoding: .utf8))
    }
}
