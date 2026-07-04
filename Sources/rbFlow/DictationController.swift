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

    private init() {}

    func start() {
        // Warm-load Whisper in the background so the first dictation is fast.
        Task.detached(priority: .utility) {
            await TranscriptionService.shared.warmUp(model: SettingsStore.shared.whisperModel)
        }

        hotkeys.onPushToTalkDown = { [weak self] in self?.beginRecording() }
        hotkeys.onPushToTalkUp = { [weak self] in self?.finishRecording() }
        hotkeys.onToggle = { [weak self] in
            guard let self else { return }
            AppState.shared.status == .recording ? finishRecording() : beginRecording()
        }
        hotkeys.start()
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
            NSLog("rbFlow: failed to start recording: \(error.localizedDescription)")
        }
    }

    private func finishRecording() {
        guard AppState.shared.status == .recording else { return }
        let samples = recorder.stop()
        NSSound(named: "Bottle")?.play()

        AppState.shared.audioLevel = 0

        guard samples.count >= minimumSamples else {
            AppState.shared.status = .idle
            DictationHUD.shared.hide()
            return
        }

        AppState.shared.status = .transcribing
        Task {
            await process(samples: samples)
            AppState.shared.status = .idle
            DictationHUD.shared.hide()
        }
    }

    private func process(samples: [Float]) async {
        let settings = SettingsStore.shared
        let started = Date()

        let raw: String
        do {
            raw = try await TranscriptionService.shared.transcribe(
                samples: samples, model: settings.whisperModel
            )
        } catch {
            NSLog("rbFlow: transcription failed: %@", error.localizedDescription)
            return
        }
        guard !raw.isEmpty else { return }

        var text = TextCleaner.clean(raw)
        if settings.llmCleanupEnabled {
            text = await OllamaClient().cleanup(text, model: settings.ollamaModel)
        }
        // Vocabulary corrections run last so they override both Whisper and
        // the LLM (exact casing like "rbFlow" survives).
        text = VocabularyStore.shared.apply(to: text)
        guard !text.isEmpty else { return }

        AppState.shared.status = .injecting
        AppState.shared.lastTranscript = text
        TranscriptStore.shared.add(
            text: text,
            audioSeconds: Double(samples.count) / AudioRecorder.targetSampleRate
        )
        _ = await TextInjector.insert(text)

        NSLog("rbFlow: dictation done in %.2fs — \"%@\"",
              Date().timeIntervalSince(started), text)
    }
}
