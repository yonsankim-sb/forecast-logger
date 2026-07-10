import SwiftUI

/// A "dynamic island"–style card shown from the menu-bar icon: the project being
/// recorded, a big live timer, and Record / Pause / Stop controls.
struct IslandView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var model: TrackerViewModel

    /// Called by the "Open app" affordances to raise the main window.
    let onOpenApp: () -> Void

    @State private var didBootstrap = false

    var body: some View {
        ZStack {
            // Single rounded shape: fill + concentric inset border share the
            // exact same RoundedRectangle, so outer and inner corners match.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                // No shadow — the island sits flat with just its hairline border.

            content
                .padding(16)
        }
        .frame(width: 300)
        // Small transparent margin so the rounded corners aren't clipped by the
        // panel edge (no shadow to leave room for anymore).
        .padding(8)
        .tint(.blue)
        .environment(\.locale, auth.locale)
        .textSelection(.disabled)
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            await model.bootstrap()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !auth.isConfigured {
            notConfigured
        } else {
            VStack(spacing: 14) {
                statusChip
                projectRow
                timer
                controls
                footer
            }
        }
    }

    // MARK: - Not configured

    private var notConfigured: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.8))
            Text("Connect to Forecast")
                .font(.headline).foregroundStyle(.white)
            Text("Open the app to add your token.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            Button {
                onOpenApp()
            } label: {
                Text("Open App").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.15))
        }
        .padding(.vertical, 8)
    }

    // MARK: - Status

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .opacity(model.isTimerRunning ? 1 : 0.7)
            Text(statusText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .textCase(.uppercase)
                .kerning(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.10)))
    }

    private var statusColor: Color {
        if model.isTimerRunning { return .red }
        if model.isPaused { return .orange }
        return .gray
    }

    private var statusText: String {
        if model.isTimerRunning { return L.s("Recording", "記録中", auth.languageCode) }
        if model.isPaused { return L.s("Paused", "一時停止", auth.languageCode) }
        return L.s("Ready", "準備完了", auth.languageCode)
    }

    // MARK: - Project

    @ViewBuilder
    private var projectRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.blue)
                Image(systemName: "timer")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            if model.isRecording {
                Text(model.activeProjectLabel ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer(minLength: 0)
            } else {
                // Idle: choose a project to record.
                Menu {
                    if model.projects.isEmpty {
                        Text(model.isLoadingProjects ? "Loading…" : "No projects")
                    } else {
                        ForEach(model.projects) { project in
                            Button(project.displayName) { model.selectProject(project) }
                        }
                    }
                } label: {
                    HStack {
                        Text(model.selectedProject?.displayName ?? "Choose a project…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(model.selectedProject == nil ? .white.opacity(0.55) : .white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Timer

    private var timer: some View {
        RollingTime(
            text: TrackerViewModel.shortTime(model.elapsedSeconds),
            size: 44,
            color: .white
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 22) {
            // Record / Resume
            islandButton(
                system: "play.fill",
                tint: .green,
                label: model.isPaused ? "Resume" : "Record",
                enabled: model.canRecord
            ) { model.record() }

            // Pause
            islandButton(
                system: "pause.fill",
                tint: .orange,
                label: "Pause",
                enabled: model.isTimerRunning
            ) { model.pause() }

            // Stop
            islandButton(
                system: "stop.fill",
                tint: .red,
                label: "Stop",
                enabled: model.isRecording
            ) { model.stop() }
        }
    }

    private func islandButton(system: String, tint: Color, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 5) {
            Button(action: action) {
                ZStack {
                    Circle().fill(enabled ? tint.opacity(0.22) : Color.white.opacity(0.06))
                    Image(systemName: system)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(enabled ? tint : .white.opacity(0.25))
                }
                .frame(width: 54, height: 54)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(enabled ? 0.7 : 0.3))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Label(TrackerViewModel.formatHours(model.todayLoggedHours) + " today", systemImage: "sum")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Button {
                onOpenApp()
            } label: {
                Label("Open app", systemImage: "arrow.up.forward.app")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }
}

#if DEBUG
#Preview("Island") {
    let auth = AuthStore.preview()
    IslandView(onOpenApp: {})
        .environmentObject(auth)
        .environmentObject(TrackerViewModel.preview(auth: auth, running: true))
}
#endif
