import SwiftUI

/// The main app window — a clean, card-based modern macOS layout.
struct MenuBarContentView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var model: TrackerViewModel

    @State private var showSettings = false
    @State private var showAddAllocation = false
    @State private var showNoiseControls = false
    @State private var didBootstrap = false
    @State private var isCompact = false
    /// Natural height of the full-mode content (incl. its 20 pt padding), fed to
    /// `WindowChrome` so the window fits the content instead of expanding freely.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if isCompact {
                    // Minimized / compact mode with a moving noise-shader background.
                    CompactTimerView()
                } else {
                    fullContent(width: proxy.size.width)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WindowChrome(compact: isCompact, contentHeight: contentHeight))
            .onAppear { updateCompact(height: proxy.size.height) }
            .onChange(of: proxy.size.height) { h in updateCompact(height: h) }
        }
        // The compact and full layouts (orange shader vs. white cards) are too
        // different to cross-fade cleanly while the window is also resizing and
        // its chrome toggles — an opacity blend left ghosted timers and dark
        // flashes. Snap between them instantly at the threshold instead.
        .textSelection(.disabled)
        .tint(.blue)
        .environment(\.locale, auth.locale)
        .background(isCompact ? Color.black : Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 300, minHeight: 200)
        // Toolbar visibility is driven by `WindowChrome` (AppKit) in compact mode
        // — see the note there — so it isn't toggled here.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    auth.languageCode = (auth.languageCode == "ja") ? "en" : "ja"
                } label: {
                    Image(systemName: "globe")
                }
                .help(auth.languageCode == "ja" ? "Switch to English" : "日本語に切り替え")

                Button {
                    Task { await model.refreshToday() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!auth.isConfigured || model.isRefreshing)
                .help("Refresh")

                Button { showNoiseControls = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Background style")

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showNoiseControls) {
            NoiseControlsView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(auth).environmentObject(model)
                .environment(\.locale, auth.locale)
        }
        .sheet(isPresented: $showAddAllocation) {
            ManualEntryView().environmentObject(model).environmentObject(auth)
                .environment(\.locale, auth.locale)
        }
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            await model.bootstrap()
        }
    }

    private func updateCompact(height: CGFloat) {
        // Hysteresis: enter compact well below the threshold, exit well above it,
        // so the mode can't flip-flop as the window is dragged near the boundary.
        let want: Bool
        if isCompact {
            guard height > 400 else { return }
            want = false
        } else {
            guard auth.isConfigured, height < 320 else { return }
            want = true
        }
        // Instant snap (no crossfade) so the two very different layouts never
        // render on top of each other during the switch.
        isCompact = want
    }

    // MARK: - Full content

    private func fullContent(width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let notice = model.notice {
                    NoticeView(notice: notice) { model.dismissNotice() }
                }

                if !auth.isConfigured {
                    connectCard
                } else {
                    if !model.isOnline { offlinePill }
                    timerCard(width: width)
                    scheduleCard
                    // Same card container as the others so every section shares
                    // one width, padding, and resize behavior.
                    TodaySummaryView().cardSurface()
                }
            }
            .padding(20)
            // Pin content to the viewport width so cards fill evenly.
            .frame(width: width, alignment: .leading)
            // Report the content's natural height (padding included) so the
            // window can be sized to fit it rather than expanded arbitrarily.
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                }
            )
            .animation(.easeInOut(duration: 0.25), value: model.notice)
            .hideScrollers()
        }
        .scrollIndicators(.hidden)
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Not configured

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SymbolBadge(system: "bolt.horizontal.fill", tint: .blue, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect to Forecast").font(.headline)
                    Text("Add your token to schedule time and track hours.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                showSettings = true
            } label: {
                Text("Open Settings…").frame(maxWidth: .infinity)
            }
            .cardActionButton()
        }
        .cardSurface()
    }

    private var offlinePill: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
            Text("Offline — reconnect to schedule.")
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Timer card

    private func timerCard(width: CGFloat) -> some View {
        let fontSize = timerFontSize(forWidth: width)
        return VStack(alignment: .leading, spacing: 22) {
            ProjectPickerView()

            Divider()

            // Reflows to a centered, stacked layout when the window is too narrow.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    timerReadout(.leading, fontSize: fontSize)
                    Spacer(minLength: 12)
                    timerControls
                }
                VStack(spacing: 16) {
                    timerReadout(.center, fontSize: fontSize)
                    timerControls
                }
                .frame(maxWidth: .infinity)
            }
        }
        .cardSurface()
    }

    /// Timer size that shrinks to fit the card's width, so the big numerals never
    /// force a larger minimum width than the other cards (which caused the timer
    /// card to overflow on the right when the window narrowed).
    private func timerFontSize(forWidth width: CGFloat) -> CGFloat {
        // Card content width = window width − outer padding (20·2) − card inset (16·2),
        // minus a safety margin so the numerals always stay comfortably inside the
        // card (a zero-margin fit could overflow and widen only this card).
        let cardContent = max(width - 72 - 12, 60)
        let text = TrackerViewModel.shortTime(model.elapsedSeconds)
        // Size against the *actual* fixed-slot layout width so the timer fits the
        // same content width as the other cards (matching their minimum width).
        return TimerMetrics.fittingSize(text: text, available: cardContent, maxSize: 70)
    }

    private func timerReadout(_ alignment: HorizontalAlignment, fontSize: CGFloat) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            RollingTime(
                text: TrackerViewModel.shortTime(model.elapsedSeconds),
                size: fontSize,
                color: model.isTimerRunning ? .primary : .secondary
            )
            // Trim the font's cap whitespace so the number optically hugs the
            // divider — this makes the gap above and below the divider look equal.
            .padding(.top, -TextMetrics.capInset(size: fontSize, fontName: AppTheme.timerFontName))
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var timerControls: some View {
        HStack(spacing: 14) {
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
    }

    private var statusColor: Color {
        if model.isTimerRunning { return .red }
        if model.isPaused { return .orange }
        return .secondary
    }

    private var statusText: String {
        if model.isTimerRunning { return L.s("Recording actual time", "実時間を記録中", auth.languageCode) }
        if model.isPaused { return L.s("Paused", "一時停止中", auth.languageCode) }
        return L.s("Timer idle", "タイマー停止中", auth.languageCode)
    }

    // MARK: - Schedule card

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Plan in Forecast")
            Text("Schedule planned hours on a project for a date or range.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showAddAllocation = true
            } label: {
                Label("Schedule…", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .cardActionButton()
            .disabled(!model.isOnline)
        }
        .cardSurface()
    }
}

/// Carries the full-mode content's measured height up to the window sizer.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A dismissible, typed inline notice (success / error / info) — colored and
/// iconed by kind.
struct NoticeView: View {
    let notice: Notice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(notice.message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { onDismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
        }
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var tint: Color {
        switch notice.kind {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }

    private var icon: String {
        switch notice.kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

#if DEBUG
#Preview("Full window") {
    let auth = AuthStore.preview()
    MenuBarContentView()
        .environmentObject(auth)
        .environmentObject(TrackerViewModel.preview(auth: auth))
        .frame(width: 440, height: 640)
}
#endif
