import LectorCore
import SwiftUI
import os

@main
struct ClaudeLectorApp: App {
    @State private var store: LectorStore
    // Without this binding SwiftUI quits the app whenever the status item is hidden — including when
    // macOS hides it on its own (System Settings › Menu Bar, or Control Center's block list).
    // With it the app keeps running hidden, stays reachable via the hotkey, and reappears once allowed.
    @State private var menuBarInserted = true

    init() {
        // Writing to a pipe whose reader died must be an error, not a crash.
        signal(SIGPIPE, SIG_IGN)
        do {
            let store = LectorStore(container: try LectorStore.makeContainer())
            store.startWatching()
            store.registerHotKey()
            _store = State(initialValue: store)
        } catch {
            fatalError("Claude Lector could not open its history store: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $menuBarInserted) {
            EntryListView(store: store)
                .modelContainer(store.container)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: menuBarInserted) { _, inserted in
            Logger(subsystem: "cz.lukisk.ClaudeLector", category: "app")
                .notice("menu bar item \(inserted ? "shown" : "hidden by macOS", privacy: .public)")
        }

        Window("Claude Lector", id: HistoryWindow.id) {
            HistoryWindow(store: store)
                .modelContainer(store.container)
        }
        .defaultSize(width: 1000, height: 680)
        .defaultLaunchBehavior(.suppressed)

        Window("Quick Check", id: QuickCheckWindow.id) {
            QuickCheckWindow(store: store)
                .modelContainer(store.container)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct MenuBarLabel: View {
    let store: LectorStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        icon.onAppear { store.openWindow = openWindow }
    }

    @ViewBuilder private var icon: some View {
        if case .unavailable = store.availability {
            Image(systemName: "exclamationmark.triangle")
        } else if store.badgeCount > 0 {
            HStack(spacing: 2) {
                Image(systemName: "text.badge.checkmark")
                Text("\(store.badgeCount)")
            }
        } else {
            Image(systemName: "text.badge.checkmark")
        }
    }
}
