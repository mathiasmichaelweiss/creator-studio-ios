import SwiftUI

/// Цвета экосистемы (как на разберемся.de). Точные токены сайта переносятся отдельной задачей.
enum Theme {
    static let accent = Color(red: 0xF2 / 255, green: 0x6B / 255, blue: 0x1D / 255)
    static let lilac = Color(red: 0x8B / 255, green: 0x7C / 255, blue: 0xF6 / 255)
    static let panel = Color.black.opacity(0.55)
}
