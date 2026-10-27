import XCTest
import SwiftUI
import UIKit
@testable import CreatorStudio

final class DesignTokensTests: XCTestCase {
    func testInterFontsAreBundled() {
        for name in ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"] {
            XCTAssertNotNil(UIFont(name: name, size: 16), "Шрифт \(name) не зарегистрирован (UIAppFonts в project.yml)")
        }
    }

    func testWeightMapping() {
        XCTAssertEqual(Typo.postScriptName(.regular), "Inter-Regular")
        XCTAssertEqual(Typo.postScriptName(.medium), "Inter-Medium")
        XCTAssertEqual(Typo.postScriptName(.semibold), "Inter-SemiBold")
        XCTAssertEqual(Typo.postScriptName(.bold), "Inter-Bold")
        XCTAssertEqual(Typo.postScriptName(.heavy), "Inter-Bold")
    }

    func testSiteColorsInLightAndDark() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(hex(UIColor(Palette.bg).resolvedColor(with: light)), 0xF7F7F6)
        XCTAssertEqual(hex(UIColor(Palette.bg).resolvedColor(with: dark)), 0x121212)
        XCTAssertEqual(hex(UIColor(Palette.ink).resolvedColor(with: light)), 0x111111)
        XCTAssertEqual(hex(UIColor(Palette.ink).resolvedColor(with: dark)), 0xF2F2F0)
    }

    func testThemeAndTextScale() {
        XCTAssertNil(AppTheme.system.scheme)
        XCTAssertEqual(AppTheme.dark.scheme, .dark)
        XCTAssertEqual(TextScale.large.prompterFactor, 1.2)
        XCTAssertEqual(AppTheme.allCases.map(\.title), ["Светлая", "Тёмная", "Система"])
    }

    private func hex(_ c: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
    }
}
