import XCTest
@testable import CreatorStudio

final class CameraOptionsTests: XCTestCase {
    func testWideUsesZoomBelowOne() {
        let z = CameraMath.zoomFactors(minAvailable: 0.7, maxAvailable: 5)
        XCTAssertEqual(z.normal, 1)
        XCTAssertEqual(z.wide, 0.7)
        XCTAssertTrue(CameraMath.supportsWide(minAvailable: 0.7))
    }

    func testNoWideOnOldCamera() {
        let z = CameraMath.zoomFactors(minAvailable: 1, maxAvailable: 3)
        XCTAssertEqual(z.normal, 1)
        XCTAssertEqual(z.wide, 1)
        XCTAssertFalse(CameraMath.supportsWide(minAvailable: 1))
    }

    func testShutterNeverLongerThanFrame() {
        XCTAssertEqual(CameraMath.shutterOptions(fps: 60), [60, 100, 120, 250, 500, 1000])
        XCTAssertEqual(CameraMath.shutterOptions(fps: 30).first, 30)
        XCTAssertEqual(CameraMath.recommendedShutter(fps: 60), 120)
        XCTAssertEqual(CameraMath.recommendedShutter(fps: 25), 50)
    }

    func testGainClamp() {
        XCTAssertEqual(CameraMath.clampGain(0.5, maxGain: 4), 1)
        XCTAssertEqual(CameraMath.clampGain(6, maxGain: 4), 4)
        XCTAssertEqual(CameraMath.clampGain(2, maxGain: 4), 2)
    }

    func testHistogramNormalized() {
        // Половина кадра чёрная, половина белая.
        let h = CameraMath.histogram(width: 10, height: 10, step: 1, bins: 4) { x, _ in x < 5 ? 0 : 255 }
        XCTAssertEqual(h, [1, 0, 0, 1])
        XCTAssertTrue(CameraMath.histogram(width: 0, height: 5, step: 1, bins: 4) { _, _ in 0 }.isEmpty)
    }

    func testOrientationMatch() {
        XCTAssertTrue(CameraMath.matches(.vertical, width: 2160, height: 3840))
        XCTAssertFalse(CameraMath.matches(.vertical, width: 3840, height: 2160))
        XCTAssertTrue(CameraMath.matches(.horizontal, width: 3840, height: 2160))
    }

    func testOptionsRoundTrip() {
        let d = UserDefaults(suiteName: "camera-test")!
        d.removePersistentDomain(forName: "camera-test")
        var o = CameraOptions()
        o.framing = .wide; o.orientation = .horizontal; o.shutter = 100; o.whiteBalance = 5600
        o.save(to: d)
        XCTAssertEqual(CameraOptions.load(from: d), o)
        XCTAssertEqual(CameraMath.shutterTitle(nil), "Авто")
        XCTAssertEqual(CameraMath.whiteBalanceTitle(3200), "3200K")
    }

    func testLandscapeCropFromTallFrame() {
        let r = CameraMath.landscapeCrop(width: 3024, height: 4032)
        XCTAssertEqual(r.w, 3024)
        XCTAssertEqual(r.h, 1700)
        XCTAssertEqual(r.y, (4032 - 1700) / 2)
        XCTAssertEqual(r.x, 0)
        XCTAssertTrue(FormatPicker.isTall(width: 4032, height: 3024))
        XCTAssertTrue(FormatPicker.isTall(width: 3840, height: 3840))
        XCTAssertFalse(FormatPicker.isTall(width: 3840, height: 2160))
    }
}
