import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var service: DisplayService
    @State private var resolutionPercent = 100.0
    @State private var modeIndex = 0.0
    @State private var confirmFlexibleScalingInstall = false
    @State private var confirmFlexibleScalingRemoval = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let display = service.selectedDisplay {
                ScrollView {
                    VStack(spacing: 22) {
                        hero(display)
                        resolutionPanel(display)
                        controlsPanel
                    }
                    .padding(28)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .safeAreaInset(edge: .bottom) {
                    if let pending = service.pendingChange { confirmationBar(pending) }
                }
            } else {
                ContentUnavailableView("没有检测到显示器", systemImage: "display.trianglebadge.exclamationmark")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            syncModeIndex()
            service.refreshBrightnessKeyPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            service.refreshBrightnessKeyPermission()
        }
        .onChange(of: service.selectedDisplayID) {
            service.loadControlsForSelectedDisplay()
            syncModeIndex()
        }
        .onChange(of: service.displays.map(\.currentModeID)) { syncModeIndex() }
        .alert("LumaFlow", isPresented: Binding(
            get: { service.statusMessage != nil },
            set: { if !$0 { service.statusMessage = nil } }
        )) {
            Button("好") { service.statusMessage = nil }
        } message: {
            Text(service.statusMessage ?? "")
        }
        .alert("启用 3% 灵活缩放？", isPresented: $confirmFlexibleScalingInstall) {
            Button("取消", role: .cancel) { }
            Button("继续并授权") { service.installFlexibleScaling() }
        } message: {
            Text("将合并写入所选显示器的系统配置，并在首次修改前保存备份。macOS 会要求管理员密码，重启后生效。同型号显示器都会受到影响。")
        }
        .alert("恢复原显示器配置？", isPresented: $confirmFlexibleScalingRemoval) {
            Button("取消", role: .cancel) { }
            Button("恢复并授权", role: .destructive) { service.removeFlexibleScaling() }
        } message: {
            Text("将恢复 LumaFlow 安装前保存的配置；如果原来没有配置文件，则移除 LumaFlow 创建的文件。重启后生效。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(.blue.gradient)
                    Image(systemName: "display.2")
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LumaFlow").font(.headline)
                    Text("显示，由你掌控").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(18)

            Text("显示器")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 8)

            ForEach(service.displays) { display in
                Button {
                    service.selectedDisplayID = display.id
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                            .font(.title3)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(display.name).lineLimit(1)
                            Text(display.currentMode?.title ?? "未知分辨率")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if display.isMain {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .background(service.selectedDisplayID == display.id ? Color.accentColor.opacity(0.13) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            Spacer()
            Button {
                service.refresh()
            } label: {
                Label("重新检测", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 280)
        .background(.ultraThinMaterial)
    }

    private func hero(_ display: DisplayInfo) -> some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [.blue.opacity(0.85), .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 112, height: 74)
                    .shadow(color: .blue.opacity(0.25), radius: 16, y: 8)
                Text(display.currentMode.map { "\($0.width)\n× \($0.height)" } ?? "—")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(display.name).font(.largeTitle.weight(.bold))
                    if display.isBuiltIn { badge("内建", color: .blue) }
                    if display.isMain { badge("主显示器", color: .orange) }
                }
                Text("\(Int(display.bounds.width)) × \(Int(display.bounds.height)) 点 · 旋转 \(Int(display.rotation))° · Display ID \(display.id)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
            Text("已连接").foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func resolutionPanel(_ display: DisplayInfo) -> some View {
        let modes = display.resolutionModes
        return panel {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    sectionTitle("分辨率", icon: "rectangle.arrowtriangle.2.outward")
                    Spacer()
                    Label(
                        display.hasThreePercentCoverage
                            ? "默认 100% · 每档 3% · \(Int(display.targetRefreshRate.rounded())) Hz"
                            : "系统可用档位 · \(Int(display.targetRefreshRate.rounded())) Hz",
                        systemImage: display.hasThreePercentCoverage
                            ? "checkmark.seal.fill"
                            : "exclamationmark.triangle.fill"
                    )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(display.hasThreePercentCoverage ? .green : .orange)
                }

                if !modes.isEmpty {
                    VStack(spacing: 10) {
                        if display.hasThreePercentCoverage {
                            Slider(value: Binding(
                                get: { resolutionPercent },
                                set: {
                                    resolutionPercent = $0
                                    if let mode = display.closestMode(to: $0) {
                                        service.schedulePreview(mode)
                                    }
                                }
                            ), in: display.percentRange, step: 3)
                        } else {
                            Slider(value: Binding(
                                get: { modeIndex },
                                set: {
                                    modeIndex = $0
                                    let index = Int($0.rounded())
                                    guard modes.indices.contains(index) else { return }
                                    resolutionPercent = Double(display.scalePercent(for: modes[index]))
                                    service.schedulePreview(modes[index])
                                }
                            ), in: 0...Double(max(0, modes.count - 1)), step: 1)
                        }
                        HStack {
                            Text(modes.first.map { "\(display.scalePercent(for: $0))%" } ?? "")
                            Spacer()
                            VStack(spacing: 2) {
                                Text("\(Int(resolutionPercent))%")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let mode = display.closestMode(to: resolutionPercent) {
                                    Text("实际 \(mode.title)")
                                        .font(.caption2)
                                }
                            }
                            Spacer()
                            Text(modes.last.map { "\(display.scalePercent(for: $0))%" } ?? "")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(Color.primary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    if !display.hasThreePercentCoverage {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                "系统目前只提供 \(modes.count) 个有效档位。安装精细 HiDPI 模式并重启后，每个 3% 刻度才会真正改变分辨率。",
                                systemImage: "info.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            HStack {
                                Button {
                                    confirmFlexibleScalingInstall = true
                                } label: {
                                    if service.flexibleScalingBusy {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Label("一键启用 3% 灵活缩放", systemImage: "wand.and.stars")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(service.flexibleScalingBusy)

                                if service.flexibleScalingManaged {
                                    Button("恢复安装前配置", role: .destructive) {
                                        confirmFlexibleScalingRemoval = true
                                    }
                                    .disabled(service.flexibleScalingBusy)
                                }

                                if service.restartRequired {
                                    Label("等待重启", systemImage: "restart")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    ContentUnavailableView(
                        "没有符合条件的模式",
                        systemImage: "display.trianglebadge.exclamationmark",
                        description: Text("该显示器没有提供原生宽高比、\(Int(display.targetRefreshRate.rounded())) Hz 的分辨率。")
                    )
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(display.presentationModes) { mode in
                        modeCard(mode, display: display, current: mode.id == display.currentModeID)
                    }
                }
            }
        }
    }

    private var controlsPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    sectionTitle("画面控制", icon: "slider.horizontal.3")
                    Spacer()
                    Button("恢复默认") { service.resetImageControls() }
                }
                controlRow("亮度", icon: "sun.max.fill", value: $service.softwareBrightness, range: 0.2...1, tint: .orange)
                controlRow("对比度", icon: "circle.lefthalf.filled", value: $service.contrast, range: 0.5...1.5, tint: .blue)
                controlRow("色温", icon: "thermometer.medium", value: $service.warmth, range: -1...1, tint: .pink, valueLabel: temperatureLabel)
                Divider()
                HStack {
                    Label(
                        service.selectedDisplay.map(service.usesHardwareBrightness) == true
                            ? "硬件亮度 · 色彩软件调节"
                            : "软件亮度与色彩调节",
                        systemImage: service.selectedDisplay.map(service.usesHardwareBrightness) == true
                            ? "display.and.arrow.down"
                            : "circle.lefthalf.filled"
                    )
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle(
                        "键盘亮度键调节焦点显示器",
                        isOn: $service.controlFocusedDisplayWithBrightnessKeys
                    )
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    if !service.brightnessKeyPermissionGranted {
                        Button("授权键盘控制") {
                            service.requestBrightnessKeyPermission()
                        }
                        .controlSize(.small)
                    }
                    Text(
                        service.brightnessKeyPermissionGranted
                            ? (service.brightnessKeyFeedback ?? "键盘控制已就绪")
                            : "需要辅助功能授权"
                    )
                        .font(.caption)
                        .foregroundStyle(
                            service.brightnessKeyPermissionGranted
                                ? Color.secondary
                                : Color.orange
                        )
                }
            }
        }
    }

    private func controlRow(_ title: String, icon: String, value: Binding<Double>, range: ClosedRange<Double>, tint: Color, valueLabel: ((Double) -> String)? = nil) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.title3)
                .frame(width: 24)
            Text(title).frame(width: 58, alignment: .leading)
            Slider(value: value, in: range)
                .tint(tint)
                .onChange(of: value.wrappedValue) { service.updateImageControls() }
            Text(valueLabel?(value.wrappedValue) ?? "\(Int(value.wrappedValue * 100))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private func modeCard(_ mode: DisplayModeOption, display: DisplayInfo, current: Bool) -> some View {
        Button {
            service.apply(mode)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(display.scalePercent(for: mode))%").font(.headline)
                    Text("\(mode.title) · \(Int(mode.refreshRate.rounded())) Hz\(mode.isHiDPI ? " · HiDPI" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    service.toggleFavorite(mode)
                } label: {
                    Image(systemName: service.favorites.contains(mode.id) ? "star.fill" : "star")
                        .foregroundStyle(service.favorites.contains(mode.id) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(current ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.045))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(current ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func confirmationBar(_ pending: PendingModeChange) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                if let display = service.displays.first(where: { $0.id == pending.displayID }) {
                    Text("保留 \(display.scalePercent(for: pending.selected))%？").font(.headline)
                }
                Text("\(service.confirmationSeconds) 秒后自动恢复").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("恢复") { service.revertMode() }
            Button("保留") { service.keepMode() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func syncModeIndex() {
        guard let display = service.selectedDisplay,
              let index = display.resolutionModes.firstIndex(where: { $0.id == display.currentModeID }) else { return }
        let mode = display.resolutionModes[index]
        modeIndex = Double(index)
        resolutionPercent = Double(display.scalePercent(for: mode))
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(22)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.08)) }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.title2.weight(.semibold))
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12)).clipShape(Capsule())
    }

    private func temperatureLabel(_ value: Double) -> String {
        value == 0 ? "中性" : value > 0 ? "暖 \(Int(value * 100))" : "冷 \(Int(-value * 100))"
    }
}
