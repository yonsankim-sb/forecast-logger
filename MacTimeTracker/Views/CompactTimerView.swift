import SwiftUI

/// A stripped-down "minimized" view shown when the window is small: project,
/// live timer, and Record / Pause / Stop over a moving noise-shader background.
struct CompactTimerView: View {
    @EnvironmentObject private var model: TrackerViewModel
    @State private var showControls = false

    var body: some View {
        ZStack {
            // Background layers don't take clicks, so a click on the shader falls
            // through to the drag handle (below) and moves the window; clicks on
            // the controls in `content` are handled by the controls themselves.
            NoiseBackground().allowsHitTesting(false)

            // Liquid Glass panel over the shader — refracts/frosts the moving
            // pattern behind it so the content reads clearly on top.
            frost.allowsHitTesting(false)

            content
        }
        .background(WindowDragHandle())
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .sheet(isPresented: $showControls) {
            NoiseControlsView()
        }
    }

    /// A subtle dark scrim so white text and controls stay legible over the
    /// rings. Deliberately a plain gradient — NOT a Liquid Glass / material
    /// backdrop: a full-bleed translucent material samples the desktop behind
    /// the window and washes the shader with whatever color is behind it. This
    /// only darkens the opaque shader beneath, so the rings keep their color.
    private var frost: some View {
        LinearGradient(
            colors: [.black.opacity(0.12), .black.opacity(0.32)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    /// One responsive layout with uniform padding: project name + tool buttons on
    /// the top row, the big timer centered, and the controls along the bottom.
    /// The timer scales with the available height. Tool buttons live in the top
    /// row so they never overlap the controls.
    private var content: some View {
        GeometryReader { geo in
            // Size from the height, then clamp so the readout also fits the width.
            let heightSize = min(max(geo.size.height * 0.24, 32), 66)
            let text = TrackerViewModel.shortTime(model.elapsedSeconds)
            let timerSize = TimerMetrics.fittingSize(text: text, available: geo.size.width - 32, maxSize: heightSize)
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    projectLabel
                    Spacer(minLength: 8)
                    iconButton("arrow.up.backward.and.arrow.down.forward", help: "Expand") {
                        expandToFull()
                    }
                    iconButton("slider.horizontal.3", help: "Shader style") {
                        showControls = true
                    }
                }
                Spacer(minLength: 8)
                timerReadout(fontSize: timerSize)
                Spacer(minLength: 8)
                controls
            }
            .padding(16)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var projectLabel: some View {
        Text(projectName)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timerReadout(fontSize: CGFloat) -> some View {
        RollingTime(
            text: TrackerViewModel.shortTime(model.elapsedSeconds),
            size: fontSize,
            color: .white
        )
        .fixedSize()
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            CircleControl(
                system: "play.fill", tint: .green,
                label: model.isPaused ? "Resume" : "Start",
                enabled: model.canRecord, filledWhenEnabled: true
            ) { model.record() }

            CircleControl(
                system: "pause.fill", tint: .orange, label: "Pause",
                enabled: model.isTimerRunning
            ) { model.pause() }

            CircleControl(
                system: "stop.fill", tint: .red, label: "Stop",
                enabled: model.isRecording
            ) { model.stop() }
        }
        .fixedSize()
        .frame(maxWidth: .infinity)
    }

    private func iconButton(_ system: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            iconButtonLabel(system)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    /// Small circular affordance: Liquid Glass on macOS 26+, translucent white
    /// disc on earlier systems.
    @ViewBuilder
    private func iconButtonLabel(_ system: String) -> some View {
        let base = Image(systemName: system)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(8)
        if #available(macOS 26.0, *) {
            base.glassEffect(.regular.interactive(), in: Circle())
        } else {
            base.background(.white.opacity(0.12), in: Circle())
        }
    }

    /// Leave compact mode: resize back to full.
    private func expandToFull() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) else { return }
        var frame = window.frame
        let top = frame.maxY
        frame.size = NSSize(width: 440, height: 580)
        frame.origin.y = top - frame.size.height
        window.setFrame(frame, display: true, animate: false)
    }

    private var projectName: String {
        model.activeProjectLabel ?? model.selectedProject?.displayName ?? "No project"
    }
}

/// A background view that lets the title-bar-less compact window be dragged from
/// empty areas, without stealing clicks from the controls in front of it. This
/// replaces `NSWindow.isMovableByWindowBackground`, which routed SwiftUI button
/// taps into a window drag so Start/Stop sometimes never fired.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        // Only fires for clicks that fall through to the background (i.e. not on a
        // control), so it never interferes with the timer buttons.
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Configures the host `NSWindow` for compact mode: transparent, title-less,
/// full-size-content title bar (so the shader fills to the top and the
/// "Forecast Schedule" title disappears), restored in full mode. It does NOT
/// resize the window — doing that during a live drag fought the user's resize
/// and caused the mode to oscillate.
struct WindowChrome: NSViewRepresentable {
    let compact: Bool
    /// Natural height of the full-mode content (0 when unknown). In full mode the
    /// window is clamped to this height so it can't be dragged taller than its
    /// content, and is sized to fit whenever the content height changes.
    var contentHeight: CGFloat = 0

