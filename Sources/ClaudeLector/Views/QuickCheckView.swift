import LectorCore
import SwiftUI

/// A field for checking any sentence on the spot. ⌘↩ checks.
struct QuickCheckView: View {
    let store: LectorStore
    var large = false
    var focusOnAppear = false

    @State private var text = ""
    @State private var checking = false
    @State private var result: LectorStore.QuickCheckResult?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Check a sentence…", text: $text, axis: .vertical)
                    .lineLimit(1...(large ? 6 : 4))
                    .textFieldStyle(.roundedBorder)
                    .font(large ? .title3 : .body)
                    .focused($focused)
                    .onSubmit(check)   // Return in a single-line state
                Button(action: check) {
                    if checking { ProgressView().controlSize(.small) } else { Text("Check") }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(checking || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            switch result {
            case .entry(let entry):
                EntryRow(entry: entry, isNew: false)
                    .padding(-12)   // EntryRow brings its own padding
                    .padding(.top, 8)
            case .message(let message):
                Label(message, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
        }
        .onAppear { if focusOnAppear { focused = true } }
    }

    private func check() {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !checking else { return }
        checking = true
        result = nil
        Task {
            let outcome = await store.checkManually(input)
            result = outcome
            checking = false
            // Checked: clear the field for the next sentence (the result stays below).
            // A message (not English, engine down) keeps the text so it can be fixed or retried.
            if case .entry = outcome {
                text = ""
                focused = true
            }
        }
    }
}

/// Small window opened by the global hotkey.
struct QuickCheckWindow: View {
    static let id = "quick-check"
    let store: LectorStore

    var body: some View {
        ScrollView {
            QuickCheckView(store: store, large: true, focusOnAppear: true)
                .padding(20)
        }
        .frame(width: 560)
        .frame(minHeight: 140, maxHeight: 520)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.activate()
                NSApp.windows.first { $0.isVisible && $0.canBecomeKey && $0.title == "Quick Check" }?
                    .makeKeyAndOrderFront(nil)
            }
        }
    }
}
