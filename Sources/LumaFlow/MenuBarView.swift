import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var service: DisplayService
    @Environment(\.openWindow) private var openWindow
    @State private var resolutionPercent = 100.0
    @State private var modeIndex = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text("LumaFlow").font(.headline)
                Spacer()
                Text("\(service.displays.count) 台显示器")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let display = service.selectedDisplay {
                Picker("显示器", selection: $service.selectedDisplayID) {
                    ForEach(service.displays) { Text($0.name).tag(Optional($0.id)) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label("分辨率", systemImage: "rectangle.arrowtriangle.2.outward")
                        Spacer()
                        Text("\(Int(resolutionPercent.rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    if !display.resolutionModes.isEmpty {
                        if display.hasThreePercentCoverage {
                            Slider(
                                value: Binding(
                                    get: { resolutionPercent },
                                    set: {
                                        resolutionPercent = $0
                                        if let mode = display.closestMode(to: $0) {
                                            service.schedulePreview(mode)
                                        }
                                    }
                                ),
                                in: display.percentRange,
                                step: 3
                            )
                        } else {
                            Slider(
                                value: Binding(
                                    get: { modeIndex },
                                    set: {
                                        modeIndex = $0
                                        let index = Int($0.rounded())
                                        guard display.resolutionModes.indices.contains(index) else {
                                            return
                                        }
                                        let mode = display.resolutionModes[index]
                                        resolutionPercent = Double(display.scalePercent(for: mode))
                                        service.schedulePreview(mode)
                                    }
                                ),
                                in: 0...Double(max(0, display.resolutionModes.count - 1)),
                                step: 1
                            )
                        }
                        HStack {
                            Text(display.currentMode?.title ?? "未知")
                            Spacer()
                            Text("\(Int(display.targetRefreshRate.rounded())) Hz")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                if let pending = service.pendingChange,
                   pending.displayID == display.id {
                    HStack {
                        Text("\(service.confirmationSeconds) 秒后恢复")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("恢复") { service.revertMode() }
                        Button("保留") { service.keepMode() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                Divider()
                HStack {
                    Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                    Slider(
                        value: Binding(
                            get: { service.softwareBrightness },
                            set: {
                                service.softwareBrightness = $0
                                service.updateImageControls()
                            }
                        ),
                        in: 0.05...1
                    )
                    Text("\(Int(service.softwareBrightness * 100))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            Divider()
            HStack {
                Button("打开主窗口") { showMainWindow() }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { syncResolution() }
        .onChange(of: service.selectedDisplayID) {
            service.loadControlsForSelectedDisplay()
            syncResolution()
        }
        .onChange(of: service.displays.map(\.currentModeID)) { syncResolution() }
    }

    private func syncResolution() {
        guard let display = service.selectedDisplay,
              let index = display.resolutionModes.firstIndex(where: {
                  $0.id == display.currentModeID
              }) else { return }
        modeIndex = Double(index)
        resolutionPercent = Double(display.scalePercent(for: display.resolutionModes[index]))
    }

    private func showMainWindow() {
        openWindow(id: "main")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: {
                $0.canBecomeMain && !($0 is NSPanel)
            }) {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
}
