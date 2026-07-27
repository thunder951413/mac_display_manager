import AppKit
import CoreGraphics
import SwiftUI

private let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { _, _, userInfo in
    guard let userInfo else { return }
    let service = Unmanaged<DisplayService>.fromOpaque(userInfo).takeUnretainedValue()
    Task { @MainActor in service.refresh() }
}

final class DisplayModeOption: Identifiable, Hashable {
    let mode: CGDisplayMode
    let id: String
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let isHiDPI: Bool

    init(_ mode: CGDisplayMode) {
        self.mode = mode
        width = mode.width
        height = mode.height
        pixelWidth = mode.pixelWidth
        pixelHeight = mode.pixelHeight
        refreshRate = mode.refreshRate
        isHiDPI = mode.pixelWidth >= mode.width * 2
        id = "\(width)x\(height)@\(Int(refreshRate.rounded()))-\(pixelWidth)x\(pixelHeight)"
    }

    var title: String { "\(width) × \(height)" }
    var subtitle: String {
        let rate = refreshRate > 0 ? "\(Int(refreshRate.rounded())) Hz" : "可变刷新率"
        return isHiDPI ? "HiDPI · \(rate)" : rate
    }

    static func == (lhs: DisplayModeOption, rhs: DisplayModeOption) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum ResolutionPolicy {
    static let aspectTolerance = 0.002

    static func aspectMatches(
        width: Int,
        height: Int,
        nativeWidth: Int,
        nativeHeight: Int
    ) -> Bool {
        guard height > 0, nativeWidth > 0, nativeHeight > 0 else { return false }
        let aspect = Double(width) / Double(height)
        let nativeAspect = Double(nativeWidth) / Double(nativeHeight)
        return abs(aspect / nativeAspect - 1) <= aspectTolerance
    }

    static func matches(
        width: Int,
        height: Int,
        refreshRate: Double,
        targetRefreshRate: Double,
        nativeWidth: Int,
        nativeHeight: Int
    ) -> Bool {
        let refreshMatches = abs(refreshRate - targetRefreshRate) < 0.6
        return refreshMatches && aspectMatches(
            width: width,
            height: height,
            nativeWidth: nativeWidth,
            nativeHeight: nativeHeight
        )
    }
}

struct DisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    let isMain: Bool
    let bounds: CGRect
    let rotation: Double
    let modes: [DisplayModeOption]
    let currentModeID: String
    let nativeWidth: Int
    let nativeHeight: Int
    let defaultWidth: Int
    let defaultHeight: Int
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32
    let targetRefreshRate: Double

    var currentMode: DisplayModeOption? { modes.first { $0.id == currentModeID } }
    var stableKey: String {
        let identity = serialNumber > 0 ? String(serialNumber) : name
        return "\(vendorID)-\(productID)-\(identity)"
    }

    var resolutionModes: [DisplayModeOption] {
        let matching = modes.filter {
            ResolutionPolicy.matches(
                width: $0.width,
                height: $0.height,
                refreshRate: $0.refreshRate,
                targetRefreshRate: targetRefreshRate,
                nativeWidth: nativeWidth,
                nativeHeight: nativeHeight
            )
        }
        return Dictionary(grouping: matching, by: { "\($0.width)x\($0.height)" })
            .compactMap { _, candidates in
                candidates.max {
                    if $0.isHiDPI != $1.isHiDPI { return !$0.isHiDPI }
                    return $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight
                }
            }
            .sorted { ($0.width, $0.height) < ($1.width, $1.height) }
    }

    func scalePercent(for mode: DisplayModeOption) -> Int {
        guard defaultWidth > 0 else { return 100 }
        return Int((Double(mode.width) / Double(defaultWidth) * 100).rounded())
    }

    func steppedPercent(for mode: DisplayModeOption) -> Int {
        let raw = scalePercent(for: mode)
        return 100 + Int((Double(raw - 100) / 3).rounded()) * 3
    }

    var percentRange: ClosedRange<Double> {
        let percentages = resolutionModes.map(steppedPercent)
        guard let minimum = percentages.min(), let maximum = percentages.max() else {
            return 100...100
        }
        return Double(minimum)...Double(maximum)
    }

