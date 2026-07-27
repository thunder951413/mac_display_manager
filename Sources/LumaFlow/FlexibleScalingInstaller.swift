import Foundation

enum FlexibleScalingInstaller {
    struct InstallRequest: Sendable {
        let vendorID: UInt32
        let productID: UInt32
        let defaultWidth: Int
        let defaultHeight: Int

        init(display: DisplayInfo) {
            vendorID = display.vendorID
            productID = display.productID
            defaultWidth = display.defaultWidth
            defaultHeight = display.defaultHeight
        }

        init(
            vendorID: UInt32,
            productID: UInt32,
            defaultWidth: Int,
            defaultHeight: Int
        ) {
            self.vendorID = vendorID
            self.productID = productID
            self.defaultWidth = defaultWidth
            self.defaultHeight = defaultHeight
        }

        var vendorFolderName: String {
            "DisplayVendorID-\(String(vendorID, radix: 16))"
        }

        var productFileName: String {
            "DisplayProductID-\(String(productID, radix: 16))"
        }
    }

    enum InstallerError: LocalizedError {
        case invalidDisplay
        case cannotCreateConfiguration
        case authorizationCancelled
        case privilegedCommandFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidDisplay:
                return "无法读取显示器的默认分辨率或硬件标识。"
            case .cannotCreateConfiguration:
                return "无法生成灵活缩放配置。"
            case .authorizationCancelled:
                return "管理员授权已取消，显示器配置没有改变。"
            case .privilegedCommandFailed(let detail):
                return "安装显示器配置失败：\(detail)"
            }
        }
    }

    static func install(_ request: InstallRequest) -> Result<Void, Error> {
        guard request.vendorID > 0,
              request.productID > 0,
              request.defaultWidth > 0,
              request.defaultHeight > 0 else {
            return .failure(InstallerError.invalidDisplay)
        }

        do {
            let paths = try paths(for: request)
            let plist = try mergedConfiguration(request: request, existingURL: paths.target)
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("LumaFlow-\(UUID().uuidString).plist")
            try plist.write(to: temporary, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporary) }

            let command = [
                "/bin/mkdir -p \(shellQuote(paths.target.deletingLastPathComponent().path))",
                "/bin/mkdir -p \(shellQuote(paths.backup.deletingLastPathComponent().path))",
                "if [ -f \(shellQuote(paths.target.path)) ] && [ ! -f \(shellQuote(paths.backup.path)) ]; then /bin/cp -p \(shellQuote(paths.target.path)) \(shellQuote(paths.backup.path)); fi",
                "/bin/cp \(shellQuote(temporary.path)) \(shellQuote(paths.target.path))",
                "/usr/sbin/chown root:wheel \(shellQuote(paths.target.path))",
                "/bin/chmod 0644 \(shellQuote(paths.target.path))"
            ].joined(separator: " && ")

            try runPrivileged(command)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    static func uninstall(_ request: InstallRequest) -> Result<Void, Error> {
        do {
            let paths = try paths(for: request)
            let command = [
                "if [ -f \(shellQuote(paths.backup.path)) ]; then /bin/cp -p \(shellQuote(paths.backup.path)) \(shellQuote(paths.target.path)); else /bin/rm -f \(shellQuote(paths.target.path)); fi",
                "if [ -f \(shellQuote(paths.target.path)) ]; then /usr/sbin/chown root:wheel \(shellQuote(paths.target.path)) && /bin/chmod 0644 \(shellQuote(paths.target.path)); fi"
            ].joined(separator: " && ")
            try runPrivileged(command)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private static func paths(for request: InstallRequest) throws -> (target: URL, backup: URL) {
        let root = URL(fileURLWithPath: "/Library/Displays/Contents/Resources/Overrides", isDirectory: true)
        let target = root
            .appendingPathComponent(request.vendorFolderName, isDirectory: true)
            .appendingPathComponent(request.productFileName)
        let backupRoot = URL(
            fileURLWithPath: "/Library/Application Support/LumaFlow/Backups",
            isDirectory: true
        )
        let backup = backupRoot.appendingPathComponent(
            "\(request.vendorFolderName)-\(request.productFileName).original"
        )
        return (target, backup)
    }

    private static func mergedConfiguration(
        request: InstallRequest,
        existingURL: URL
    ) throws -> Data {
        var dictionary: [String: Any] = [
            "DisplayVendorID": Int(request.vendorID),
            "DisplayProductID": Int(request.productID)
        ]

        if let existingData = try? Data(contentsOf: existingURL),
           let existing = try? PropertyListSerialization.propertyList(
                from: existingData,
                options: [],
                format: nil
           ) as? [String: Any] {
            dictionary.merge(existing) { _, existingValue in existingValue }
        }

        var resolutions = (dictionary["scale-resolutions"] as? [Data]) ?? []
        var known = Set(resolutions)
        for data in generatedResolutions(for: request) {
            if known.insert(data).inserted {
                resolutions.append(data)
            }
        }

        guard !resolutions.isEmpty else {
            throw InstallerError.cannotCreateConfiguration
        }
        dictionary["scale-resolutions"] = resolutions

        return try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
    }

    static func generatedResolutions(for request: InstallRequest) -> [Data] {
        stride(from: 70, through: 199, by: 3).map { percent in
            let framebufferWidth = Int(
                (Double(request.defaultWidth * 2) * Double(percent) / 100).rounded()
            )
            let framebufferHeight = Int(
                (Double(request.defaultHeight * 2) * Double(percent) / 100).rounded()
            )
            return resolutionData(width: framebufferWidth, height: framebufferHeight)
        }
    }

    private static func resolutionData(width: Int, height: Int) -> Data {
        var widthBE = UInt32(width).bigEndian
        var heightBE = UInt32(height).bigEndian
        var data = Data(bytes: &widthBE, count: MemoryLayout<UInt32>.size)
        data.append(Data(bytes: &heightBE, count: MemoryLayout<UInt32>.size))
        return data
    }

    private static func runPrivileged(_ command: String) throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw InstallerError.privilegedCommandFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let detail = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if detail.contains("-128") || detail.localizedCaseInsensitiveContains("cancel") {
                throw InstallerError.authorizationCancelled
            }
            throw InstallerError.privilegedCommandFailed(
                detail.isEmpty ? "osascript \(process.terminationStatus)" : detail
            )
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
