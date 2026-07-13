import Foundation
import WhisperKit
import VaniCore

/// Owns the WhisperKit pipeline. Loaded once at launch (in the background)
/// and kept warm so each dictation only pays inference cost.
actor TranscriptionService {
    /// The main pipeline: the user's chosen (large-v3-turbo) model, used for
    /// the authoritative final transcript that gets pasted.
    static let shared = TranscriptionService()

    /// A second, independent instance running a small/fast model purely for
    /// the live preview. Kept separate so a preview re-decode never blocks the
    /// final pass — releasing the key is never slowed by an in-flight preview.
    static let preview = TranscriptionService()

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
    /// Vocabulary terms fed to the decoder as a glossary prompt so they're
    /// heard right the *first* time ("Vani", not "Bonnie") instead of being
    /// patched afterwards. Requires the forked WhisperKit (upstream 1.0.0's
    /// promptTokens returns empty transcripts — see Package.swift).
    private var biasTerms: [String] = []

    func setBiasTerms(_ terms: [String]) {
        // Dedupe (many rules map to the same canonical word — 7 mishear
        // rules all replacing to "Vani" once produced the prompt
        // "Glossary: Vani, Vani, Vani…", and a repeated-token prompt makes
        // the decoder emit empty text or fall down the temperature-retry
        // ladder, tripling chunk decode times).
        var seen = Set<String>()
        biasTerms = Array(terms.filter { seen.insert($0.lowercased()).inserted }.prefix(40))
    }

    /// Idempotent; safe to call at launch and again before first use.
    func warmUp(model: String) async {
        if state == .ready, loadedModel == model { return }
        if state == .downloading || state == .loading { return }

        do {
            state = .downloading
            publishState()
            NSLog("Vani: loading Whisper model '%@'…", model)
            let config = WhisperKitConfig(model: model)
            config.prewarm = true
            state = .loading
            publishState()
            let kit = try await WhisperKit(config)
            whisperKit = kit
            loadedModel = model
            state = .ready
            publishState()
            NSLog("Vani: Whisper model ready")
        } catch {
            state = .failed(error.localizedDescription)
            publishState()
            NSLog("Vani: Whisper load failed: %@", error.localizedDescription)
        }
    }

    /// Surface the main pipeline's model state to the UI (onboarding row,
    /// menu) — a first launch downloads ~1.6 GB and without this the user
    /// just sees a silent app and assumes it's broken. Only the shared
    /// instance publishes; the preview model stays invisible.
    private func publishState() {
        guard self === Self.shared else { return }
        let text: String? = switch state {
        case .downloading: "Downloading speech model (~1.6 GB, one time)…"
        case .loading: "Loading speech model…"
        case .failed(let message): "Speech model failed: \(message)"
        case .ready, .unloaded: nil
        }
        Task { @MainActor in AppState.shared.modelStatus = text }
    }

    /// Transcribes 16 kHz mono Float32 samples; returns the raw transcript.
    /// `language` is a Whisper code ("hi", "en", ...) or "auto" to detect.
    /// WhisperKit's defaults force English (usePrefillPrompt: true prefills
    /// "en" unless told otherwise), so we must pass options explicitly.
    func transcribe(samples: [Float], model: String, language: String) async throws -> String {
        if state != .ready || loadedModel != model {
            await warmUp(model: model)
        }
        guard let whisperKit, state == .ready else {
            throw NSError(domain: "Vani.stt", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Speech model is not loaded."
            ])
        }

        // Explicit language: the user committed to one — single pass.
        if language != "auto" {
            return try await decode(samples, language: language, on: whisperKit)
        }

        // Auto: Whisper detects one language for the whole clip and decodes
        // everything in it, so a mid-utterance switch (English → Hindi) gets
        // force-decoded as the first language (Hindi comes back as garbled
        // English + a "Bye" hallucination). Split on pauses (eagerly — a
        // breath-length 0.3 s gap is enough, since real switches rarely come
        // with a long pause), detect each segment's language on the *small*
        // preview model (fast, already loaded), and regroup adjacent
        // same-language segments so the big model still decodes once per
        // language run. A dictation with no pause, or all one language,
        // stays a single big-model pass.
        let segments = Self.speechSegments(in: samples)
        guard segments.count > 1 else {
            return try await decode(samples, language: nil, on: whisperKit)
        }

        var langs: [String] = []
        for seg in segments {
            let slice = Array(samples[seg.start..<seg.end])
            langs.append(await Self.detectLanguageFast(slice, fallback: whisperKit))
        }
        // Short segments (fillers) can't be language-ID'd reliably — inherit
        // from the nearest long neighbor instead of decoding junk.
        langs = SpeechSegmenter.smoothLanguages(segments: segments, languages: langs)

        // All one language after all: one whole-clip decode keeps it fast and
        // preserves cross-pause context (better punctuation than per-segment).
        if Set(langs).count <= 1 {
            return try await decode(samples, language: langs.first, on: whisperKit)
        }

        // Real code-switch: decode each same-language run in its language.
        let groups = SpeechSegmenter.groupByLanguage(segments: segments, languages: langs)
        NSLog("Vani: code-switch — %d segments → %d language runs: %@",
              segments.count, groups.count, groups.map(\.language).joined(separator: ","))
        var parts: [String] = []
        for group in groups {
            let slice = Array(samples[group.start..<group.end])
            let text = try await decode(slice, language: group.language, on: whisperKit)
            if !text.isEmpty { parts.append(text) }
        }
        return parts.joined(separator: " ")
    }

    /// Language ID for one segment, on the small preview model when it's
    /// ready (an encoder pass there is ~5–10× cheaper than on turbo, and it
    /// runs on a separate instance). Falls back to the main model, then "en".
    /// When the small model was never loaded (streaming preview flagged off),
    /// kick off a background warm-up so this dictation uses the slower
    /// fallback but later code-switches get the fast path.
    private static func detectLanguageFast(_ samples: [Float], fallback: WhisperKit) async -> String {
        if let lang = await preview.detectLanguage(samples) { return lang }
        Task.detached(priority: .background) {
            await preview.warmUp(model: SettingsStore.previewModel)
        }
        return (try? await fallback.detectLangauge(audioArray: samples).language) ?? "en"
    }

    /// Language ID on this instance's model; nil unless loaded and ready.
    func detectLanguage(_ samples: [Float]) async -> String? {
        guard state == .ready, let whisperKit else { return nil }
        return try? await whisperKit.detectLangauge(audioArray: samples).language
    }

    /// Language ID for the incremental transcriber: small model when ready
    /// (warms it lazily), own model otherwise, "en" as last resort.
    func detectLanguageAuto(_ samples: [Float]) async -> String {
        guard let whisperKit else { return "en" }
        return await Self.detectLanguageFast(samples, fallback: whisperKit)
    }

    /// One chunk of an incremental dictation.
    ///
    /// Deliberately NO cross-chunk prompt: `DecodingOptions.promptTokens` is
    /// broken in argmax-oss-swift 1.0.0 — any prompt makes the decoder emit
    /// <|endoftext|> as its first sampled token, producing empty text
    /// (verified empirically against real audio; plain-text prompt tokens,
    /// filtered specials, and disabled thresholds all fail identically).
    /// Chunks are pause-bounded phrases, so decoding them cold costs a bit
    /// of boundary punctuation, not correctness. Revisit on library upgrade.
    func decodeChunk(samples: [Float], model: String, language: String?) async throws -> String {
        if state != .ready || loadedModel != model {
            await warmUp(model: model)
        }
        guard let whisperKit, state == .ready else {
            throw NSError(domain: "Vani.stt", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Speech model is not loaded."
            ])
        }
        return try await decode(samples, language: language, on: whisperKit)
    }

    /// One Whisper decode. `language == nil` auto-detects; a code decodes in
    /// that language. The user's vocabulary rides along as a glossary prompt.
    private func decode(_ samples: [Float], language: String?, on whisperKit: WhisperKit) async throws -> String {
        var prompt: [Int]?
        if !biasTerms.isEmpty, let tokenizer = whisperKit.tokenizer {
            let glossary = " Glossary: " + biasTerms.joined(separator: ", ") + "."
            prompt = Array(tokenizer.encode(text: glossary).suffix(200))
        }
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            promptTokens: prompt
        )
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A prompted decode that comes back empty on real audio is almost
        // always the prompt confusing the decoder, not silence (field log:
        // a 14.9 s spoken tail → 0 chars). The glossary is a nicety; the
        // words are not. Retry bare before letting callers treat this as
        // silence and fall back to a full classic re-decode.
        if text.isEmpty, prompt != nil,
           samples.count > Int(2 * AudioRecorder.targetSampleRate) {
            let bare = DecodingOptions(
                task: .transcribe,
                language: language,
                usePrefillPrompt: true,
                detectLanguage: language == nil
            )
            let retried = try await whisperKit.transcribe(audioArray: samples, decodeOptions: bare)
            let bareText = retried.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            VaniLog.log("prompted decode empty → bare retry: \(bareText.count) chars")
            return bareText
        }
        return text
    }

    /// Split audio into pause-delimited speech segments (sample-index ranges).
    /// Voice-active regions separated by less than ~0.3 s are merged into one
    /// segment; longer silences split. Tiny blips are dropped. Returns a single
    /// segment (or none) when there's no clear pause to split on — the caller
    /// then decodes the whole clip in one pass.
    static func speechSegments(in samples: [Float]) -> [(start: Int, end: Int)] {
        // Threshold adapts to the clip: a fixed 0.02 sat *above* real speech
        // on a quiet mic, so the VAD saw a 40s dictation as near-total
        // silence and the incremental path decoded only stray loud slivers.
        let frameLength = Int(0.1 * 16_000)
        let threshold = SpeechSegmenter.adaptiveEnergyThreshold(
            frameRMS: SpeechSegmenter.frameRMS(of: samples, frameLength: frameLength)
        )
        let vad = EnergyVAD(sampleRate: 16_000, frameLength: 0.1, energyThreshold: threshold)
        let active = vad.calculateActiveChunks(in: samples)
            .map { (start: $0.startIndex, end: $0.endIndex) }
        return SpeechSegmenter.merge(activeChunks: active, totalSamples: samples.count)
    }

    /// Best-effort partial transcript for the live preview while recording.
    /// Reuses the already-loaded model (never triggers a download/load) and
    /// returns "" if the model isn't ready or the pass fails — the preview is
    /// disposable, so it must never throw into the UI or hold up the final
    /// pass. Temperature 0 keeps successive partials on a stable prefix.
    func transcribePreview(samples: [Float], model: String, language: String) async -> String {
        guard state == .ready, loadedModel == model, let whisperKit else { return "" }

        // temperatureFallbackCount 0 + no timestamps: a preview pass must be
        // fast and bounded. The retry ladder (re-decoding at rising
        // temperatures when the model loops on silence-heavy audio) can turn
        // one pass into 8–12 s, which freezes the preview — for a disposable
        // partial we'd rather show a flawed line than a stale one.
        let options = DecodingOptions(
            task: .transcribe,
            language: language == "auto" ? nil : language,
            temperature: 0,
            temperatureFallbackCount: 0,
            usePrefillPrompt: true,
            detectLanguage: language == "auto",
            withoutTimestamps: true
        )
        do {
            let started = Date()
            let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            NSLog("Vani: preview pass %.2fs for %.1fs audio",
                  Date().timeIntervalSince(started), Double(samples.count) / 16_000)
            return text
        } catch {
            return ""
        }
    }
}
