import XCTest
import SwiftUI
@testable import CreatorStudio

final class ReadingMaskTests: XCTestCase {
    func testStopsAreOrderedAndInRange() {
        let stops = ReadingMask.stops(lineY: 105, lineHeight: 37.5, height: 300)
        let locs = stops.map(\.location)
        XCTAssertEqual(locs, locs.sorted())
        XCTAssertTrue(locs.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(locs.first, 0)
        XCTAssertEqual(locs.last, 1)
    }

    func testReadingLineIsInsideBrightBand() {
        let h: CGFloat = 300, lineY: CGFloat = 105, lineH: CGFloat = 37.5
        let stops = ReadingMask.stops(lineY: lineY, lineHeight: lineH, height: h)
        // Яркая полоса между 3-й и 4-й точками покрывает всю строку.
        XCTAssertLessThanOrEqual(stops[2].location, lineY / h)
        XCTAssertGreaterThanOrEqual(stops[3].location, (lineY + lineH) / h)
    }

    func testZeroHeightDoesNotCrash() {
        XCTAssertEqual(ReadingMask.stops(lineY: 0, lineHeight: 10, height: 0).count, 1)
    }
}
