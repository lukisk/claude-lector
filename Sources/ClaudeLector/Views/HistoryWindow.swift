import AppKit
import LectorCore
import SwiftData
import SwiftUI

/// The full history in a normal window: list on the left, the selected prompt on the right.
struct HistoryWindow: View {
    static let id = "history"

    let store: LectorStore
    @Query(sort: \PromptEntry.timestamp, order: .reverse) private var allEntries: [PromptEntry]
    @State private var filter: HistoryFilter = .all
    @State private var query = ""
    @State private var selection: PromptEntry.ID?

    private var entries: [PromptEntry] {
        allEntries.filter { filter.matches($0.historyItem, query: query) }
    }

    var body: some View {
        NavigationSplitView {
            List(entries, selection: $selection) { entry in
                HistoryRow(entry: entry).tag(entry.id)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Nothing here yet" : "No matches",
                                           systemImage: query.isEmpty ? "text.badge.checkmark" : "magnifyingglass")
                }
            }
        } detail: {
            if let entry = entries.first(where: { $0.id == selection }) ?? nil {
                EntryDetailView(entry: entry)
                    .id(entry.id)
                    .onAppear { store.markSeen(entry) }
            } else {
                ContentUnavailableView("Select a prompt", systemImage: "text.alignleft")
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search prompts")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .onAppear {
            // A real app while the window is open: Dock icon and Cmd-Tab.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            if selection == nil { selection = entries.first?.id }
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

struct HistoryRow: View {
    let entry: PromptEntry

    var body: some View {
        let categories = entry.issues.map(\.issue.category)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if !entry.seen && categories.contains(.grammar) {
                    Circle().fill(.blue).frame(width: 7, height: 7)
                }
                Text(entry.projectName).font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.timestamp, format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(entry.checkedText ?? entry.prompt)
                .font(.callout)
                .lineLimit(2)
                .foregroundStyle(.secondary)
            Group {
                if entry.status == .failed {
                    Label("couldn't check", systemImage: "exclamationmark.circle")
                } else if categories.isEmpty {
                    Label("no mistakes", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text(HistoryItem.issueSummary(categories))
                        .foregroundStyle(categories.contains(.grammar) ? .red : .secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

struct EntryDetailView: View {
    let entry: PromptEntry

    var body: some View {
        let text = entry.checkedText ?? entry.prompt
        let issues = entry.issues
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 8) {
                    Text(entry.projectName).font(.title3.weight(.semibold))
                    Text(entry.timestamp, format: .dateTime.day().month().hour().minute())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if entry.status == .failed {
                        Label("Couldn't check this prompt", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    } else if issues.isEmpty {
                        Label("No mistakes", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }

                section("Your text") {
                    Text(EntryRow.styled(HighlightBuilder.original(text, issues: issues), strike: true))
                        .font(.title3)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }

                if !issues.isEmpty {
                    section("Corrected") {
                        Text(EntryRow.styled(HighlightBuilder.corrected(text, issues: issues), strike: false))
                            .font(.title3)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }

                    section("Mistakes") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(issues.enumerated()), id: \.offset) { _, li in
                                IssueCard(issue: li.issue)
                            }
                        }
                    }
                }

                if entry.truncated {
                    Text("Only the first 3000 characters were checked.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}

struct IssueCard: View {
    let issue: LectorCore.Issue

    var body: some View {
        let color = EntryRow.color(issue.category)
        HStack(alignment: .top, spacing: 12) {
            Text(issue.category.rawValue)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(color.opacity(0.18), in: Capsule())
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(issue.original).strikethrough().foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                    Text(issue.replacement).fontWeight(.semibold)
                }
                .font(.body)
                Text(issue.explanation).font(.callout).foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .opacity(issue.category == .typo ? 0.85 : 1)
    }
}

extension PromptEntry {
    var historyItem: HistoryItem {
        HistoryItem(status: status, categories: issues.map(\.issue.category),
                    text: checkedText ?? prompt, project: projectName)
    }
}
