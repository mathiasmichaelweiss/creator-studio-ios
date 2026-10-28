import Foundation

/// Находит в сценарии место, которое ты сейчас произносишь.
/// На вход: распознанный текст (растёт по ходу речи). На выход: номер последнего сказанного слова сценария.
/// Чистая логика без звука и UI, поэтому полностью покрыта тестами.
struct ScriptAligner {
    struct Word: Equatable {
        let norm: String
        /// Позиция слова в исходном тексте (UTF-16), чтобы найти его строку на экране.
        let location: Int
    }

    let words: [Word]
    /// Индекс следующего ожидаемого слова (последнее найденное + 1).
    private(set) var position = 0

    /// Сколько последних услышанных слов сравниваем со сценарием.
    static let tail = 4
    /// Насколько далеко вперёд можно «перепрыгнуть», если ты пропустил кусок.
    static let lookAhead = 80
    /// Насколько можно вернуться назад, если повторил фразу.
    static let lookBehind = 6

    init(text: String) {
        words = Self.tokenize(text)
    }

    mutating func reset(to index: Int = 0) { position = min(max(0, index), words.count) }

    /// Обрабатывает распознанный текст. Возвращает индекс слова сценария, если место сдвинулось.
    mutating func consume(transcript: String) -> Int? {
        let heard = Self.tokenize(transcript).map(\.norm)
        guard !heard.isEmpty, !words.isEmpty else { return nil }
        let k = min(Self.tail, heard.count)
        let tailWords = Array(heard.suffix(k))
        let need = k >= 2 ? 2 : 1

        let lo = max(0, position - Self.lookBehind)
        let hi = min(words.count - 1, position + Self.lookAhead)
        guard lo <= hi else { return nil }

        var best: (index: Int, score: Int, distance: Int)?
        for j in lo...hi where Self.same(words[j].norm, tailWords[k - 1]) {
            var score = 0
            for t in 0..<k {
                let wi = j - t
                guard wi >= 0 else { break }
                if Self.same(words[wi].norm, tailWords[k - 1 - t]) { score += 1 }
            }
            // Одно совпавшее слово засчитывается только рядом с текущим местом и если слово не короткое.
            if score < need {
                guard need == 1 || (score == 1 && tailWords[k - 1].count >= 5 && j >= position && j <= position + 3)
                else { continue }
            }
            let distance = abs(j - position)
            if best == nil || score > best!.score || (score == best!.score && distance < best!.distance) {
                best = (j, score, distance)
            }
        }
        guard let found = best, found.index + 1 != position else { return nil }
        position = found.index + 1
        return found.index
    }

    // MARK: Слова

    static func tokenize(_ text: String) -> [Word] {
        var result: [Word] = []
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { sub, range, _, _ in
            guard let sub else { return }
            let n = normalize(sub)
            if !n.isEmpty { result.append(Word(norm: n, location: range.location)) }
        }
        return result
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Одинаковые слова с поправкой на окончания и ошибки распознавания:
    /// совпадение, общее начало из 5 букв (падежи), или одна опечатка в длинном слове.
    static func same(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.count >= 5, b.count >= 5, a.prefix(5) == b.prefix(5) { return true }
        if a.count >= 5, b.count >= 5, abs(a.count - b.count) <= 1 { return distance(a, b) <= 1 }
        return false
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[y.count]
    }
}