    /// Remembers the last height we imposed, so we only resize when the content
    /// height genuinely changes — never in response to the user's own drag.
    final class Coordinator { var lastAppliedHeight: CGFloat = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        let compact = self.compact
        let contentHeight = self.contentHeight
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.titlebarAppearsTransparent = compact
            window.titleVisibility = compact ? .hidden : .visible
            // NOTE: do NOT use isMovableByWindowBackground — in the title-bar-less
            // compact window it swallowed SwiftUI button taps into a window drag
            // (Start/Stop wouldn't fire). Dragging is handled by `WindowDragHandle`
            // behind the content instead, which never steals control clicks.
            window.isMovableByWindowBackground = false
            if compact {
                window.styleMask.insert(.fullSizeContentView)
            } else {
                window.styleMask.remove(.fullSizeContentView)
            }
            // Hide/show the toolbar and traffic-light buttons together with the
            // title bar here (AppKit), rather than also toggling toolbar
            // visibility from SwiftUI — the two managers fought and the full
            // chrome sometimes failed to come back when leaving compact mode.
            window.toolbar?.isVisible = !compact
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = compact
            }

            // Floor tall enough that the compact layout (label + timer +
            // controls) never gets squeezed / clipped when the window shrinks.
            let minSize = NSSize(width: 300, height: 220)
            if compact || contentHeight <= 1 {
                // Compact mode drives its own height, but not below the floor.
                window.contentMinSize = minSize
                window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                               height: CGFloat.greatestFiniteMagnitude)
                coordinator.lastAppliedHeight = 0
                // Nudge a restored/dragged frame back up if it sits below the floor.
                let frame = window.frame
                let currentContentHeight = window.contentRect(forFrameRect: frame).height
                if currentContentHeight < minSize.height - 0.5 {
                    let chrome = frame.height - currentContentHeight
                    var newFrame = frame
                    newFrame.size.height = minSize.height + chrome
                    newFrame.origin.y = frame.maxY - newFrame.size.height
                    window.setFrame(newFrame, display: true, animate: false)
                }
                return
            }

            // Fit the window to the content, capped to the visible screen height
            // (so very tall content scrolls rather than running off-screen).
            let screenHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 2000
            let target = min(contentHeight, screenHeight)
            window.contentMinSize = minSize
            window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: target)

            let frame = window.frame
            let currentContentHeight = window.contentRect(forFrameRect: frame).height
            // Refit when the content height itself changed, or trim whenever the
            // window is taller than its content (empty space / oversized restored
            // frame). A window the user dragged *shorter* is left alone so it can
            // still scroll or collapse toward compact mode.
            let contentChanged = abs(coordinator.lastAppliedHeight - target) > 0.5
            let tooTall = currentContentHeight > target + 0.5
            coordinator.lastAppliedHeight = target
            guard (contentChanged || tooTall),
                  abs(currentContentHeight - target) > 0.5 else { return }

            let chrome = frame.height - currentContentHeight   // title bar height
            var newFrame = frame
            newFrame.size.height = target + chrome
            newFrame.origin.y = frame.maxY - newFrame.size.height   // keep top edge fixed
            window.setFrame(newFrame, display: true, animate: false)
        }
    }
}