    func closestMode(to percent: Double) -> DisplayModeOption? {
        resolutionModes.min {
            abs(Double(scalePercent(for: $0)) - percent) <
            abs(Double(scalePercent(for: $1)) - percent)
        }
    }

    var hasThreePercentCoverage: Bool {
        let range = percentRange
        let targets = stride(
            from: Int(range.lowerBound),
            through: Int(range.upperBound),
            by: 3
        )
        return targets.allSatisfy { target in
            resolutionModes.contains {
                abs(scalePercent(for: $0) - target) <= 1
            }
        }
    }

    var presentationModes: [DisplayModeOption] {
        guard hasThreePercentCoverage else { return resolutionModes }
        var seen = Set<String>()
        return stride(
            from: Int(percentRange.lowerBound),
            through: Int(percentRange.upperBound),
            by: 3
        ).compactMap { target in
            guard let mode = closestMode(to: Double(target)),
                  seen.insert(mode.id).inserted else { return nil }
            return mode
        }
    }
}

struct PendingModeChange: Identifiable {
    let id = UUID()
    let displayID: CGDirectDisplayID
    let previous: CGDisplayMode
    let selected: DisplayModeOption
}

@MainActor
final class DisplayService: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var softwareBrightness: Double = 1
    @Published var contrast: Double = 1
    @Published var warmth: Double = 0
    @Published var favorites: Set<String> = []
    @Published var pendingChange: PendingModeChange?
    @Published var confirmationSeconds = 15
    @Published var statusMessage: String?
    @Published var flexibleScalingBusy = false
    @Published var flexibleScalingManaged = UserDefaults.standard.bool(forKey: "flexibleScalingManaged")
    @Published var restartRequired = false
    @Published var brightnessKeyPermissionGranted = false
    @Published private(set) var brightnessKeyFeedback: String?
    @Published var controlFocusedDisplayWithBrightnessKeys = UserDefaults.standard.object(
        forKey: "controlFocusedDisplayWithBrightnessKeys"
    ) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(
                controlFocusedDisplayWithBrightnessKeys,
                forKey: "controlFocusedDisplayWithBrightnessKeys"
            )
        }
    }

    private var previewTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var brightnessKeyMonitor: BrightnessKeyMonitor?
    private var knownDisplayKeys = Set<String>()
    private let settingsStore = DisplaySettingsStore.shared
    private let hardwareController = DisplayHardwareController()

    init() {
        refresh()
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favoriteModes") ?? [])
        CGDisplayRegisterReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        brightnessKeyMonitor = BrightnessKeyMonitor { [weak self] event in
            Task { @MainActor in self?.handleBrightnessKey(event) }
        }
        brightnessKeyPermissionGranted = brightnessKeyMonitor?.start() == true
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    var selectedDisplay: DisplayInfo? {
        guard let selectedDisplayID else { return displays.first }
        return displays.first { $0.id == selectedDisplayID }
    }

    func refresh() {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = Array(repeating: CGDirectDisplayID(), count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)

        let names = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen.localizedName)
        })

        displays = ids.map { id in
            let current = CGDisplayCopyDisplayMode(id)
            let all = (CGDisplayCopyAllDisplayModes(id, [
                kCGDisplayShowDuplicateLowResolutionModes: true
            ] as CFDictionary) as? [CGDisplayMode]) ?? []
            let unique = Dictionary(grouping: all.map(DisplayModeOption.init), by: \.id)
                .compactMap { $0.value.first }
                .sorted {
                    if $0.width != $1.width { return $0.width < $1.width }
                    if $0.height != $1.height { return $0.height < $1.height }
                    return $0.refreshRate < $1.refreshRate
                }
            let currentID = current.map { DisplayModeOption($0).id } ?? ""
            let nativeFlag: UInt32 = 0x02000000 // kDisplayModeNativeFlag
            let defaultFlag: UInt32 = 0x00000004 // kDisplayModeDefaultFlag
            let nativeModes = all.filter { $0.ioFlags & nativeFlag != 0 }
            let native = (nativeModes.isEmpty ? all : nativeModes).max {
                $0.width * $0.height < $1.width * $1.height
            }
            let nativeWidth = native?.width ?? current?.pixelWidth ?? 0
            let nativeHeight = native?.height ?? current?.pixelHeight ?? 0
            let nativeAspectModes = all.filter {
                ResolutionPolicy.aspectMatches(
                    width: $0.width,
                    height: $0.height,
                    nativeWidth: nativeWidth,
                    nativeHeight: nativeHeight
                )
            }
            let targetRefreshRate = nativeAspectModes
                .map(\.refreshRate)
                .filter { $0 > 1 }
                .max() ?? current?.refreshRate ?? 60
            let defaultModes = all.filter { $0.ioFlags & defaultFlag != 0 }
            let defaultMode = defaultModes.first {
                abs($0.refreshRate - targetRefreshRate) < 0.6
            } ?? defaultModes.first ?? current
            return DisplayInfo(
                id: id,
                name: names[id] ?? "显示器 \(id)",
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                bounds: CGDisplayBounds(id),
                rotation: CGDisplayRotation(id),
                modes: unique,
                currentModeID: currentID,
                nativeWidth: nativeWidth,
                nativeHeight: nativeHeight,
                defaultWidth: defaultMode?.width ?? current?.width ?? 0,
                defaultHeight: defaultMode?.height ?? current?.height ?? 0,
                vendorID: CGDisplayVendorNumber(id),
                productID: CGDisplayModelNumber(id),
                serialNumber: CGDisplaySerialNumber(id),
                targetRefreshRate: targetRefreshRate
            )
        }.sorted { ($0.isMain ? 0 : 1, $0.name) < ($1.isMain ? 0 : 1, $1.name) }

        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = displays.first?.id
        }
        hardwareController.refresh(displays: displays)
        let currentKeys = Set(displays.map(\.stableKey))
        let newlyConnected = currentKeys.subtracting(knownDisplayKeys)
        knownDisplayKeys = currentKeys
        loadControlsForSelectedDisplay()
        let restoreTargets = displays.filter { newlyConnected.contains($0.stableKey) }
        if !restoreTargets.isEmpty {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                guard let self else { return }
                for display in restoreTargets {
                    self.restoreSavedSettings(for: display)
                }
            }
        }
    }

    func schedulePreview(_ mode: DisplayModeOption) {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.apply(mode)
        }
    }

    func apply(_ mode: DisplayModeOption) {
        guard let display = selectedDisplay,
              mode.id != display.currentModeID,
              let previous = CGDisplayCopyDisplayMode(display.id) else { return }

        let result = switchMode(displayID: display.id, mode: mode.mode)
        guard result == .success else {
            statusMessage = "无法切换到 \(mode.title)（错误 \(result.rawValue)）"
            return
        }

        pendingChange = PendingModeChange(displayID: display.id, previous: previous, selected: mode)
        confirmationSeconds = 15
        startCountdown()
        refresh()
    }

    func keepMode() {
        countdownTask?.cancel()
        if let pendingChange,
           let display = displays.first(where: { $0.id == pendingChange.displayID }) {
            saveMode(pendingChange.selected, for: display)
        }
        pendingChange = nil
        statusMessage = "已保留新的分辨率"
    }

    func revertMode() {
        guard let pendingChange else { return }
        countdownTask?.cancel()
        _ = switchMode(displayID: pendingChange.displayID, mode: pendingChange.previous)
        self.pendingChange = nil
        statusMessage = "已恢复原分辨率"
        refresh()
    }

    private func switchMode(displayID: CGDirectDisplayID, mode: CGDisplayMode) -> CGError {
        var token = CGDisplayFadeReservationToken()
        let reserved = CGAcquireDisplayFadeReservation(2, &token) == .success
        if reserved {
            CGDisplayFade(
                token, 0.12,
                CGDisplayBlendFraction(kCGDisplayBlendNormal),
                CGDisplayBlendFraction(kCGDisplayBlendSolidColor),
                0, 0, 0, 1
            )
        }

        var config: CGDisplayConfigRef?
        var result = CGBeginDisplayConfiguration(&config)
        if result == .success, let config {
            result = CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
            if result == .success {
                result = CGCompleteDisplayConfiguration(config, .permanently)
            } else {
                CGCancelDisplayConfiguration(config)
            }
        }

        if reserved {
            CGDisplayFade(
                token, 0.22,
                CGDisplayBlendFraction(kCGDisplayBlendSolidColor),
                CGDisplayBlendFraction(kCGDisplayBlendNormal),
                0, 0, 0, 0
            )
            CGReleaseDisplayFadeReservation(token)
        }
        return result
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for remaining in stride(from: 15, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                self?.confirmationSeconds = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            self?.revertMode()
        }
    }

    func toggleFavorite(_ mode: DisplayModeOption) {
        if favorites.contains(mode.id) { favorites.remove(mode.id) }
        else { favorites.insert(mode.id) }
        UserDefaults.standard.set(Array(favorites), forKey: "favoriteModes")
    }

    func updateImageControls() {
        guard let display = selectedDisplay else { return }
        var settings = settingsStore.settings(for: display.stableKey)
        settings.brightness = softwareBrightness
        settings.contrast = contrast
        settings.warmth = warmth
        settingsStore.save(settings, for: display.stableKey)
        applyControls(settings, to: display)
    }

    private func applyControls(_ settings: SavedDisplaySettings, to display: DisplayInfo) {
        let hardwareBrightness = hardwareController.supportsHardwareBrightness(display)
        if hardwareBrightness {
            hardwareController.setBrightness(settings.brightness, for: display)
        }
        applyGamma(
            displayID: display.id,
            brightness: hardwareBrightness ? 1 : settings.brightness,
            contrast: settings.contrast,
            warmth: settings.warmth
        )
    }

    private func applyGamma(
        displayID id: CGDirectDisplayID,
        brightness: Double,
        contrast: Double,
        warmth: Double
    ) {
        let capacity = max(256, Int(CGDisplayGammaTableCapacity(id)))
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = red
        var blue = red
        let gamma = 1 / max(0.5, min(1.5, contrast))
        let warm = max(-1, min(1, warmth))
        let redScale = warm >= 0 ? 1 : 1 + warm * 0.18
        let blueScale = warm <= 0 ? 1 : 1 - warm * 0.24
        let greenScale = 1 - abs(warm) * 0.05
        for index in 0..<capacity {
            let x = Double(index) / Double(capacity - 1)
            let value = pow(x, gamma) * brightness
            red[index] = CGGammaValue(min(1, value * redScale))
            green[index] = CGGammaValue(min(1, value * greenScale))
            blue[index] = CGGammaValue(min(1, value * blueScale))
        }
        CGSetDisplayTransferByTable(id, UInt32(capacity), &red, &green, &blue)
    }

    func resetImageControls() {
        guard let display = selectedDisplay else { return }
        softwareBrightness = 1
        contrast = 1
        warmth = 0
        var settings = settingsStore.settings(for: display.stableKey)
        settings.brightness = 1
        settings.contrast = 1
        settings.warmth = 0
        settingsStore.save(settings, for: display.stableKey)
        CGDisplayRestoreColorSyncSettings()
        applyControls(settings, to: display)
        statusMessage = "已恢复系统色彩参数"
    }

    func loadControlsForSelectedDisplay() {
        guard let display = selectedDisplay else { return }
        let settings = settingsStore.settings(for: display.stableKey)
        softwareBrightness = settings.brightness
        contrast = settings.contrast
        warmth = settings.warmth
    }

    func usesHardwareBrightness(_ display: DisplayInfo) -> Bool {
        hardwareController.supportsHardwareBrightness(display)
    }

    private func saveMode(_ mode: DisplayModeOption, for display: DisplayInfo) {
        var settings = settingsStore.settings(for: display.stableKey)
        settings.modeWidth = mode.width
        settings.modeHeight = mode.height
        settings.refreshRate = mode.refreshRate
        settingsStore.save(settings, for: display.stableKey)
    }

    private func restoreSavedSettings(for display: DisplayInfo) {
        guard let settings = settingsStore.savedSettings(for: display.stableKey) else {
            return
        }
        applyControls(settings, to: display)
        guard let width = settings.modeWidth,
              let height = settings.modeHeight,
              let savedMode = display.resolutionModes.min(by: {
                  let lhs = abs($0.width - width) + abs($0.height - height)
                  let rhs = abs($1.width - width) + abs($1.height - height)
                  return lhs < rhs
              }),
              savedMode.id != display.currentModeID else { return }
        _ = switchMode(displayID: display.id, mode: savedMode.mode)
    }

    func requestBrightnessKeyPermission() {
        brightnessKeyPermissionGranted = brightnessKeyMonitor?.start(prompt: true) == true
        if !brightnessKeyPermissionGranted {
            statusMessage = "请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 LumaFlow，然后重新打开应用。"
        }
    }

    func refreshBrightnessKeyPermission() {
        let trusted = BrightnessKeyMonitor.hasAccessibilityPermission(prompt: false)
        if trusted, !brightnessKeyPermissionGranted {
            brightnessKeyPermissionGranted = brightnessKeyMonitor?.start() == true
        } else if !trusted {
            brightnessKeyMonitor?.stop()
            brightnessKeyPermissionGranted = false
        }
    }

    private func handleBrightnessKey(_ event: NSEvent) {
        guard controlFocusedDisplayWithBrightnessKeys, event.subtype.rawValue == 8 else { return }
        guard let action = BrightnessKeyAction.decode(
            data1: event.data1,
            modifierFlags: event.modifierFlags
        ) else { return }
        switch action {
        case .increase(let fine):
            adjustBrightnessForFocusedDisplay(by: fine ? 0.01 : 0.0625)
        case .decrease(let fine):
            adjustBrightnessForFocusedDisplay(by: fine ? -0.01 : -0.0625)
        }
    }

    private func adjustBrightnessForFocusedDisplay(by delta: Double) {
        guard let display = focusedDisplay() ?? selectedDisplay else { return }
        var settings = settingsStore.settings(for: display.stableKey)
        settings.brightness = min(max(settings.brightness + delta, 0.05), 1)
        settingsStore.save(settings, for: display.stableKey)
        applyControls(settings, to: display)
        if display.id == selectedDisplayID {
            softwareBrightness = settings.brightness
        }
        brightnessKeyFeedback = "\(display.name) · \(Int((settings.brightness * 100).rounded()))%"
    }

    private func focusedDisplay() -> DisplayInfo? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windowInfo = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]] else { return nil }

        for window in windowInfo {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let values = window[kCGWindowBounds as String] as? [String: Any],
                  let x = (values["X"] as? NSNumber)?.doubleValue,
                  let y = (values["Y"] as? NSNumber)?.doubleValue,
                  let width = (values["Width"] as? NSNumber)?.doubleValue,
                  let height = (values["Height"] as? NSNumber)?.doubleValue,
                  case let bounds = CGRect(x: x, y: y, width: width, height: height),
                  bounds.width > 80,
                  bounds.height > 60 else { continue }
            let point = CGPoint(x: bounds.midX, y: bounds.midY)
            if let display = displays.first(where: { CGDisplayBounds($0.id).contains(point) }) {
                return display
            }
        }
        return nil
    }

    func installFlexibleScaling() {
        guard let display = selectedDisplay else { return }
        flexibleScalingBusy = true
        let request = FlexibleScalingInstaller.InstallRequest(display: display)
        Task {
            let result = await Task.detached {
                FlexibleScalingInstaller.install(request)
            }.value
            flexibleScalingBusy = false
            switch result {
            case .success:
                flexibleScalingManaged = true
                restartRequired = true
                UserDefaults.standard.set(true, forKey: "flexibleScalingManaged")
                statusMessage = "3% 灵活缩放配置已安装。重启 Mac 后生效。"
            case .failure(let error):
                statusMessage = error.localizedDescription
            }
        }
    }

    func removeFlexibleScaling() {
        guard let display = selectedDisplay else { return }
        flexibleScalingBusy = true
        let request = FlexibleScalingInstaller.InstallRequest(display: display)
        Task {
            let result = await Task.detached {
                FlexibleScalingInstaller.uninstall(request)
            }.value
            flexibleScalingBusy = false
            switch result {
            case .success:
                flexibleScalingManaged = false
                restartRequired = true
                UserDefaults.standard.set(false, forKey: "flexibleScalingManaged")
                statusMessage = "已恢复安装前的显示器配置。重启 Mac 后生效。"
            case .failure(let error):
                statusMessage = error.localizedDescription
            }
        }
    }
}
