import Foundation
import QuartzCore

/// Прокрутка суфлёра: позиция текста в пунктах, меняется только пока суфлёр запущен.
final class PrompterEngine: ObservableObject {
    @Published private(set) var offset: Double = 0
    @Published private(set) var isRunning = false

    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    var speed: Double = 40
    /// Режим «по голосу»: текст плавно едет к строке, которую ты сейчас говоришь.
    var followsVoice = false
    private var target: Double?

    func follow(to y: Double) { target = max(0, y) }

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

    func reset() { stop(); offset = 0; target = nil }

    /// Ручная подмотка пальцем.
    func nudge(by delta: Double) { offset = max(0, offset + delta) }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if followsVoice {
            if let target { offset += PrompterMath.ease(current: offset, target: target, t0: lastTick, t1: now) }
        } else {
            offset += PrompterMath.advance(speed: speed, from: lastTick, to: now)
        }
        lastTick = now
    }
}

enum PrompterMath {
    /// Сколько пунктов проехать за интервал. Защита от скачков после фона.
    static func advance(speed: Double, from: CFTimeInterval, to: CFTimeInterval) -> Double {
        let dt = min(max(to - from, 0), 0.1)
        return speed * dt
    }

    /// Плавный подъезд к строке: за 0,2 с проходит примерно две трети пути, без рывков.
    static func ease(current: Double, target: Double, t0: CFTimeInterval, t1: CFTimeInterval) -> Double {
        let dt = min(max(t1 - t0, 0), 0.1)
        return (target - current) * min(1, dt * 5)
    }
}
