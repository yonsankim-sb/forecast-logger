import SwiftUI
import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let mttToggleIsland = Notification.Name("mttToggleIsland")
}

/// Creates and owns the menu-bar item natively (`NSStatusItem`) and presents the
/// SwiftUI `IslandView` in a **chromeless transparent panel** — so the island is
/// the only rounded shape on screen (no popover chrome creating a second,
/// mismatched corner). Installed from the main window's `.task`.
@MainActor
final class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var hostingView: NSView?
    private var refreshTimer: Timer?
    private var installed = false
    private var hotKeyRef: EventHotKeyRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var model: TrackerViewModel?

    func installIfNeeded(auth: AuthStore, model: TrackerViewModel) {
        guard !installed else { return }
        installed = true
        self.model = model

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel)
            button.toolTip = "Time Tracker"
        }
        statusItem = item

        // The island content, hosted in a transparent borderless panel.
        let host = NSHostingView(
            rootView: IslandView(onOpenApp: { [weak self] in self?.openMainWindow() })
                .environmentObject(auth)
                .environmentObject(model)
        )
        host.setContentHuggingPriority(.required, for: .horizontal)
        host.setContentHuggingPriority(.required, for: .vertical)
        hostingView = host

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false            // the card draws its own shadow
        panel.level = .statusBar
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
        self.panel = panel

        updateButton()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateButton() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        NotificationCenter.default.addObserver(forName: .mttToggleIsland, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.togglePanel() }
        }
        registerHotKey()
    }

    // MARK: - Panel show/hide

    @objc private func togglePanel() {
        if panel?.isVisible == true { closePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard let panel, let host = hostingView else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(panelOrigin(size: size))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        startDismissMonitors()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        stopDismissMonitors()
    }

    /// Position the panel just below the status item, clamped on screen. Falls
    /// back to top-center (under the notch) if the item has no window.
    private func panelOrigin(size: NSSize) -> NSPoint {
        if let button = statusItem?.button, let win = button.window {
            let rect = win.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
            var x = rect.midX - size.width / 2
            var y = rect.minY - size.height - 4
            if let vf = screen?.visibleFrame {
                x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
                if y < vf.minY { y = vf.minY + 8 }
            }
            return NSPoint(x: x, y: y)
        }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 4)
    }

    private func startDismissMonitors() {
        stopDismissMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == UInt16(kVK_Escape) { self.closePanel() }
                return event
            }
            if event.window != self.panel { self.closePanel() }
            return event
        }
    }

    private func stopDismissMonitors() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
    }

    // MARK: - Global hotkey (Carbon; no accessibility permission needed)

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            NotificationCenter.default.post(name: .mttToggleIsland, object: nil)
            return noErr
        }, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D545454) /* 'MTTT' */, id: 1)
        let modifiers = UInt32(optionKey | cmdKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_T), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - Menu-bar button

    private func updateButton() {
        guard let button = statusItem?.button, let model else { return }
        let symbol: String
        if model.isTimerRunning { symbol = "record.circle" }
        else if model.isPaused { symbol = "pause.circle" }
        else { symbol = "clock" }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Time Tracker")
        image?.isTemplate = true
        button.image = image

        if model.isRecording {
            button.title = " " + TrackerViewModel.shortTime(model.elapsedSeconds)
        } else if model.todayLoggedHours > 0 {
            button.title = " " + TrackerViewModel.formatHours(model.todayLoggedHours)
        } else {
            button.title = ""
        }
    }

    // MARK: - Window

    func openMainWindow() {
        closePanel()
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
