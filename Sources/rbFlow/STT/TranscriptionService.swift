import Foundation
import WhisperKit

/// Owns the WhisperKit pipeline. Loaded once at launch (in the background)
/// and kept warm so each dictation only pays inference cost.
actor TranscriptionService {
    static let shared = TranscriptionService()

    enum State: Equatable {
        case unloaded
        case downloading
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .unloaded
    private var whisperKit: WhisperKit?
    private var loadedModel: String?

    /// Idempotent; safe to call at launch and again before first use.
    func warmUp(model: String) async {
        if state == .ready, loadedModel == model { return }
        if state == .downloading || state == .loading { return }

        do {
            state = .downloading
            NSLog("rbFlow: loading Whisper model '%@'…", model)
            let config = WhisperKitConfig(model: model)
            config.prewarm = true
            state = .loading
            let kit = try await WhisperKit(config)
            whisperKit = kit
            loadedModel = model
            state = .ready
            NSLog("rbFlow: Whisper model ready")
        } catch {
            state = .failed(error.localizedDescription)
            NSLog("rbFlow: Whisper load failed: %@", error.localizedDescription)
        }
    }

    /// Transcribes 16 kHz mono Float32 samples; returns the raw transcript.
    func transcribe(samples: [Float], model: String) async throws -> String {
        if state != .ready || loadedModel != model {
            await warmUp(model: model)
        }
        guard let whisperKit, state == .ready else {
            throw NSError(domain: "rbFlow.stt", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Speech model is not loaded."
            ])
        }

        let results = try await whisperKit.transcribe(audioArray: samples)
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
