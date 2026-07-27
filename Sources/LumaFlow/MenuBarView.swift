import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var service: DisplayService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "display.2")
                    .foregroundStyle(.blue)
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
                Text("常用分辨率").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(display.resolutionModes.filter { service.favorites.contains($0.id) }.prefix(6))) { mode in
                    Button {
                        service.apply(mode)
                    } label: {
                        HStack {
                            Text("\(display.scalePercent(for: mode))%")
                            Spacer()
                            Text(mode.title).foregroundStyle(.secondary)
                            if mode.id == display.currentModeID { Image(systemName: "checkmark") }
                        }
                    }
                }
                if !display.resolutionModes.contains(where: { service.favorites.contains($0.id) }) {
                    Text("在主窗口点亮星标后，可在这里快速切换。")
                        .font(.caption).foregroundStyle(.secondary)
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
                Button("打开主窗口") { NSApp.activate(ignoringOtherApps: true) }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 330)
        .onChange(of: service.selectedDisplayID) {
            service.loadControlsForSelectedDisplay()
        }
    }
}
