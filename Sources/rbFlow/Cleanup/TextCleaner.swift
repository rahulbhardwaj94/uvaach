import Foundation

/// Fast, deterministic transcript cleanup. Always runs, LLM or not.
enum TextCleaner {
    /// Standalone disfluencies Whisper tends to keep. Word-boundary matched,
    /// case-insensitive, with any trailing comma/space swallowed.
    private static let fillerPattern = try! NSRegularExpression(
        pattern: #"(?i)(?<![\w'])(um+|uh+|erm+|hmm+)(?![\w'])[,]?\s*"#
    )

    static func clean(_ text: String) -> String {
        var result = text

        let range = NSRange(result.startIndex..., in: result)
        result = fillerPattern.stringByReplacingMatches(
            in: result, range: range, withTemplate: ""
        )

        // Collapse doubled spaces and fix space-before-punctuation artifacts
        // left behind by filler removal.
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize first letter if Whisper didn't.
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }
}
