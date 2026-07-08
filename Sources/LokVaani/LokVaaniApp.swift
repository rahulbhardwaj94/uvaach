import SwiftUI
import UserNotifications

@main
struct LokVaaniApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.status.symbolName)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only; LSUIElement in Info.plist hides the Dock icon,
        // but enforce it when run as a bare executable during development.
        NSApp.setActivationPolicy(.accessory)

        if !PermissionsManager.shared.allGranted {
            OnboardingWindow.shared.show()
        }

        DictationController.shared.start()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }
}

/// Global app status, drives the menu-bar icon.
enum DictationStatus {
    case idle
    case recording
    case transcribing
    case injecting

    var symbolName: String {
        switch self {
        case .idle: "mic"
        case .recording: "mic.fill"
        case .transcribing: "waveform"
        case .injecting: "arrow.down.doc"
        }
    }

    var label: String {
        switch self {
        case .idle: "Idle"
        case .recording: "Recording…"
        case .transcribing: "Transcribing…"
        case .injecting: "Inserting text…"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var status: DictationStatus = .idle
    @Published var lastTranscript: String?
    /// Mic RMS level while recording, 0…~0.3 typical speech. Drives the HUD bars.
    @Published var audioLevel: Float = 0
    /// True when a ≥3 s hold released into hands-free mode (tap once to stop).
    @Published var isHandsFree = false

    private init() {}
}

struct MenuContent: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Text("LokVaani — \(appState.status.label)")
        Divider()
        Button("Dashboard…") {
            DashboardWindow.shared.show()
        }
        Button("Settings…") {
            SettingsWindow.shared.show()
        }
        Button("Setup & Permissions…") {
            OnboardingWindow.shared.show()
        }
        Divider()
        Button("Quit LokVaani") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
