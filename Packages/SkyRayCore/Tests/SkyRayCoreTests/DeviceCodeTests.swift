import XCTest
@testable import SkyRayCore

final class DeviceCodeTests: XCTestCase {
    func testTheCodeIsSixteenHexOfTheIdAndTheBundleAndNothingWithoutAnId() {
        let a = DeviceCode.make(id: "9774D56D-682E-549C-B2A4-0123456789AB", bundle: "com.allion.skyray")!
        XCTAssertEqual(a.count, 16)
        XCTAssertTrue(a.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertEqual(a, DeviceCode.make(id: " 9774D56D-682E-549C-B2A4-0123456789AB ", bundle: "com.allion.skyray"))
        XCTAssertNotEqual(a, DeviceCode.make(id: "9774D56D-682E-549C-B2A4-0123456789AC", bundle: "com.allion.skyray"))
        XCTAssertNotEqual(a, DeviceCode.make(id: "9774D56D-682E-549C-B2A4-0123456789AB", bundle: "com.other.app"))
        XCTAssertNil(DeviceCode.make(id: "", bundle: "com.allion.skyray"))
        XCTAssertNil(DeviceCode.make(id: nil, bundle: "com.allion.skyray"))
    }
}