/// A full-bleed shader background (Metal on macOS 14+, solid fill below). The
/// shader draws the app icon's concentric circles continuously emanating from
/// the center; `NoiseSettings` drives the expansion speed.
struct NoiseBackground: View {
    @ObservedObject private var settings = NoiseSettings.shared

    var body: some View {
        // Render the shader directly at the live view size so it always fills the
        // bounds exactly. (The old approach rendered at a fixed reference size and
        // scaled it to cover — during a resize the scale lagged a frame and left
        // black bars above/below where the scaled content didn't reach yet.)
        GeometryReader { geo in
            noiseFill(size: geo.size)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func noiseFill(size: CGSize) -> some View {
        if #available(macOS 14.0, *) {
            TimelineView(.animation) { context in
                let now = context.date.timeIntervalSince1970
                // Keep the time value small so Float precision stays smooth.
                let t = Float(now.truncatingRemainder(dividingBy: 3600))
                Rectangle()
                    .fill(.black)
                    .colorEffect(makeShader(size: size, time: t))
            }
        } else {
            Color(red: 1.0, green: 0.584, blue: 0.0)   // #FF9500 fallback
        }
    }

    @available(macOS 14.0, *)
    private func makeShader(size: CGSize, time: Float) -> Shader {
        let p = settings.params
        let arguments: [Shader.Argument] = [
            .float2(Float(size.width), Float(size.height)),
            .float(time),
            .float(Float(p.speed)),
            .float(Float(p.circles)),
            .float(Float(p.refraction)),
            .float(Float(p.gloss)),
            .float(Float(p.aberration)),
            .float(Float(p.rim)),
            .float(Float(p.hue)),
            .float(Float(p.iridescence)),
            .float(Float(p.reflection)),
            .float(Float(p.caustics)),
            .float(Float(p.saturation)),
        ]
        return Shader(function: ShaderFunction(library: .default, name: "iconCircles"), arguments: arguments)
    }
}

extension View {
    /// Explicit separable Gaussian blur via a Metal `layerEffect` (macOS 14+),
    /// with edge clamping so borders don't darken. Falls back to `.blur` below.
    @ViewBuilder
    func gaussianBlur(radius: Double, size: CGSize) -> some View {
        if radius < 0.5 {
            self
        } else if #available(macOS 14.0, *) {
            let r = Float(radius)
            let w = Float(size.width), h = Float(size.height)
            self
                .layerEffect(
                    ShaderLibrary.gaussianBlur(.float2(1, 0), .float(r), .float2(w, h)),
                    maxSampleOffset: CGSize(width: radius, height: 0)
                )
                .layerEffect(
                    ShaderLibrary.gaussianBlur(.float2(0, 1), .float(r), .float2(w, h)),
                    maxSampleOffset: CGSize(width: 0, height: radius)
                )
        } else {
            self.blur(radius: radius)
        }
    }
}

#if DEBUG
#Preview("Compact – wide") {
    let auth = AuthStore.preview()
    CompactTimerView()
        .environmentObject(auth)
        .environmentObject(TrackerViewModel.preview(auth: auth, running: true))
        .frame(width: 540, height: 200)
}

#Preview("Compact – tall") {
    let auth = AuthStore.preview()
    CompactTimerView()
        .environmentObject(auth)
        .environmentObject(TrackerViewModel.preview(auth: auth, running: true))
        .frame(width: 360, height: 440)
}
#endif
