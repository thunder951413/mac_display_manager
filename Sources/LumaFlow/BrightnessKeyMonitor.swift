import AppKit
import ApplicationServices

enum BrightnessKeyAction: Equatable {
    case increase(fine: Bool)
    case decrease(fine: Bool)

    static func decode(
        data1: Int,
        modifierFlags: NSEvent.ModifierFlags
    ) -> BrightnessKeyAction? {
        let keyCode = (data1 & 0xffff0000) >> 16
        let keyState = (data1 & 0x0000ff00) >> 8
        guard keyState == 0x0a || keyState == 0x0b else { return nil }
        let fine = modifierFlags.contains([.option, .shift])
        switch keyCode {
        case 2: return .increase(fine: fine)
        case 3: return .decrease(fine: fine)
        default: return nil
        }
    }
}

private let brightnessEventTapCallback: CGEventTapCallBack = {
    _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<BrightnessKeyMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        monitor.enable()
        return Unmanaged.passUnretained(event)
    }

    guard type.rawValue == NSEvent.EventType.systemDefined.rawValue,
          let nsEvent = NSEvent(cgEvent: event),
          monitor.consumeIfBrightnessKey(nsEvent) else {
        return Unmanaged.passUnretained(event)
    }
    return nil
}

final class BrightnessKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: (NSEvent) -> Void

    init(handler: @escaping (NSEvent) -> Void) {
        self.handler = handler
    }

    deinit { stop() }

    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    @discardableResult
    func start(prompt: Bool = false) -> Bool {
        stop()
        guard Self.hasAccessibilityPermission(prompt: prompt) else { return false }
        let mask = CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: brightnessEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func enable() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }

    fileprivate func consumeIfBrightnessKey(_ event: NSEvent) -> Bool {
        guard event.subtype.rawValue == 8 else { return false }
        let data = event.data1
        let keyCode = (data & 0xffff0000) >> 16
        guard let _ = BrightnessKeyAction.decode(
            data1: data,
            modifierFlags: event.modifierFlags
        ) else {
            // Swallow key-up for brightness as well so macOS does not also
            // change the built-in panel after LumaFlow handled key-down.
            return keyCode == 2 || keyCode == 3
        }
        handler(event)
        return true
    }
}
