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
            let size = NSSize(width: 180, height: 44)
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
                FlowingWave(level: appState.audioLevel)
            case .transcribing, .injecting:
                ProcessingDots()
                Text(appState.status == .transcribing ? "Transcribing…" : "Inserting…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 180, height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
        .tint(.blue)
    }
}

/// Continuous voice-reactive waveform: three layered sine waves drifting at
/// different speeds, their amplitude driven by the mic level and tapered at
/// the edges so the wave melts into the pill.
private struct FlowingWave: View {
    let level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let midY = size.height / 2
                // Idle breath keeps the wave alive between words.
                let amplitude = midY * (0.15 + min(CGFloat(level) * 12, 1) * 0.85)

                let layers: [(speed: Double, freq: Double, scale: CGFloat, opacity: Double)] = [
                    (2.4, 1.6, 1.0, 0.9),
                    (-1.7, 2.3, 0.6, 0.45),
                    (3.1, 3.1, 0.35, 0.25),
                ]

                for layer in layers {
                    var path = Path()
                    let steps = 64
                    for i in 0...steps {
                        let x = CGFloat(i) / CGFloat(steps)
                        // Edge taper: 0 at the ends, 1 in the middle.
                        let envelope = sin(.pi * x)
                        let angle = Double(x) * layer.freq * 2 * .pi + time * layer.speed * 2
                        let y = midY + amplitude * layer.scale * envelope * CGFloat(sin(angle))
                        let point = CGPoint(x: x * size.width, y: y)
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    canvas.stroke(
                        path,
                        with: .color(.blue.opacity(layer.opacity)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .frame(width: 130, height: 30)
    }
}

private struct ProcessingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(.tint)
                        .frame(width: 6, height: 6)
                        .opacity(0.35 + 0.65 * (0.5 + 0.5 * sin(time * 6 - Double(i) * 0.9)))
                }
            }
        }
    }
}
