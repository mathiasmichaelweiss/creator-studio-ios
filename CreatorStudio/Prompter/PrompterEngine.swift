import Foundation
import QuartzCore

/// Прокрутка суфлёра: позиция текста в пунктах, меняется только пока суфлёр запущен.
final class PrompterEngine: ObservableObject {
    @Published private(set) var offset: Double = 0
    @Published private(set) var isRunning = false

    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    var speed: Double = 40

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastTick = CACurrentMediaTime()
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        isRunning = false
        link?.invalidate(); link = nil
    }

    func reset() { stop(); offset = 0 }

    /// Ручная подмотка пальцем.
    func nudge(by delta: Double) { offset = max(0, offset + delta) }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        offset += PrompterMath.advance(speed: speed, from: lastTick, to: now)
        lastTick = now
    }
}

enum PrompterMath {
    /// Сколько пунктов проехать за интервал. Защита от скачков после фона.
    static func advance(speed: Double, from: CFTimeInterval, to: CFTimeInterval) -> Double {
        let dt = min(max(to - from, 0), 0.1)
        return speed * dt
    }
}
