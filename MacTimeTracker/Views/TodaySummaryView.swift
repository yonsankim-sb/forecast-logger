import SwiftUI
import Charts

/// Today at a glance: toggle between **Logged** (real hours from the local timer)
/// and **Scheduled** (Forecast assignments). Logged mode offers a "Sync" action
/// that rewrites today's Forecast assignments to match logged hours.
struct TodaySummaryView: View {
    @EnvironmentObject private var model: TrackerViewModel
    @EnvironmentObject private var auth: AuthStore

    enum Mode: String, CaseIterable, Identifiable {
        case logged = "Logged"
        case scheduled = "Scheduled"
        case insights = "Insights"
        var id: String { rawValue }

        func title(_ lang: String) -> String {
            switch self {
            case .logged: return L.s("Logged", "実績", lang)
            case .scheduled: return L.s("Scheduled", "予定", lang)
            case .insights: return L.s("Insights", "分析", lang)
            }
        }
    }

    @State private var mode: Mode = .logged
    @State private var pendingDelete: PendingDelete?
    @State private var showSyncConfirm = false

    // Note editing
    @State private var showNoteEditor = false
    @State private var noteDraft = ""
    @State private var editingIds: [UUID] = []

    private enum PendingDelete: Identifiable {
        case assignment(ForecastAssignment)
        case logged(label: String, ids: [UUID])
        var id: String {
            switch self {
            case let .assignment(a): return "a\(a.id)"
            case let .logged(_, ids): return "l" + ids.map(\.uuidString).joined()
            }
        }
    }

