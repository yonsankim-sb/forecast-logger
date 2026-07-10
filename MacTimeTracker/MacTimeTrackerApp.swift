import SwiftUI

/// Forecast scheduler. The main window is a SwiftUI `Window`; the menu-bar
/// "dynamic island" is created natively by `StatusBarController`, installed from
/// the window's `.task` (reliable once `NSApp` exists).
@main
struct MacTimeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth: AuthStore
    @StateObject private var model: TrackerViewModel
    @StateObject private var statusBar = StatusBarController()

    init() {
        // Register the bundled timer font before any view builds, so it renders
        // even on Macs that don't have SHIFTBRAIN Norms installed.
        AppFonts.registerBundled()
        let auth = AuthStore()
        _auth = StateObject(wrappedValue: auth)
        _model = StateObject(wrappedValue: TrackerViewModel(auth: auth))
    }

    var body: some Scene {
        Window("Forecast Schedule", id: "main") {
            MenuBarContentView()
                .environmentObject(auth)
                .environmentObject(model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .frame(minWidth: 300, minHeight: 200)
                .task { statusBar.installIfNeeded(auth: auth, model: model) }
        }
        .defaultSize(width: 440, height: 580)
        .commands {
            // Replace the "New Window" item — this is a single-window app.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
