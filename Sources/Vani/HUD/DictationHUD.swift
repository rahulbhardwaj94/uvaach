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
    /// Compact while listening; grows wider to fit the live preview line.
    private static let compactSize = NSSize(width: 246, height: 46)
    private static let previewSize = NSSize(width: 360, height: 50)

    func show() {
        if panel == nil {
            let hosting = NSHostingView(rootView: HUDView())
            let p = NSPanel(
                contentRect: NSRect(origin: .zero, size: Self.compactSize),
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
        panel?.setContentSize(Self.compactSize)
        position()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel?.animator().alphaValue = 1
        }
    }

    /// Grow the pill to fit the live preview line, or shrink it back. Keeps
    /// the pill horizontally centered on screen as it resizes.
    func setPreviewing(_ previewing: Bool) {
        guard let panel else { return }
        let target = previewing ? Self.previewSize : Self.compactSize
        guard panel.frame.size != target else { return }
        var frame = panel.frame
        frame.origin.x -= (target.width - frame.width) / 2
        frame.size = target
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().setFrame(frame, display: true)
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
        HStack(spacing: 12) {
            switch appState.status {
            case .recording:
                HaloMic()
                if let preview = appState.previewTranscript, !preview.isEmpty {
                    // Live partial (behind FeatureFlags.streamingPreview):
                    // most recent words, dimmed to read as provisional.
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    EqualizerBars(level: appState.audioLevel)
                }
                if let startedAt = appState.recordingStartedAt {
                    ElapsedBadge(since: startedAt)
                }
                if appState.isHandsFree {
                    // Hands-free lock engaged: recording continues until a
                    // single tap of the hold key.
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
            case .transcribing, .injecting:
                Spinner()
                Text("Transcribing…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MonoGlass())
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .padding(3)
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
    private let barCount = 20

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    // Two offset sines per bar so neighbours never sync up.
                    let phase = Double(i) * 0.9
                    let bounce = 0.22
                        + 0.58 * abs(sin(time * 3.6 + phase))
                        + 0.20 * abs(sin(time * 2.1 + phase * 1.7))
                    let drive = 0.30 + min(CGFloat(level) * 10, 1) * 0.70
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.55)],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .frame(width: 1.6, height: max(3, 34 * bounce * drive))
                }
            }
            .frame(width: 81, height: 34)
        }
    }
}

/// Mic icon with a soft white halo breathing behind it — a peripheral
/// "capture is alive" cue that stays within the HUD's monochrome language.
private struct HaloMic: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let breath = 0.5 + 0.5 * sin(time * 2.2)
            ZStack {
                // Halo stays inside its 24 pt slot (blur included) so the
                // gap to the bars never visibly shrinks as it breathes.
                Circle()
                    .fill(.white.opacity(0.10 + 0.14 * breath))
                    .frame(width: 16 + 3 * breath, height: 16 + 3 * breath)
                    .blur(radius: 3)
                Image(systemName: "mic.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 24, height: 24)
        }
    }
}

/// Elapsed recording time in a hairline capsule ("0:07"), led by a slowly
/// pulsing red REC dot — the HUD's single drop of color. Reassures during
/// long hands-free sessions that capture is still running.
private struct ElapsedBadge: View {
    let since: Date

    var body: some View {
        HStack(spacing: 5) {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let pulse = 0.5 + 0.5 * sin(time * 2.6)
                Circle()
                    .fill(Color(red: 0.91, green: 0.30, blue: 0.29)
                        .opacity(0.40 + 0.60 * pulse))
                    .frame(width: 6, height: 6)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(context.date.timeIntervalSince(since)))
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}

/// Rotating three-quarter arc over a faint full-circle track.
private struct Spinner: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 0.9) / 0.9
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .padding(1)
                    .rotationEffect(.degrees(turn * 360))
            }
            .frame(width: 14, height: 14)
        }
    }
}
