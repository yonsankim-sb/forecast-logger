import SwiftUI

/// Schedule an allocation across a date range: project, start/end date, hours
/// per day, notes. Native grouped-form styling.
struct ManualEntryView: View {
    @EnvironmentObject private var model: TrackerViewModel
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var project: ForecastProject?
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var hoursText = "8"
    @State private var notes = ""
    @State private var showProjectSheet = false
    @State private var localError: String?

    private var hoursValue: Double? {
        Double(hoursText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        project != nil && (hoursValue ?? 0) > 0 && endDate >= startDate && !model.isBusy
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SymbolBadge(system: "calendar.badge.plus", tint: .blue, size: 30)
                Text("Schedule Time").font(.headline)
                Spacer()
            }
            .padding(20)

            Form {
                Section("Project") {
                    ProjectRowButton(project: project) { showProjectSheet = true }
                        .environmentObject(model)
                }

                Section("When") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        .onChange(of: startDate) { newValue in
                            if endDate < newValue { endDate = newValue }
                        }
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                    HStack(spacing: 8) {
                        Text("Hours / day")
                        Spacer()
                        // Editable hours, then a fixed "/ 1" (per one day).
                        
                        TextField("", text: $hoursText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 52)
                            .multilineTextAlignment(.trailing)
                        Text("/").foregroundStyle(.secondary)
                        Text("1").foregroundStyle(.secondary).monospacedDigit()
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes)
                }

                if let localError {
                    Section {
                        Label(localError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollIndicators(.hidden)
            .hideScrollers()

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if model.isBusy { ProgressView().controlSize(.small) }
                        Text("Add to Schedule")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .padding(20)
        }
        .frame(width: 460, height: 540)
        .tint(.blue)
        .textSelection(.disabled)
        .sheet(isPresented: $showProjectSheet) {
            ProjectSearchSheet(selectedProjectId: project?.id) { project = $0 }
                .environmentObject(model)
                .environment(\.locale, auth.locale)
        }
    }

    private func save() async {
        guard let project, let hours = hoursValue else { return }
        localError = nil
        let ok = await model.addAssignment(
            project: project,
            start: TrackerViewModel.isoDate(startDate),
            end: TrackerViewModel.isoDate(endDate),
            hours: hours,
            notes: notes
        )
        if ok { dismiss() }
    }
}

#if DEBUG
#Preview("Schedule") {
    let auth = AuthStore.preview()
    ManualEntryView()
        .environmentObject(TrackerViewModel.preview(auth: auth))
        .environmentObject(auth)
}
#endif