    var body: some View {
        // A segmented picker + switched content, wrapped by `cardSurface` at the
        // call site — so this panel is the same width and padding as the other
        // cards (a macOS TabView draws its own, differently-sized box). The
        // segmented control still gets Liquid Glass on macOS 26.
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.title(auth.languageCode)).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            switch mode {
            case .logged:
                tabPage(title: L.s("Logged today", "今日の実績", auth.languageCode),
                        total: model.todayLoggedHours, showSync: true) {
                    loggedList
                }
            case .scheduled:
                tabPage(title: L.s("Scheduled today", "今日の予定", auth.languageCode),
                        total: model.todayTotalHours, showSync: false) {
                    scheduledList
                }
            case .insights:
                insightsPage
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) {
                switch item {
                case let .assignment(a): Task { await model.deleteAssignment(a) }
                case let .logged(_, ids): model.deleteLogged(ids: ids)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { item in
            switch item {
            case let .assignment(a):
                Text("Removes the Forecast assignment: \(model.projectLabel(for: a)). This affects the shared schedule.")
            case let .logged(label, ids):
                Text("Removes \(ids.count) logged session\(ids.count == 1 ? "" : "s"): \(label).")
            }
        }
        .confirmationDialog(
            L.s("Sync today's hours to Forecast?",
                "今日の実績を Forecast に同期しますか？", auth.languageCode),
            isPresented: $showSyncConfirm,
            titleVisibility: .visible
        ) {
            Button(L.s("Sync", "同期する", auth.languageCode), role: .destructive) {
                Task { await model.syncLoggedToForecast() }
            }
            Button(L.s("Cancel", "キャンセル", auth.languageCode), role: .cancel) {}
        } message: {
            Text(L.s("For each project you logged today, its Forecast assignment for today is set to those hours (created if none exists). Multi-day bookings are split so only today changes — the other days keep their hours. Projects you didn't log are left unchanged.",
                     "今日記録した各プロジェクトについて、今日の Forecast アサインメントを実績時間に設定します（なければ新規作成）。複数日にまたがる予定は分割し、今日だけを変更します（他の日はそのまま）。記録のないプロジェクトは変更しません。",
                     auth.languageCode))
        }
        .alert(L.s("Forecast updated", "Forecast を更新しました", auth.languageCode),
               isPresented: $model.showForecastReviewPrompt) {
            Button(L.s("View in Forecast", "Forecast で確認", auth.languageCode)) { model.openForecastInBrowser() }
            Button(L.s("Not now", "今はしない", auth.languageCode), role: .cancel) {}
        } message: {
            Text(L.s("Your Forecast schedule was updated. Open Forecast in your browser to review?",
                     "Forecast のスケジュールを更新しました。ブラウザで開いて確認しますか？", auth.languageCode))
        }
        .alert("Note", isPresented: $showNoteEditor) {
            TextField("What is this time for?", text: $noteDraft)
            Button("Save") { model.setNote(noteDraft, forIds: editingIds) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add or edit the note for these logged sessions.")
        }
    }

    private func editNote(ids: [UUID], current: String) {
        editingIds = ids
        noteDraft = current
        showNoteEditor = true
    }

    /// One tab's page: a header (label · optional Sync · total) above its list.
    @ViewBuilder
    private func tabPage<Content: View>(
        title: String, total: Double, showSync: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionLabel(title)
                Spacer()
                if model.isRefreshing || model.isBusy {
                    ProgressView().controlSize(.small)
                }
                // Always laid out (invisible on the Scheduled tab) so the label
                // and the total sit at the same position on both tabs.
                Button {
                    showSyncConfirm = true
                } label: {
                    Label(L.s("Sync", "同期", auth.languageCode), systemImage: "arrow.up.circle")
                }
                .glassButton()
                .disabled(!showSync || model.todayLoggedHours <= 0 || !model.isOnline || model.isBusy)
                .help(L.s("Push today's logged hours to Forecast",
                          "今日の実績を Forecast に反映", auth.languageCode))
                .opacity(showSync ? 1 : 0)
                .allowsHitTesting(showSync)
                .accessibilityHidden(!showSync)
                Text(TrackerViewModel.formatHours(total))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Logged

    @ViewBuilder
    private var loggedList: some View {
        let summary = model.loggedGroupedToday
        if summary.groups.isEmpty {
            emptyState(icon: "timer", text: "No time logged today.\nPick a project and press Start.")
        } else {
            VStack(spacing: 8) {
                ForEach(summary.groups) { group in
                    groupCard(label: group.label, hours: group.hours, tint: .green) {
                        ForEach(group.noteGroups) { note in
                            noteRow(
                                note: note.note,
                                hours: note.hours,
                                running: note.isRunning,
                                onEdit: { editNote(ids: note.entryIds, current: note.note) },
                                onDelete: { pendingDelete = .logged(label: note.note.isEmpty ? group.label : note.note, ids: note.entryIds) }
                            )
                        }
                    }
                }
            }
        }
    }

    /// A merged note line: note on the left (tap to add/edit), summed hours right.
    private func noteRow(note: String, hours: Double, running: Bool, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            if running {
                Image(systemName: "record.circle").foregroundStyle(.red).font(.caption)
            }
            // Tappable note area (add a note when there isn't one).
            Button(action: onEdit) {
                HStack(spacing: 5) {
                    Text(note.isEmpty ? "Add note…" : note)
                        .font(.caption)
                        .foregroundStyle(note.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    if note.isEmpty {
                        Image(systemName: "square.and.pencil").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(TrackerViewModel.formatHours(hours))
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Button(action: onDelete) { Image(systemName: "trash").font(.caption2) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
    }

    // MARK: - Scheduled

    @ViewBuilder
    private var scheduledList: some View {
        let summary = model.groupedToday
        if summary.groups.isEmpty {
            emptyState(icon: "calendar", text: "Nothing scheduled today.")
        } else {
            VStack(spacing: 8) {
                ForEach(summary.groups, id: \.label) { group in
                    groupCard(label: group.label, hours: group.hours, tint: .blue) {
                        ForEach(group.assignments) { a in
                            row(
                                running: false,
                                primary: TrackerViewModel.formatHours(a.hoursPerDay) + "/day",
                                secondary: scheduledSubtitle(a)
                            ) { pendingDelete = .assignment(a) }
                        }
                    }
                }
            }
        }
    }

    private func scheduledSubtitle(_ a: ForecastAssignment) -> String? {
        if let notes = a.notes, !notes.isEmpty { return notes }
        if !a.isSingleDay, let s = a.startDate, let e = a.endDate { return "\(s) → \(e)" }
        return nil
    }

    // MARK: - Insights

    private var dailyBreakdown: [DayBreakdown] { model.loggedDailyBreakdown(days: 7) }

    /// A single logged session placed on the day's timeline.
    private struct DaySegment: Identifiable {
        let id: UUID
        let start: Date
        let end: Date
        /// Color/legend series: the note, or the project name when there's none.
        let series: String
    }

    /// Today's sessions (running one clamped to now) for the timeline.
    private var daySessions: [DaySegment] {
        model.todayLoggedEntries.compactMap { entry in
            let end = entry.end ?? Date()
            guard end > entry.start else { return nil }
            let note = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return DaySegment(id: entry.id, start: entry.start, end: end,
                              series: note.isEmpty ? entry.projectLabel : note)
        }
    }

    /// Stable task→color mapping shared by BOTH charts and the legend, so a task
    /// is the same color everywhere.
    private var seriesOrder: [String] {
        var seen: [String] = []
        for day in dailyBreakdown {
            for seg in day.segments where !seen.contains(seg.label) { seen.append(seg.label) }
        }
        for session in daySessions where !seen.contains(session.series) { seen.append(session.series) }
        return seen
    }
    private var seriesColors: [String: Color] {
        let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .red, .mint, .cyan, .yellow, .brown]
        var map: [String: Color] = [:]
        for (index, series) in seriesOrder.enumerated() { map[series] = palette[index % palette.count] }
        return map
    }

    /// The whole Insights tab: today's timeline, a shared color legend, a per-day
    /// breakdown (each day separate, segments = tasks), then today's plan vs actual.
    private var insightsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(L.s("Today", "今日", auth.languageCode))
                dayTimelineChart
            }
            if !seriesOrder.isEmpty { legend }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(L.s("By day · last 7 days", "日別・過去7日", auth.languageCode))
                dailyBarsChart
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(L.s("Planned vs actual · today", "予定 vs 実績・今日", auth.languageCode))
                planVsActualChart
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Human day label for the per-day chart: Today / Yesterday / M/D.
    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        if cal.isDateInToday(date) { return L.s("Today", "今日", auth.languageCode) }
        if cal.isDateInYesterday(date) { return L.s("Yesterday", "昨日", auth.languageCode) }
        let formatter = DateFormatter()
        formatter.locale = auth.locale
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    /// Shared legend: which color is which task (note, or project when no note).
    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(seriesOrder, id: \.self) { series in
                HStack(spacing: 5) {
                    Circle().fill(seriesColors[series] ?? .gray).frame(width: 8, height: 8)
                    Text(series).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    /// Vertical timeline: time of day on the y-axis, each session a block colored
    /// by task (shared color scale), so you can see when you did what.
    @ViewBuilder
    private var dayTimelineChart: some View {
        let sessions = daySessions
        if sessions.isEmpty {
            emptyState(icon: "clock",
                       text: L.s("No sessions logged today yet.",
                                 "今日の記録はまだありません。", auth.languageCode))
        } else {
            let lo = (sessions.map(\.start).min() ?? Date()).addingTimeInterval(-1800)
            let hi = (sessions.map(\.end).max() ?? Date()).addingTimeInterval(1800)
            Chart(sessions) { seg in
                RectangleMark(
                    x: .value("Day", "Today"),
                    yStart: .value("Start", seg.start),
                    yEnd: .value("End", seg.end)
                )
                .foregroundStyle(by: .value("Work", seg.series))
            }
            .chartForegroundStyleScale(domain: seriesOrder, range: seriesOrder.map { seriesColors[$0] ?? .gray })
            .chartYScale(domain: lo...hi)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartLegend(.hidden)
            .frame(height: 240)
        }
    }

    /// One stacked bar **per day** (newest first), its width proportional to that
    /// day's total and its colored segments showing each task's share (same colors
    /// as the timeline + legend). Keeps each date separate instead of lumping the
    /// whole week together.
    @ViewBuilder
    private var dailyBarsChart: some View {
        let data = dailyBreakdown
        if data.isEmpty {
            emptyState(icon: "chart.bar",
                       text: L.s("No time logged in the last 7 days.",
                                 "過去7日間の記録がありません。", auth.languageCode))
        } else {
            let maxTotal = max(data.map(\.total).max() ?? 1, 0.1)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(data) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(dayLabel(day.date))
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 8)
                            Text(TrackerViewModel.formatHours(day.total))
                                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                .fixedSize()
                        }
                        GeometryReader { geo in
                            let full = geo.size.width * CGFloat(day.total / maxTotal)
                            HStack(spacing: 0) {
                                ForEach(day.segments) { seg in
                                    (seriesColors[seg.label] ?? .blue)
                                        .frame(width: max(2, full * CGFloat(seg.hours / day.total)))
                                }
                            }
                            .frame(width: full, height: 16, alignment: .leading)
                            .clipShape(Capsule())
                        }
                        .frame(height: 16)
                    }
                }
            }
        }
    }

    /// Per-project comparison of today's actual (logged) vs planned (Forecast)
    /// hours — two bars on a shared scale, so over/under-runs are obvious.
    @ViewBuilder
    private var planVsActualChart: some View {
        let data = model.todayPlannedVsActual()
        if data.isEmpty {
            emptyState(icon: "calendar.badge.clock",
                       text: L.s("Nothing scheduled or logged today.",
                                 "今日の予定・実績がありません。", auth.languageCode))
        } else {
            let maxHours = max(data.flatMap { [$0.planned, $0.actual] }.max() ?? 1, 0.1)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    planActualLegendChip(.blue, L.s("Actual", "実績", auth.languageCode))
                    planActualLegendChip(Color.secondary.opacity(0.45), L.s("Planned", "予定", auth.languageCode))
                }
                ForEach(data) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.label)
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 8)
                            Text("\(TrackerViewModel.formatHours(item.actual)) / \(TrackerViewModel.formatHours(item.planned))")
                                .font(.caption2).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                        }
                        GeometryReader { geo in
                            VStack(alignment: .leading, spacing: 3) {
                                Capsule().fill(Color.blue.gradient)
                                    .frame(width: max(2, geo.size.width * CGFloat(item.actual / maxHours)), height: 8)
                                Capsule().fill(Color.secondary.opacity(0.45))
                                    .frame(width: max(2, geo.size.width * CGFloat(item.planned / maxHours)), height: 8)
                            }
                        }
                        .frame(height: 19)
                    }
                }
            }
        }
    }

    private func planActualLegendChip(_ color: Color = .blue, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 10, height: 8)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Shared bits

    private func groupCard<Content: View>(label: String, hours: Double, tint: Color, @ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(label).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(TrackerViewModel.formatHours(hours))
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            rows()
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func row(running: Bool, primary: String, secondary: String?, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            if running {
                Image(systemName: "record.circle").foregroundStyle(.red).font(.caption)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(primary).font(.caption).monospacedDigit()
                if let secondary { Text(secondary).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            Button(action: onDelete) { Image(systemName: "trash").font(.caption2) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title).foregroundStyle(.tertiary)
            Text(text)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

#if DEBUG
#Preview("Today") {
    let auth = AuthStore.preview()
    TodaySummaryView()
        .environmentObject(TrackerViewModel.preview(auth: auth))
        .environmentObject(auth)
        .frame(width: 380)
        .padding()
}
#endif
