import LectorCore
import SwiftData
import SwiftUI

struct EntryListView: View {
    let store: LectorStore
    @Query(EntryListView.latestChecked) private var entries: [PromptEntry]
    @State private var unseenOnOpen: Set<String> = []
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var confirmClear = false
    @Environment(\.openWindow) private var openWindow

    static var latestChecked: FetchDescriptor<PromptEntry> {
        var d = FetchDescriptor<PromptEntry>(predicate: #Predicate { $0.statusRaw == "checked" || $0.statusRaw == "failed" },
                                             sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        d.fetchLimit = 50
        return d
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if entries.isEmpty {
                ContentUnavailableView("No prompts yet", systemImage: "text.badge.checkmark",
                                       description: Text("English prompts you send in Claude Code show up here."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            EntryRow(entry: entry, isNew: unseenOnOpen.contains(entry.promptId))
                            Divider()
                        }
                    }
                }
            }
            Divider()
            footer
        }
        .frame(width: 440, height: 560)
        .onAppear { unseenOnOpen = store.markAllSeen() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Claude Lector").font(.headline)
                Spacer()
                Button("Open window", systemImage: "macwindow") {
                    openWindow(id: HistoryWindow.id)
                    NSApp.activate()
                }
                .controlSize(.small)
            }
            if case .unavailable(let reason) = store.availability {
                Label("\(reason) — prompts are queued (\(store.pendingCount))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if store.pendingCount > 0 {
                Text("Checking \(store.pendingCount) prompt\(store.pendingCount == 1 ? "" : "s")…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.engineSummary).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reload config") { store.reloadConfigAndProcess() }
            }
            HStack {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { _, on in
                        try? LaunchAtLogin.set(on)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                Spacer()
                Button("Clear history") { confirmClear = true }
                    .confirmationDialog("Delete all checked prompts?", isPresented: $confirmClear) {
                        Button("Clear history", role: .destructive) { store.clearHistory() }
                    }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .controlSize(.small)
        .padding(12)
    }
}
