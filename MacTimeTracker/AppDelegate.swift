import AppKit

/// Minimal app delegate: keeps the app alive (menu-bar icon + timer) after the
/// window is closed, and reopens the window when the Dock icon is clicked.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Don't quit when the window's close button is pressed — the app keeps
    /// running in the background with its menu-bar item.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon reopens/raises the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.styleMask.contains(.titled) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
