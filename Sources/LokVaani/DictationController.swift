import AppKit

/// Orchestrates the dictation pipeline:
/// hotkey → record → transcribe → clean → inject, updating AppState throughout.
@MainActor
final class DictationController {
    static let shared = DictationController()

    private let recorder = AudioRecorder()
    private let hotkeys = HotkeyManager()

    /// Discard blips shorter than this (accidental key taps).
    private let minimumSamples = Int(AudioRecorder.targetSampleRate * 0.3)

    /// Holding the PTT key at least this long, then releasing, locks into
    /// hands-free mode: recording continues until a single tap of the key.
    private let handsFreeHoldThreshold: TimeInterval = 3.0
    private var pttDownAt: Date?
    private var suppressNextKeyUp = false

    private init() {}

    func start() {
        // Warm-load Whisper in the background so the first dictation is fast.
        Task.detached(priority: .utility) {
            await TranscriptionService.shared.warmUp(model: SettingsStore.shared.whisperModel)
        }

        hotkeys.onPushToTalkDown = { [weak self] in self?.pushToTalkDown() }
        hotkeys.onPushToTalkUp = { [weak self] in self?.pushToTalkUp() }
        hotkeys.onToggle = { [weak self] in
            guard let self else { return }
            AppState.shared.status == .recording ? finishRecording() : beginRecording()
        }
        hotkeys.start()
    }

    // MARK: - Push-to-talk with hands-free lock

    private func pushToTalkDown() {
        if AppState.shared.isHandsFree {
            // Single tap while hands-free: stop. Swallow the matching key-up
            // so it isn't misread as the end of a fresh hold.
            suppressNextKeyUp = true
            finishRecording()
            return
        }
        pttDownAt = Date()
        beginRecording()
    }

    private func pushToTalkUp() {
        if suppressNextKeyUp {
            suppressNextKeyUp = false
            return
        }
        guard AppState.shared.status == .recording else { return }
        if let downAt = pttDownAt, Date().timeIntervalSince(downAt) >= handsFreeHoldThreshold {
            // Held long enough: release doesn't stop — lock into hands-free
            // so long dictations don't require pinning the key down.
            AppState.shared.isHandsFree = true
            NSSound(named: "Tink")?.play()
            return
        }
        finishRecording()
    }

    private func beginRecording() {
        guard AppState.shared.status == .idle else { return }
        guard PermissionsManager.shared.microphone == .granted else {
            OnboardingWindow.shared.show()
            return
        }
        do {
            recorder.onLevel = { level in
                Task { @MainActor in
                    // Smooth the meter so the bars don't flicker.
                    let previous = AppState.shared.audioLevel
                    AppState.shared.audioLevel = previous * 0.6 + level * 0.4
                }
            }
            try recorder.start()
            AppState.shared.status = .recording
            DictationHUD.shared.show()
            NSSound(named: "Pop")?.play()
        } catch {
            NSLog("LokVaani: failed to start recording: \(error.localizedDescription)")
        }
    }

    private func finishRecording() {
        guard AppState.shared.status == .recording else { return }
        AppState.shared.status = .transcribing
        AppState.shared.audioLevel = 0
        AppState.shared.isHandsFree = false
        pttDownAt = nil

        Task {
            // Grace period: people release the key while the last word is
            // still leaving their mouth. Capture 300 ms more before stopping
            // so the tail isn't clipped ("…on its" instead of "…on its own").
            try? await Task.sleep(for: .milliseconds(300))
            let samples = recorder.stop()
            NSSound(named: "Bottle")?.play()

            guard samples.count >= minimumSamples else {
                AppState.shared.status = .idle
                DictationHUD.shared.hide()
                return
            }
            await process(samples: samples)
            // Success path already hid the pill at paste time; this covers
            // failures (empty transcript, injection fallback).
            DictationHUD.shared.hide()
            AppState.shared.status = .idle
        }
    }

    private func process(samples: [Float]) async {
        let settings = SettingsStore.shared
        let started = Date()

        let raw: String
        do {
            raw = try await TranscriptionService.shared.transcribe(
                samples: samples, model: settings.whisperModel,
                language: settings.language
            )
        } catch {
            NSLog("LokVaani: transcription failed: %@", error.localizedDescription)
            return
        }
        guard !raw.isEmpty else { return }

        var text = TextCleaner.clean(raw)
        // The 1B cleanup model helps short dictations (fillers, punctuation)
        // but drops sentences and mangles casing beyond a few sentences —
        // Whisper's own punctuation is already good there, so skip it.
        if settings.llmCleanupEnabled && text.count <= 350 {
            text = await OllamaClient().cleanup(text, model: settings.ollamaModel)
        }
        // Vocabulary corrections run last so they override both Whisper and
        // the LLM (exact casing like "LokVaani" survives).
        text = VocabularyStore.shared.apply(to: text)
        guard !text.isEmpty else { return }

        AppState.shared.status = .injecting
        AppState.shared.lastTranscript = text
        TranscriptStore.shared.add(
            text: text,
            raw: raw,
            audioSeconds: Double(samples.count) / AudioRecorder.targetSampleRate
        )
        _ = await TextInjector.insert(text) // hides the HUD itself at paste time

        NSLog("LokVaani: dictation done in %.2fs — \"%@\"",
              Date().timeIntervalSince(started), text)
    }
}
