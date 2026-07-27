import XCTest
@testable import LumaFlow

final class LumaFlowTests: XCTestCase {
    func testResolutionPolicyRequires120HzAndNativeAspect() {
        XCTAssertTrue(ResolutionPolicy.matches(
            width: 1728, height: 1117, refreshRate: 120,
            targetRefreshRate: 120,
            nativeWidth: 3456, nativeHeight: 2234
        ))
        XCTAssertFalse(ResolutionPolicy.matches(
            width: 1728, height: 1080, refreshRate: 120,
            targetRefreshRate: 120,
            nativeWidth: 3456, nativeHeight: 2234
        ))
        XCTAssertTrue(ResolutionPolicy.matches(
            width: 1920, height: 1080, refreshRate: 60,
            targetRefreshRate: 60,
            nativeWidth: 3840, nativeHeight: 2160
        ))
        XCTAssertFalse(ResolutionPolicy.matches(
            width: 1728, height: 1117, refreshRate: 60,
            targetRefreshRate: 120,
            nativeWidth: 3456, nativeHeight: 2234
        ))
    }

    func testThreePercentScaleGridIsAnchoredAt100() {
        let rawPercentages = [68, 76, 87, 100, 119, 135, 152, 173, 200]
        let stepped = rawPercentages.map { 100 + Int((Double($0 - 100) / 3).rounded()) * 3 }
        XCTAssertEqual(stepped, [67, 76, 88, 100, 118, 136, 151, 172, 199])
        XCTAssertTrue(stepped.allSatisfy { ($0 - 100).isMultiple(of: 3) })
    }

    func testFlexibleScalingGeneratesEveryThreePercent() {
        let request = FlexibleScalingInstaller.InstallRequest(
            vendorID: 0x610,
            productID: 0x1234,
            defaultWidth: 1728,
            defaultHeight: 1117
        )
        let resolutions = FlexibleScalingInstaller.generatedResolutions(for: request)
        XCTAssertEqual(resolutions.count, 44)

        let oneHundredPercentIndex = (100 - 70) / 3
        let bytes = [UInt8](resolutions[oneHundredPercentIndex])
        XCTAssertEqual(bytes, [0x00, 0x00, 0x0d, 0x80, 0x00, 0x00, 0x08, 0xba])
    }

    func testBrightnessMediaKeyDirectionAndRepeat() {
        let keyDown = 0x0a << 8
        let keyRepeat = 0x0b << 8
        XCTAssertEqual(
            BrightnessKeyAction.decode(
                data1: (2 << 16) | keyDown,
                modifierFlags: []
            ),
            .increase(fine: false)
        )
        XCTAssertEqual(
            BrightnessKeyAction.decode(
                data1: (3 << 16) | keyRepeat,
                modifierFlags: [.option, .shift]
            ),
            .decrease(fine: true)
        )
    }
}
