import SwiftUI

@main
struct LumaFlowApp: App {
    @StateObject private var displays = DisplayService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(displays)
                .frame(minWidth: 980, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("显示器") {
                Button("重新检测显示器") { displays.refresh() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("恢复色彩参数") { displays.resetImageControls() }
                    .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }

        MenuBarExtra("LumaFlow", systemImage: "display.2") {
            MenuBarView()
                .environmentObject(displays)
        }
        .menuBarExtraStyle(.window)
    }
}
