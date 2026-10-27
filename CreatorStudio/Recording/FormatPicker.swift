import Foundation

/// Правила выбора формата камеры. Отдельно от AVFoundation, чтобы покрыть тестами.
enum FormatPicker {
    static func isSixteenByNine(width: Int32, height: Int32) -> Bool {
        guard width > 0, height > 0 else { return false }
        let r = Double(max(width, height)) / Double(min(width, height))
        return abs(r - 16.0 / 9.0) < 0.02
    }

    /// Сравнение (fps, пиксели): важнее fps, при равном fps больше пикселей.
    static func isWorse(_ a: (fps: Double, pixels: Int32), than b: (fps: Double, pixels: Int32)) -> Bool {
        if a.fps != b.fps { return a.fps < b.fps }
        return a.pixels < b.pixels
    }
}
