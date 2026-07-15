import Foundation

/// Fast, deterministic transcript cleanup. Always runs, LLM or not.
public enum TextCleaner {
    /// Standalone disfluencies Whisper tends to keep. Word-boundary matched,
    /// case-insensitive. m{3,} catches the "Mmm" hum (field: "Mmm......").
    /// The filler's own trailing comma/periods/ellipsis are swallowed with
    /// it — they punctuate the hum, not the sentence.
    private static let fillerPattern = try! NSRegularExpression(
        pattern: #"(?i)(?<![\w'])(um+|uh+|ah+|erm+|hmm+|m{3,})(?![\w'])[.,…]*\s*"#
    )

    /// `codeMode`: cleaning for terminals/editors — no auto-capitalization
    /// and no trailing sentence period, because `git statuS.` isn't a
    /// command and prose conventions have no business in a shell.
    public static func clean(_ text: String, codeMode: Bool = false) -> String {
        var result = text

        let range = NSRange(result.startIndex..., in: result)
        result = fillerPattern.stringByReplacingMatches(
            in: result, range: range, withTemplate: ""
        )

        // Whisper duplicates words at chunk boundaries ("issues. issues.").
        // Collapse exact immediate repeats of words ≥3 chars (incl. trailing
        // punctuation) — short repeats like "no, no" are left alone.
        result = result.replacingOccurrences(
            of: #"\b([A-Za-z']{3,}[.!?,]?)(\s+\1)+"#,
            with: "$1",
            options: .regularExpression
        )

        // Collapse doubled spaces and fix space-before-punctuation artifacts
        // left behind by filler removal.
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if codeMode {
            // Strip the single trailing period Whisper appends to speech —
            // fatal in a terminal, unwanted at a code cursor. Ellipses and
            // other punctuation stay.
            if result.hasSuffix("."), !result.hasSuffix("..") {
                result = String(result.dropLast())
            }
            return result
        }

        // Capitalize first letter if Whisper didn't.
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }
}
