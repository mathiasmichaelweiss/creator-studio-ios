import XCTest
@testable import CreatorStudio

final class FormatPickerTests: XCTestCase {
    func testRecognisesVideoFormats() {
        XCTAssertTrue(FormatPicker.isSixteenByNine(width: 3840, height: 2160))
        XCTAssertTrue(FormatPicker.isSixteenByNine(width: 1920, height: 1080))
    }

    func testRejectsPhotoFormats() {
        XCTAssertFalse(FormatPicker.isSixteenByNine(width: 4032, height: 3024))
        XCTAssertFalse(FormatPicker.isSixteenByNine(width: 0, height: 0))
    }

    func testPrefersHigherFpsThenResolution() {
        XCTAssertTrue(FormatPicker.isWorse((fps: 30, pixels: 3840 * 2160), than: (fps: 60, pixels: 1920 * 1080)))
        XCTAssertTrue(FormatPicker.isWorse((fps: 60, pixels: 1920 * 1080), than: (fps: 60, pixels: 3840 * 2160)))
        XCTAssertFalse(FormatPicker.isWorse((fps: 60, pixels: 3840 * 2160), than: (fps: 60, pixels: 3840 * 2160)))
    }
}
