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
    private static let size = NSSize(width: 150, height: 34)

    func show() {
        if panel == nil {
            let hosting = NSHostingView(rootView: HUDView())
            let p = NSPanel(
                contentRect: NSRect(origin: .zero, size: Self.size),
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
        // Follow the user across displays: show on the screen holding the
        // pointer (where they're working), not always the primary display.
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
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
        HStack(spacing: 8) {
            switch appState.status {
            case .recording:
                EqualizerBars(level: appState.audioLevel)
                Text("Listening…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                if appState.isHandsFree {
                    // Hands-free lock engaged: recording continues until a
                    // single tap of the hold key.
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
            case .transcribing, .injecting:
                ProcessingDots()
                Text("Transcribing…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 150, height: 34)
        .background(MonoGlass())
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

/// Near-black frosted glass with a faint white sheen — strictly monochrome.
private struct MonoGlass: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.72)
            LinearGradient(
                colors: [Color.white.opacity(0.08), .clear],
                startPoint: .top, endPoint: .center
            )
        }
    }
}

/// Equalizer-style music bars: rounded vertical bars bouncing up and down,
/// each on its own rhythm, driven louder by the mic level.
private struct EqualizerBars: View {
    let level: Float
    private let barCount = 6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    // Two offset sines per bar so neighbours never sync up.
                    let phase = Double(i) * 0.9
                    let bounce = 0.30
                        + 0.50 * abs(sin(time * 3.6 + phase))
                        + 0.20 * abs(sin(time * 2.1 + phase * 1.7))
                    let drive = 0.35 + min(CGFloat(level) * 10, 1) * 0.65
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.55)],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .frame(width: 3, height: max(4, 18 * bounce * drive))
                }
            }
            .frame(width: 30, height: 20)
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
                        .fill(.white)
                        .frame(width: 5, height: 5)
                        .opacity(0.35 + 0.65 * pulse)
                        .shadow(color: .white.opacity(0.6 * pulse), radius: 3)
                        .scaleEffect(0.85 + 0.3 * pulse)
                }
            }
        }
    }
}
