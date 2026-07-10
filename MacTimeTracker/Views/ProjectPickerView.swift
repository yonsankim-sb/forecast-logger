import SwiftUI

/// A reusable project selector row (badge + name + client + chevron), styled
/// like a System Settings row. Tapping runs `action` (typically opens the
/// searchable `ProjectSearchSheet`).
struct ProjectRowButton: View {
    @EnvironmentObject private var model: TrackerViewModel
    let project: ForecastProject?
    var isLoading: Bool = false
    /// When true, the row sits on a Liquid Glass chip (macOS 26+) instead of a
    /// bare System-Settings-style row.
    var glass: Bool = false
    let action: () -> Void

    private var row: some View {
        HStack(spacing: 12) {
            SymbolBadge(system: "folder.fill", tint: .blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(project?.displayName ?? "Choose a project…")
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(project == nil ? Color.secondary : Color.primary)
                if let project, let client = model.clientName(for: project) {
                    Text(client).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Tap to search projects").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if glass, #available(macOS 26.0, *) {
            row
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            row.contentShape(Rectangle())
        }
    }
}

/// Inline project selector + notes field for the main timer card.
struct ProjectPickerView: View {
    @EnvironmentObject private var model: TrackerViewModel
    @EnvironmentObject private var auth: AuthStore
    @State private var showProjectSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProjectRowButton(project: model.selectedProject, isLoading: model.isLoadingProjects, glass: true) {
                showProjectSheet = true
            }

            notesField
        }
        .sheet(isPresented: $showProjectSheet) {
            ProjectSearchSheet(selectedProjectId: model.selectedProject?.id) { model.selectProject($0) }
                .environmentObject(model)
                .environment(\.locale, auth.locale)
        }
    }

    /// Notes input, on a Liquid Glass field (macOS 26+) to match the project row.
    @ViewBuilder
    private var notesField: some View {
        let field = HStack(spacing: 8) {
            Image(systemName: "square.and.pencil").font(.caption).foregroundStyle(.secondary)
            TextField("Notes (optional)", text: $model.notes, prompt: Text("What is this time for?"))
                .textFieldStyle(.plain)
                .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)

        if #available(macOS 26.0, *) {
            field.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            field.background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// Modal searchable list of all active projects. Reports selection via `onSelect`
/// so it can drive either the timer's selection or a local one (schedule sheet).
struct ProjectSearchSheet: View {
    @EnvironmentObject private var model: TrackerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    let selectedProjectId: Int?
    let onSelect: (ForecastProject) -> Void

    private var filtered: [ForecastProject] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return model.projects }
        return model.projects.filter { model.searchHaystack(for: $0).contains(needle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Project").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .padding()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search code or name (e.g. 24-0001)", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(9)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(.horizontal)

            if model.projects.isEmpty {
                ContentUnavailableFallback(
                    title: model.isLoadingProjects ? "Loading projects…" : "No projects",
                    systemImage: "folder"
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    if query.isEmpty && !model.recentProjects.isEmpty {
                        Section(L.s("Recent", "最近使った", model.languageCode)) {
                            ForEach(model.recentProjects) { projectRow($0) }
                        }
                        Section(L.s("All projects", "すべて", model.languageCode)) {
                            ForEach(model.projects) { projectRow($0) }
                        }
                    } else {
                        ForEach(filtered) { projectRow($0) }
                    }
                }
                .listStyle(.inset)
                .scrollIndicators(.hidden)
                .hideScrollers()
            }
        }
        .frame(width: 440, height: 480)
        .tint(.blue)
        .textSelection(.disabled)
    }

    private func projectRow(_ project: ForecastProject) -> some View {
        Button {
            model.noteRecentProject(project)
            onSelect(project)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                SymbolBadge(system: "folder.fill", tint: .blue, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName).lineLimit(1)
                    if let client = model.clientName(for: project) {
                        Text(client).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if selectedProjectId == project.id {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }
}

/// Small stand-in for `ContentUnavailableView` to keep the min target simple.
struct ContentUnavailableFallback: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview("Project search") {
    let auth = AuthStore.preview()
    ProjectSearchSheet(selectedProjectId: 220212, onSelect: { _ in })
        .environmentObject(TrackerViewModel.preview(auth: auth))
}
#endif
