import SwiftUI
import AppKit

struct DashboardView: View {
    var body: some View {
        TabView {
            HistoryTab()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            VocabularyTab()
                .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
        }
        .frame(width: 560, height: 420)
    }
}

// MARK: - History

private struct HistoryTab: View {
    @ObservedObject private var store = TranscriptStore.shared
    @State private var query = ""

    private var filtered: [TranscriptStore.Entry] {
        guard !query.isEmpty else { return store.entries }
        return store.entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search transcripts…", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button("Clear All", role: .destructive) { store.clear() }
                    .disabled(store.entries.isEmpty)
            }
            .padding(10)

            if filtered.isEmpty {
                ContentUnavailableView(
                    store.entries.isEmpty ? "No dictations yet" : "No matches",
                    systemImage: "text.bubble",
                    description: Text(store.entries.isEmpty
                        ? "Hold Right Option and speak — everything you dictate lands here."
                        : "Try a different search.")
                )
            } else {
                List(filtered) { entry in
                    HistoryRow(entry: entry)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: TranscriptStore.Entry
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .textSelection(.enabled)
                .lineLimit(4)
            HStack {
                Text(entry.date, format: .dateTime.day().month().hour().minute())
                Text("· \(entry.audioSeconds, format: .number.precision(.fractionLength(1)))s of audio")
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) {
                    TranscriptStore.shared.delete(entry)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Vocabulary

private struct VocabularyTab: View {
    @ObservedObject private var vocab = VocabularyStore.shared
    @State private var newFind = ""
    @State private var newReplace = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("When rbFlow keeps hearing a word wrong, add a correction. Matches are case-insensitive whole words/phrases; the replacement's exact casing is kept (e.g. \"rb flow\" → \"rbFlow\").")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(10)

            HStack {
                TextField("Heard as… (e.g. rb flow)", text: $newFind)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                TextField("Replace with… (e.g. rbFlow)", text: $newReplace)
                Button("Add") {
                    vocab.rules.append(.init(find: newFind, replace: newReplace))
                    newFind = ""
                    newReplace = ""
                }
                .disabled(newFind.trimmingCharacters(in: .whitespaces).isEmpty
                          || newReplace.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            if vocab.rules.isEmpty {
                ContentUnavailableView(
                    "No corrections yet",
                    systemImage: "character.book.closed",
                    description: Text("Add one above — it applies to every future dictation.")
                )
            } else {
                List {
                    ForEach(vocab.rules) { rule in
                        HStack {
                            Text(rule.find)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text(rule.replace).bold()
                            Spacer()
                            Button(role: .destructive) {
                                vocab.rules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - Window

@MainActor
final class DashboardWindow {
    static let shared = DashboardWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: DashboardView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "rbFlow Dashboard"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
