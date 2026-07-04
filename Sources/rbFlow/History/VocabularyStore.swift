import Foundation

/// User-defined corrections for words Whisper keeps mishearing —
/// e.g. "rb flow" → "rbFlow", "nest js" → "NestJS".
/// Applied as the LAST pipeline step (after the LLM) so corrections and
/// casing always win. Matching is case-insensitive on word boundaries.
@MainActor
final class VocabularyStore: ObservableObject {
    static let shared = VocabularyStore()

    struct Rule: Identifiable, Codable, Equatable {
        var id = UUID()
        var find: String
        var replace: String
    }

    @Published var rules: [Rule] = [] {
        didSet { save() }
    }

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "rbFlow")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appending(path: "vocabulary.json")
        rules = (try? JSONDecoder().decode([Rule].self, from: Data(contentsOf: fileURL))) ?? []
    }

    func apply(to text: String) -> String {
        var result = text
        for rule in rules where !rule.find.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: rule.find)
            guard let regex = try? NSRegularExpression(
                pattern: #"(?i)\b"# + escaped + #"\b"#
            ) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.replace)
            )
        }
        return result
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
