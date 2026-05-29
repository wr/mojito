import AppKit

enum AppRelauncher {
    /// Relaunches the app in place. A detached shell waits for this process
    /// to fully exit before reopening, so `SingleInstanceCoordinator` doesn't
    /// see a live same-bundle peer and make the newcomer quit. Used when a
    /// fresh Accessibility/Input Monitoring grant only registers on a clean
    /// launch.
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"\(path)\"",
        ]
        try? task.run()
        NSApp.terminate(nil)
    }
}
