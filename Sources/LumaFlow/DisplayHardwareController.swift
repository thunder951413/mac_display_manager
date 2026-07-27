import CoreGraphics
import Darwin
import Foundation
import IOKit

private typealias IOAVServiceRef = CFTypeRef

@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(
    _ allocator: CFAllocator?,
    _ service: io_service_t
) -> Unmanaged<IOAVServiceRef>?

@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(
    _ service: IOAVServiceRef,
    _ chipAddress: UInt32,
    _ dataAddress: UInt32,
    _ inputBuffer: UnsafeMutableRawPointer,
    _ inputBufferSize: UInt32
) -> IOReturn

/// Minimal Apple Silicon DDC/CI implementation. Packet construction and
/// DCPAVServiceProxy discovery follow the MIT-licensed MonitorControl project.
final class DisplayHardwareController {
    private struct Candidate {
        var vendorID: UInt32 = 0
        var productID: UInt32 = 0
        var serialNumber: UInt32 = 0
        var service: IOAVServiceRef?
    }

    private var services: [String: IOAVServiceRef] = [:]
    private var pendingWrites: [String: DispatchWorkItem] = [:]
    private let writeQueue = DispatchQueue(label: "local.lumaflow.ddc", qos: .userInitiated)

    func refresh(displays: [DisplayInfo]) {
        services.removeAll()
        let candidates = discoverCandidates()
        for display in displays where !display.isBuiltIn {
            if let candidate = candidates.first(where: {
                $0.vendorID == display.vendorID &&
                $0.productID == display.productID &&
                ($0.serialNumber == 0 || display.serialNumber == 0 || $0.serialNumber == display.serialNumber)
            }), let service = candidate.service {
                services[display.stableKey] = service
            }
        }
    }

    func supportsHardwareBrightness(_ display: DisplayInfo) -> Bool {
        display.isBuiltIn || display.vendorID == 0x610 || services[display.stableKey] != nil
    }

    func setBrightness(_ value: Double, for display: DisplayInfo) {
        let clamped = Float(min(max(value, 0), 1))
        if display.isBuiltIn || display.vendorID == 0x610 {
            _ = Self.setAppleBrightness(displayID: display.id, value: clamped)
            return
        }
        guard let service = services[display.stableKey] else { return }

        pendingWrites[display.stableKey]?.cancel()
        let ddcValue = UInt16((clamped * 100).rounded())
        let item = DispatchWorkItem {
            _ = Self.writeVCP(service: service, command: 0x10, value: ddcValue)
        }
        pendingWrites[display.stableKey] = item
        writeQueue.asyncAfter(deadline: .now() + .milliseconds(35), execute: item)
    }

    private static func setAppleBrightness(
        displayID: CGDirectDisplayID,
        value: Float
    ) -> Bool {
        typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        ), let symbol = dlsym(handle, "DisplayServicesSetBrightness") else {
            return false
        }
        let function = unsafeBitCast(symbol, to: SetBrightness.self)
        return function(displayID, value) == 0
    }

    private static func writeVCP(
        service: IOAVServiceRef,
        command: UInt8,
        value: UInt16
    ) -> Bool {
        let address: UInt8 = 0x37
        let dataAddress: UInt8 = 0x51
        let payload: [UInt8] = [command, UInt8(value >> 8), UInt8(value & 0xff)]
        var packet = [UInt8(0x80 | (payload.count + 1)), UInt8(payload.count)] + payload + [0]
        packet[packet.count - 1] = checksum(
            seed: (address << 1) ^ dataAddress,
            bytes: packet.dropLast()
        )

        for _ in 0..<3 {
            usleep(10_000)
            let packetCount = UInt32(packet.count)
            let result = packet.withUnsafeMutableBytes {
                IOAVServiceWriteI2C(
                    service,
                    UInt32(address),
                    UInt32(dataAddress),
                    $0.baseAddress!,
                    packetCount
                )
            }
            if result == kIOReturnSuccess { return true }
            usleep(20_000)
        }
        return false
    }

    private static func checksum<S: Sequence>(seed: UInt8, bytes: S) -> UInt8
    where S.Element == UInt8 {
        bytes.reduce(seed, ^)
    }

    private func discoverCandidates() -> [Candidate] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return [] }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var candidates: [Candidate] = []
        var current = Candidate()
        while case let entry = IOIteratorNext(iterator), entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &nameBuffer) == KERN_SUCCESS else { continue }
            let name = String(cString: nameBuffer)

            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                current = candidateMetadata(from: entry)
            } else if name == "DCPAVServiceProxy",
                      propertyString("Location", from: entry) == "External" {
                current.service = IOAVServiceCreateWithService(
                    kCFAllocatorDefault,
                    entry
                )?.takeRetainedValue()
                if current.service != nil { candidates.append(current) }
            }
        }
        return candidates
    }

    private func candidateMetadata(from entry: io_service_t) -> Candidate {
        var candidate = Candidate()
        guard let attributes = propertyDictionary("DisplayAttributes", from: entry),
              let product = attributes["ProductAttributes"] as? [String: Any] else {
            return candidate
        }
        candidate.vendorID = (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value ?? 0
        candidate.productID = (product["ProductID"] as? NSNumber)?.uint32Value ?? 0
        candidate.serialNumber = (product["SerialNumber"] as? NSNumber)?.uint32Value ?? 0
        return candidate
    }

    private func propertyDictionary(_ key: String, from entry: io_service_t) -> [String: Any]? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        )?.takeRetainedValue() as? [String: Any]
    }

    private func propertyString(_ key: String, from entry: io_service_t) -> String? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        )?.takeRetainedValue() as? String
    }
}
