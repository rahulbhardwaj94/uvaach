import Foundation

/// UserDefaults-backed app settings.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// WhisperKit model names as they appear in argmaxinc/whisperkit-coreml.
    static let whisperModels = [
        "openai_whisper-large-v3-v20240930",        // large-v3-turbo, best accuracy (~1.6 GB)
        "openai_whisper-large-v3-v20240930_626MB",  // compressed turbo (~0.6 GB)
        "openai_whisper-small",                     // low-latency / low-memory fallback
        "openai_whisper-base",
    ]

    @Published var whisperModel: String {
        didSet { UserDefaults.standard.set(whisperModel, forKey: "whisperModel") }
    }
    @Published var llmCleanupEnabled: Bool {
        didSet { UserDefaults.standard.set(llmCleanupEnabled, forKey: "llmCleanupEnabled") }
    }
    @Published var ollamaModel: String {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: "ollamaModel") }
    }

    private init() {
        let defaults = UserDefaults.standard
        whisperModel = defaults.string(forKey: "whisperModel") ?? Self.whisperModels[0]
        // Default OFF: A/B testing vs Wispr Flow showed the 1B cleanup model
        // drops words ("I think"), swaps meaning ("and"→"or"), and stutters —
        // while the LLM-free path scored 0% WER on long-form. Rule-based
        // cleanup + Whisper's own punctuation is the trustworthy baseline;
        // the LLM stays available as an opt-in.
        llmCleanupEnabled = defaults.object(forKey: "llmCleanupEnabled") as? Bool ?? false
        ollamaModel = defaults.string(forKey: "ollamaModel") ?? "gemma3:1b"
    }
}
