import AVFoundation
import ApplicationServices
import AppKit
import CoreGraphics

enum PermissionState {
    case granted
    case denied
    case notDetermined
}

/// Checks and requests the three TCC permissions rbFlow needs.
/// None of these can be granted programmatically — for Accessibility and
/// Input Monitoring the user must flip the switch in System Settings, so we
/// deep-link them there and re-check on a timer while onboarding is visible.
@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published var microphone: PermissionState = .notDetermined
    @Published var accessibility: PermissionState = .notDetermined
    @Published var inputMonitoring: PermissionState = .notDetermined

    var allGranted: Bool {
        microphone == .granted && accessibility == .granted && inputMonitoring == .granted
    }

    private var pollTimer: Timer?

    private init() {
        refresh()
    }

    func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphone = .granted
        case .notDetermined: microphone = .notDetermined
        default: microphone = .denied
        }

        accessibility = AXIsProcessTrusted() ? .granted : .denied

        switch CGPreflightListenEventAccess() {
        case true: inputMonitoring = .granted
        case false: inputMonitoring = .denied
        }
    }

    // MARK: - Requests

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                self?.microphone = granted ? .granted : .denied
            }
        }
    }

    /// Shows the system prompt (once) and/or opens System Settings.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            openSettings(pane: "Privacy_Accessibility")
        }
        refresh()
    }

    func requestInputMonitoring() {
        if !CGRequestListenEventAccess() {
            openSettings(pane: "Privacy_ListenEvent")
        }
        refresh()
    }

    private func openSettings(pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Polling (Accessibility/Input Monitoring have no grant callback)

    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                if self.allGranted { self.stopPolling() }
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
