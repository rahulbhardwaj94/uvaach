import Foundation

/// Whisper's training data (subtitled videos) makes it emit stock phrases
/// on near-silent audio — an accidental hands-free lock with no speech
/// produced a pasted "Thank you." in the field. These checks let the
/// pipeline discard output that is almost certainly hallucinated.
public enum WhisperArtifacts {
    /// Stock phrases Whisper produces from silence/room tone. Compared
    /// case- and punctuation-insensitively against the WHOLE transcript,
    /// so a real sentence that merely contains "thank you" is never hit.
    private static let silenceStock: Set<String> = [
        "thank you", "thank you thank you", "thank you so much",
        "thanks for watching", "thank you for watching",
        "thank you for watching and see you in the next video",
        "thanks for listening", "thank you for listening",
        "please subscribe", "don t forget to subscribe",
        "like and subscribe", "see you in the next video",
        "bye", "bye bye", "you",
        "subtitles by the amara org community",
    ]

    /// True when a transcript from a recording with very little detected
    /// speech (`speechSeconds` from the VAD) matches a known silence
    /// hallucination. Longer speech legitimizes any phrase — someone can
    /// really dictate "thank you so much".
    public static func isSilenceHallucination(_ text: String, speechSeconds: Double) -> Bool {
        guard speechSeconds < 1.5 else { return false }
        // Punctuation → spaces so "Bye-bye." and "bye bye" normalize the
        // same way, then collapse runs of whitespace.
        let mapped = text.lowercased().map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : " "
        }
        let normalized = String(mapped).split(separator: " ").joined(separator: " ")
        return silenceStock.contains(normalized)
    }
}
