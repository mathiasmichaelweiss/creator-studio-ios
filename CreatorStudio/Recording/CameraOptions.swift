import Foundation

/// Настройки фронтальной камеры (iPhone 17/18 с квадратным сенсором Center Stage).
/// Чистая логика без AVFoundation, чтобы покрыть тестами.
struct CameraOptions: Codable, Equatable {
    enum Framing: String, Codable, CaseIterable, Identifiable {
        case normal, wide
        var id: String { rawValue }
        var title: String { self == .normal ? "Обычно" : "Широко" }
    }

    enum Orientation: String, Codable, CaseIterable, Identifiable {
        case vertical, horizontal
        var id: String { rawValue }
        var title: String { self == .vertical ? "Вертикально 9:16" : "Горизонтально 16:9" }
    }

    enum Stabilization: String, Codable, CaseIterable, Identifiable {
        case standard, ultra
        var id: String { rawValue }
        var title: String { self == .standard ? "Стандарт" : "Ультра" }
    }

    var framing: Framing = .normal
    var orientation: Orientation = .vertical
    var centerStage = false
    var stabilization: Stabilization = .standard
    /// Ручная выдержка 1/x секунды. nil: авто.
    var shutter: Int?
    /// Компенсация экспозиции в авто-режиме, EV.
    var exposureBias: Float = 0
    /// Баланс белого в кельвинах. nil: авто.
    var whiteBalance: Int?
    var showHistogram = false

    static let storageKey = "camera.options.v1"

    static func load(from defaults: UserDefaults = .standard) -> CameraOptions {
        guard let data = defaults.data(forKey: storageKey),
              let options = try? JSONDecoder().decode(CameraOptions.self, from: data) else { return CameraOptions() }
        return options
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// Что умеет камера этого iPhone. Недоступные пункты в настройках бледные.
struct CameraCapabilities: Equatable {
    var supportsWide = false
    var supportsHorizontal = false
    var supportsCenterStage = false
    var supportsUltra = false
    var supportsPro = false
    var fps: Double = 30
}

enum CameraMath {
    /// Зум для «Обычно» и «Широко». Квадратный сенсор даёт зум меньше 1: это и есть широкий кадр.
    /// Если камера шире не умеет, оба значения одинаковые.
    static func zoomFactors(minAvailable: Double, maxAvailable: Double) -> (normal: Double, wide: Double) {
        let lo = max(minAvailable, 0.1)
        let normal = min(max(1.0, lo), max(maxAvailable, lo))
        return (normal, lo)
    }

    static func supportsWide(minAvailable: Double) -> Bool { minAvailable < 0.999 }

    /// Выдержки 1/x, которые не длиннее кадра. Первая: правило 180° (1/(2×fps)) или ближайшая к нему.
    static func shutterOptions(fps: Double) -> [Int] {
        let all = [25, 30, 50, 60, 100, 120, 250, 500, 1000]
        return all.filter { Double($0) >= fps.rounded() }
    }

    /// Рекомендованная выдержка по правилу 180°.
    static func recommendedShutter(fps: Double) -> Int {
        let target = fps * 2
        let options = shutterOptions(fps: fps)
        return options.min(by: { abs(Double($0) - target) < abs(Double($1) - target) }) ?? Int(target)
    }

    static let whiteBalanceOptions = [2800, 3200, 4000, 5000, 5600, 6500, 7500]

    static func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

    /// Усиление канала баланса белого: iOS принимает от 1 до maxGain.
    static func clampGain(_ g: Float, maxGain: Float) -> Float { clamp(g, 1, max(maxGain, 1)) }

    /// Гистограмма яркости: `bins` столбцов, нормированы к самому высокому (0…1).
    /// `step` пропускает пиксели, чтобы считать быстро на 4K.
    static func histogram(width: Int, height: Int, step: Int, bins: Int, luma: (Int, Int) -> UInt8) -> [Double] {
        guard width > 0, height > 0, bins > 0 else { return [] }
        let s = max(step, 1)
        var counts = [Int](repeating: 0, count: bins)
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let v = Int(luma(x, y))
                counts[min(v * bins / 256, bins - 1)] += 1
                x += s
            }
            y += s
        }
        let peak = counts.max() ?? 0
        guard peak > 0 else { return counts.map { _ in 0 } }
        return counts.map { Double($0) / Double(peak) }
    }

    /// Кадр уже в нужной ориентации?
    static func matches(_ orientation: CameraOptions.Orientation, width: Int, height: Int) -> Bool {
        orientation == .horizontal ? width > height : height >= width
    }

    static func shutterTitle(_ s: Int?) -> String { s.map { "1/\($0)" } ?? "Авто" }
    static func whiteBalanceTitle(_ k: Int?) -> String { k.map { "\($0)K" } ?? "Авто" }
}
