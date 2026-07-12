import SwiftUI
import AppKit

struct DashboardView: View {
    var body: some View {
        TabView {
            StatsTab()
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
            HistoryTab()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            VocabularyTab()
                .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
        }
        .frame(width: 560, height: 420)
    }
}

// MARK: - Stats

/// Usage stats derived from history: how often you dictate, how many words,
/// and how much time speaking saved over typing the same words.
private struct StatsTab: View {
    @ObservedObject private var store = TranscriptStore.shared

    /// Average typing speed used as the baseline for "time saved".
    private static let typingWPM = 40.0

    private struct PeriodStats: Identifiable {
        let id: String
        let label: String
        let dictations: Int
        let words: Int
        let spokenSeconds: Double
        /// Typing the same words at 40 wpm, minus the time spent speaking.
        var savedSeconds: Double {
            max(0, Double(words) / StatsTab.typingWPM * 60 - spokenSeconds)
        }
    }

    private var periods: [PeriodStats] {
        let cal = Calendar.current
        let now = Date()
        func stats(_ label: String, since: Date?) -> PeriodStats {
            let entries = since.map { s in store.entries.filter { $0.date >= s } }
                ?? store.entries
            let words = entries.reduce(0) {
                $0 + $1.text.split(whereSeparator: \.isWhitespace).count
            }
            return PeriodStats(
                id: label, label: label,
                dictations: entries.count, words: words,
                spokenSeconds: entries.reduce(0) { $0 + $1.audioSeconds }
            )
        }
        return [
            stats("Today", since: cal.startOfDay(for: now)),
            stats("This week", since: cal.dateInterval(of: .weekOfYear, for: now)?.start),
            stats("This month", since: cal.dateInterval(of: .month, for: now)?.start),
            stats("This year", since: cal.dateInterval(of: .year, for: now)?.start),
            stats("All time", since: nil),
        ]
    }

    private var speakingWPM: Double? {
        let all = periods.last!
        guard all.spokenSeconds > 5 else { return nil }
        return Double(all.words) / (all.spokenSeconds / 60)
    }

    /// Mean stop→text latency over the last 10 dictations that recorded one.
    private var recentLatency: Double? {
        let waits = store.entries.compactMap(\.processingSeconds).prefix(10)
        guard !waits.isEmpty else { return nil }
        return waits.reduce(0, +) / Double(waits.count)
    }

    var body: some View {
        let periods = self.periods
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                StatTile(
                    title: "Time saved (all time)",
                    value: Self.duration(periods.last!.savedSeconds),
                    symbol: "clock.badge.checkmark"
                )
                StatTile(
                    title: "Your speaking speed",
                    value: speakingWPM.map { "\(Int($0)) wpm" } ?? "—",
                    symbol: "gauge.with.needle"
                )
                StatTile(
                    title: "Words dictated",
                    value: "\(periods.last!.words)",
                    symbol: "text.word.spacing"
                )
                StatTile(
                    title: "Stop → text (last 10)",
                    value: recentLatency.map { String(format: "%.1fs", $0) } ?? "—",
                    symbol: "bolt"
                )
            }
            .padding(12)

            Table(periods) {
                TableColumn("Period", value: \.label)
                TableColumn("Dictations") { Text("\($0.dictations)") }
                TableColumn("Words") { Text("\($0.words)") }
                TableColumn("Speaking time") { Text(Self.duration($0.spokenSeconds)) }
                TableColumn("Time saved vs typing") { p in
                    Text(Self.duration(p.savedSeconds)).bold()
                }
            }

            Text("Time saved compares your speaking pace with typing the same words at \(Int(Self.typingWPM)) wpm (average typing speed).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    private static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
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
            if let raw = entry.raw, raw != entry.text {
                Text("Heard: \(raw)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            HStack {
                Text(entry.date, format: .dateTime.day().month().hour().minute())
                Text("· \(entry.audioSeconds, format: .number.precision(.fractionLength(1)))s of audio")
                if let wait = entry.processingSeconds {
                    // ⚡ = incremental (decoded while speaking); no bolt =
                    // classic full decode after stop.
                    Text("· ready in \(wait, format: .number.precision(.fractionLength(1)))s\(entry.engine == "incremental" ? " ⚡" : "")")
                }
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
            Text("When Vani keeps hearing a word wrong, add a correction. Matches are case-insensitive whole words/phrases; the replacement's exact casing is kept (e.g. \"rb flow\" → \"Vani\").")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(10)

            HStack {
                TextField("Heard as… (e.g. rb flow)", text: $newFind)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                TextField("Replace with… (e.g. Vani)", text: $newReplace)
                Button("Add") {
                    vocab.rules.append(.init(
                        find: newFind.trimmingCharacters(in: .whitespaces),
                        replace: newReplace.trimmingCharacters(in: .whitespaces)
                    ))
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
            win.title = "Vani Dashboard"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
