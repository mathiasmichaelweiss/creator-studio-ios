import CoreMedia

/// Склеивает запись с паузами в один непрерывный ролик.
///
/// Пока запись на паузе, кадры и звук отбрасываются. Первый сэмпл после паузы
/// сдвигает общий офсет на длину паузы, и время в файле идёт без дыры.
/// Чистая логика без AVFoundation, поэтому покрыта юнит-тестами.
struct PausableTimeline {
    private(set) var isPaused = false
    private(set) var offset: CMTime = .zero
    private var lastEnd: CMTime = .invalid
    private var needsGapUpdate = false

    mutating func pause() {
        guard !isPaused else { return }
        isPaused = true
    }

    mutating func resume() {
        guard isPaused else { return }
        isPaused = false
        needsGapUpdate = true
    }

    /// Возвращает время сэмпла в файле или `nil`, если сэмпл надо выбросить.
    mutating func map(presentation pts: CMTime, duration: CMTime) -> CMTime? {
        guard !isPaused, pts.isValid else { return nil }
        if needsGapUpdate {
            needsGapUpdate = false
            if lastEnd.isValid {
                let gap = CMTimeSubtract(pts, lastEnd)
                if gap > .zero { offset = CMTimeAdd(offset, gap) }
            }
        }
        let end = duration.isValid && duration > .zero ? CMTimeAdd(pts, duration) : pts
        if !lastEnd.isValid || end > lastEnd { lastEnd = end }
        return CMTimeSubtract(pts, offset)
    }

    /// Время записи (без пауз) для момента `pts` на часах сессии.
    func recordedTime(at pts: CMTime) -> CMTime {
        CMTimeSubtract(pts, offset)
    }
}
