import SwiftUI

/// Короткие алиасы на токены сайта (см. Design/Tokens.swift).
enum Theme {
    static let accent = Palette.brand
    /// Подложка панелей поверх видео: цвет поверхности сайта, полупрозрачный.
    static let panel = Palette.surface.opacity(0.86)
    static let safeZone = Palette.ink3
}
