import Foundation

/// Persistent dictation history, newest first. Stored as JSON in
/// ~/Library/Application Support/Vani/history.json, capped at 500 entries.
@MainActor
final class TranscriptStore: ObservableObject {
    static let shared = TranscriptStore()
    private static let maxEntries = 500

    struct Entry: Identifiable, Codable, Equatable {
        let id: UUID
        let date: Date
        let text: String
        /// What Whisper actually heard, before cleanup. Optional so history
        /// saved by older versions still decodes.
        let raw: String?
        let audioSeconds: Double
        /// Stop → text-ready latency. Optional: absent on older entries.
        let processingSeconds: Double?
        /// "incremental" (chunks decoded while speaking) or "classic"
        /// (full decode after stop). Optional on older entries.
        let engine: String?
    }

    @Published private(set) var entries: [Entry] = []

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Vani")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appending(path: "history.json")
        entries = (try? JSONDecoder().decode([Entry].self, from: Data(contentsOf: fileURL))) ?? []
    }

    func add(text: String, raw: String? = nil, audioSeconds: Double,
             processingSeconds: Double? = nil, engine: String? = nil) {
        entries.insert(
            Entry(id: UUID(), date: .now, text: text, raw: raw, audioSeconds: audioSeconds,
                  processingSeconds: processingSeconds, engine: engine),
            at: 0
        )
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    func delete(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
