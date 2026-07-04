import AppKit
import SwiftUI

/// Floating pill shown near the bottom of the screen during dictation:
/// level-reactive bars while recording, animated dots while processing.
/// It never takes focus (non-activating panel) so the target app keeps
/// its text field focused for the paste.
@MainActor
final class DictationHUD {
    static let shared = DictationHUD()

    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let hosting = NSHostingView(rootView: HUDView())
            let size = NSSize(width: 170, height: 44)
            let p = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            p.contentView = hosting
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .statusBar
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.isReleasedWhenClosed = false
            panel = p
        }
        position()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel?.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.minY + 80
        )
        panel.setFrameOrigin(origin)
    }
}

private struct HUDView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        HStack(spacing: 10) {
            switch appState.status {
            case .recording:
                PulsingRing()
                Text("Listening")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
            case .transcribing, .injecting:
                ProcessingDots()
                Text(appState.status == .transcribing ? "Transcribing…" : "Inserting…")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
            case .inserted:
                Text("Inserted")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 170, height: 44)
        .background(AuroraGlass())
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .tint(.blue)
    }
}

/// "Aurora Glass": near-black frosted glass with faint violet/indigo auroras
/// drifting inside the pill. Premium, cinematic, and dark in any wallpaper.
private struct AuroraGlass: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.62)
                // Two slow-drifting aurora blooms.
                RadialGradient(
                    colors: [Color.purple.opacity(0.32), .clear],
                    center: UnitPoint(x: 0.25 + 0.1 * sin(time * 0.4), y: 0.1),
                    startRadius: 0, endRadius: 90
                )
                RadialGradient(
                    colors: [Color.indigo.opacity(0.28), .clear],
                    center: UnitPoint(x: 0.8 + 0.08 * sin(time * 0.3 + 2), y: 0.9),
                    startRadius: 0, endRadius: 100
                )
            }
        }
    }
}

/// Soft pulsing ring around a small core dot — the "live" indicator.
private struct PulsingRing: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            // 0→1 sawtooth every 1.6 s drives the expanding ring.
            let phase = (time / 1.6).truncatingRemainder(dividingBy: 1)
            ZStack {
                Circle()
                    .strokeBorder(Color.cyan.opacity(0.5 * (1 - phase)), lineWidth: 1.5)
                    .frame(width: 8 + 14 * phase, height: 8 + 14 * phase)
                Circle()
                    .fill(
                        LinearGradient(colors: [.purple, .cyan],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 7, height: 7)
            }
            .frame(width: 22, height: 22)
        }
    }
}

private struct ProcessingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let pulse = 0.5 + 0.5 * sin(time * 5 - Double(i) * 0.9)
                    Circle()
                        .fill(.cyan)
                        .frame(width: 6, height: 6)
                        .opacity(0.35 + 0.65 * pulse)
                        .shadow(color: .cyan.opacity(0.8 * pulse), radius: 4)
                        .scaleEffect(0.85 + 0.3 * pulse)
                }
            }
        }
    }
}
