import Foundation

/// Persistent dictation history, newest first. Stored as JSON in
/// ~/Library/Application Support/rbFlow/history.json, capped at 500 entries.
@MainActor
final class TranscriptStore: ObservableObject {
    static let shared = TranscriptStore()
    private static let maxEntries = 500

    struct Entry: Identifiable, Codable, Equatable {
        let id: UUID
        let date: Date
        let text: String
        let audioSeconds: Double
    }

    @Published private(set) var entries: [Entry] = []

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "rbFlow")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appending(path: "history.json")
        entries = (try? JSONDecoder().decode([Entry].self, from: Data(contentsOf: fileURL))) ?? []
    }

    func add(text: String, audioSeconds: Double) {
        entries.insert(Entry(id: UUID(), date: .now, text: text, audioSeconds: audioSeconds), at: 0)
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
