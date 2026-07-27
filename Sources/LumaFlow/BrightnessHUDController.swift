import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class BrightnessHUDController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(value: Double, on display: DisplayInfo) {
        hideTask?.cancel()

        let hudSize = NSSize(width: 238, height: 166)
        let panel = panel ?? makePanel(size: hudSize)
        self.panel = panel
        panel.contentView = NSHostingView(
            rootView: BrightnessHUDView(
                value: min(max(value, 0), 1),
                displayName: display.name
            )
            .frame(width: hudSize.width, height: hudSize.height)
        )

        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value == display.id
        } ?? NSScreen.main
        if let frame = screen?.frame {
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - hudSize.width / 2,
                y: frame.midY - hudSize.height / 2
            ))
        }

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideTask = Task { [weak panel] in
            try? await Task.sleep(for: .milliseconds(1_150))
            guard !Task.isCancelled, let panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeInEaseOut
                )
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        return panel
    }
}

private struct BrightnessHUDView: View {
    let value: Double
    let displayName: String
    private let segmentCount = 16

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 54, weight: .medium))
                .symbolRenderingMode(.monochrome)

            HStack(spacing: 3) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            index < litSegments
                                ? Color.primary.opacity(0.9)
                                : Color.primary.opacity(0.16)
                        )
                        .frame(height: 9)
                }
            }

            HStack(spacing: 7) {
                Text(displayName)
                    .lineLimit(1)
                Text("·")
                Text("\(Int((value * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 25))
        .overlay {
            RoundedRectangle(cornerRadius: 25)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 22, y: 9)
        .padding(12)
    }

    private var litSegments: Int {
        Int((value * Double(segmentCount)).rounded(.up))
    }
}
