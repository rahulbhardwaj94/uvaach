import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions = PermissionsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to rbFlow")
                .font(.title2.bold())
            Text("rbFlow needs three permissions to record your voice, watch the dictation hotkey, and type the transcribed text into other apps. Everything runs on-device — nothing leaves your Mac.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PermissionRow(
                title: "Microphone",
                detail: "Records audio while the hotkey is held.",
                state: permissions.microphone,
                action: { permissions.requestMicrophone() }
            )
            PermissionRow(
                title: "Accessibility",
                detail: "Lets rbFlow paste text into the focused app.",
                state: permissions.accessibility,
                action: { permissions.requestAccessibility() }
            )
            PermissionRow(
                title: "Input Monitoring",
                detail: "Detects the hold-to-talk key anywhere.",
                state: permissions.inputMonitoring,
                action: { permissions.requestInputMonitoring() }
            )

            if permissions.allGranted {
                Label("All set — you can close this window.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Text("After enabling a permission in System Settings, this list updates automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            permissions.refresh()
            permissions.startPolling()
        }
        .onDisappear { permissions.stopPolling() }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let state: PermissionState
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: state == .granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(state == .granted ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state != .granted {
                Button("Grant…", action: action)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Menu-bar apps have no main window, so onboarding lives in a manually
/// managed NSWindow that we can open from the menu or at first launch.
@MainActor
final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "rbFlow Setup"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
