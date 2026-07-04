import SwiftUI
import KeyboardShortcuts
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var appState = AppState.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Hotkeys") {
                LabeledContent("Hold to talk") {
                    Text("Right ⌥ (Option)")
                        .foregroundStyle(.secondary)
                }
                KeyboardShortcuts.Recorder("Toggle dictation:", name: .toggleDictation)
            }

            Section("Speech to text") {
                Picker("Whisper model", selection: $settings.whisperModel) {
                    Text("Large v3 Turbo — best accuracy (~1.6 GB)")
                        .tag(SettingsStore.whisperModels[0])
                    Text("Large v3 Turbo compressed (~0.6 GB)")
                        .tag(SettingsStore.whisperModels[1])
                    Text("Small — fastest (~0.5 GB)")
                        .tag(SettingsStore.whisperModels[2])
                    Text("Base — lightest")
                        .tag(SettingsStore.whisperModels[3])
                }
                Text("Changing the model triggers a download on next dictation if it isn't cached yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cleanup") {
                Toggle("Polish text with local LLM (Ollama)", isOn: $settings.llmCleanupEnabled)
                if settings.llmCleanupEnabled {
                    TextField("Ollama model", text: $settings.ollamaModel)
                        .help("Small models like gemma3:1b keep latency and memory low. Large models (7B+) are slow next to Whisper on 16 GB.")
                }
                Text("Filler words (um, uh) are always removed, even without the LLM. Small models can occasionally drop or swap words — leave this off if exact wording matters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            if let last = appState.lastTranscript {
                Section("Last transcript") {
                    Text(last)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "Uvaach Settings"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
