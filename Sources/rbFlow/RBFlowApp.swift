import SwiftUI

@main
struct RBFlowApp: App {
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

    private init() {}
}

struct MenuContent: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Text("rbFlow — \(appState.status.label)")
        Divider()
        Button("Setup & Permissions…") {
            OnboardingWindow.shared.show()
        }
        Divider()
        Button("Quit rbFlow") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
