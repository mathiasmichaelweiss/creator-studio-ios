import Foundation

/// Точка факта: сколько просмотров через столько-то часов после публикации.
struct FactPoint: Codable, Equatable, Hashable {
    var hours: Double
    var views: Double
}

/// Цифры из Insights на момент последнего среза.
struct FactStats: Codable, Equatable, Hashable {
    var hours: Double?
    var views: Double?
    var skip: Double?
    var avgWatch: Double?
    var length: Double?
    var saves: Double?
    var shares: Double?
    var reposts: Double?
    var likes: Double?
    var comments: Double?
    var subs: Double?

    var isEmpty: Bool { [views, skip, avgWatch, saves, shares, likes, comments, subs].allSatisfy { $0 == nil } }

    /// Досмотр в процентах: средний просмотр / длина ролика.
    var retention: Double? {
        guard let a = avgWatch, let l = length, l > 0 else { return nil }
        return a / l * 100
    }

    /// Доля от просмотров в процентах.
    func rate(_ v: Double?) -> Double? {
        guard let v, let views, views > 0 else { return nil }
        return v / views * 100
    }
}

/// Прогноз просмотров из базы «Прогнозы»: коридор (минимум, ожидание, максимум) на 24/48/72/96 ч.
struct Forecast: Codable, Equatable, Hashable {
    static let grid: [Double] = [24, 48, 72, 96]

    var id: String
    var confidence: String = ""
    var lo: [Double] = []
    var mid: [Double] = []
    var hi: [Double] = []
    var actual: [FactPoint] = []
    var why: String = ""
    var skip: String = ""
    var shares: String = ""
    var saves: String = ""
    var subs: String = ""
    /// Последний срез из Insights (поля «Факт …» в Notion). Необязательно: старый кэш без него читается.
    var stats: FactStats? = nil

    var isUsable: Bool { mid.count == Forecast.grid.count }
}

enum ForecastParser {
    typealias JSON = [String: Any]

    /// Свойства страницы плюс блоки «```json```» под «## Прогноз» и «## Факт».
    /// Если блока с коридором нет, ожидание берётся из чисел «Прогноз 24ч…96ч».
    static func forecast(page: JSON, blocks: [JSON]) -> (scriptId: String, forecast: Forecast)? {
        guard let id = page["id"] as? String, let props = page["properties"] as? JSON,
              let scriptId = NotionParser.relationIds(props["Сценарий"]).first else { return nil }

        var f = Forecast(id: id)
        f.confidence = NotionParser.plainText(props["Уверенность"])
        f.why = NotionParser.plainText(props["Почему"])
        f.skip = NotionParser.plainText(props["Пропуски"])
        f.shares = NotionParser.plainText(props["Репосты"])
        f.saves = NotionParser.plainText(props["Сохранения"])
        f.subs = NotionParser.plainText(props["Подписки"])
        let n = { (k: String) in NotionParser.number(props[k]) }
        let st = FactStats(hours: n("Факт часов"), views: n("Факт просмотры"), skip: n("Факт пропуски"),
                           avgWatch: n("Факт досмотр"), length: n("Факт длина"), saves: n("Факт сохранения"),
                           shares: n("Факт отправки"), reposts: n("Факт репосты"), likes: n("Факт лайки"),
                           comments: n("Факт комментарии"), subs: n("Факт подписки"))
        f.stats = st.isEmpty ? nil : st

        let codes = codeBlocks(blocks)
        if let parsed = codes["прогноз"].flatMap({ band(from: $0) }) {
            (f.lo, f.mid, f.hi) = parsed
        } else {
            let mids = Forecast.grid.map { NotionParser.number(props["Прогноз \(Int($0))ч"]) }
            if mids.allSatisfy({ $0 != nil }) { f.mid = mids.compactMap { $0 } }
            if let lo = NotionParser.number(props["Минимум 96ч"]), let hi = NotionParser.number(props["Максимум 96ч"]),
               f.isUsable {
                // Без полного коридора: доли от ожидания на 96 ч переносятся на остальные точки.
                let m = f.mid[3]
                f.lo = f.mid.map { m > 0 ? $0 * lo / m : 0 }
                f.hi = f.mid.map { m > 0 ? $0 * hi / m : 0 }
            }
        }
        if let points = codes["факт"].flatMap({ facts(from: $0) }) {
            f.actual = points
        } else if let views = NotionParser.number(props["Факт просмотры"]) {
            f.actual = [FactPoint(hours: f.stats?.hours ?? 96, views: views)]
        }
        return f.isUsable ? (scriptId, f) : nil
    }

    /// Текст код-блоков, ключ: заголовок второго уровня над ними (в нижнем регистре).
    static func codeBlocks(_ blocks: [JSON]) -> [String: String] {
        var heading = ""
        var out: [String: String] = [:]
        for b in blocks {
            guard let type = b["type"] as? String else { continue }
            let text = NotionParser.richText((b[type] as? JSON)?["rich_text"])
            if type == "heading_2" || type == "heading_1" { heading = text.trimmed.lowercased() }
            if type == "code", out[heading] == nil { out[heading] = text }
        }
        return out
    }

    static func band(from json: String) -> ([Double], [Double], [Double])? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? JSON else { return nil }
        func nums(_ k: String) -> [Double]? {
            guard let a = obj[k] as? [NSNumber], a.count == Forecast.grid.count else { return nil }
            return a.map(\.doubleValue)
        }
        guard let lo = nums("lo"), let mid = nums("mid"), let hi = nums("hi") else { return nil }
        return (lo, mid, hi)
    }

    static func facts(from json: String) -> [FactPoint]? {
        guard let arr = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [JSON] else { return nil }
        let points = arr.compactMap { d -> FactPoint? in
            guard let h = (d["h"] as? NSNumber)?.doubleValue, let v = (d["v"] as? NSNumber)?.doubleValue else { return nil }
            return FactPoint(hours: h, views: v)
        }
        return points.isEmpty ? nil : points.sorted { $0.hours < $1.hours }
    }
}

/// Расчёты для графика «прогноз против факта».
enum ForecastMath {
    struct BandPoint: Equatable, Identifiable {
        var hours: Double
        var lo: Double
        var mid: Double
        var hi: Double
        var id: Double { hours }
    }

    /// Коридор с нулём в момент публикации.
    static func band(_ f: Forecast) -> [BandPoint] {
        guard f.isUsable else { return [] }
        let lo = f.lo.count == 4 ? f.lo : f.mid
        let hi = f.hi.count == 4 ? f.hi : f.mid
        return [BandPoint(hours: 0, lo: 0, mid: 0, hi: 0)] +
            Forecast.grid.indices.map { BandPoint(hours: Forecast.grid[$0], lo: lo[$0], mid: f.mid[$0], hi: hi[$0]) }
    }

    /// Ожидание в любой момент: линейно между точками, после 96 ч держится на последнем значении.
    static func expected(_ f: Forecast, at hours: Double) -> Double? {
        let pts = band(f)
        guard let last = pts.last else { return nil }
        if hours >= last.hours { return last.mid }
        for (a, b) in zip(pts, pts.dropFirst()) where hours <= b.hours {
            let t = (hours - a.hours) / (b.hours - a.hours)
            return a.mid + (b.mid - a.mid) * max(0, t)
        }
        return last.mid
    }

    /// Факт из Notion плюс введённый вручную. На одном и том же часе побеждает ручной.
    static func merged(notion: [FactPoint], manual: [FactPoint]) -> [FactPoint] {
        var byHour: [Double: Double] = [:]
        for p in notion { byHour[p.hours] = p.views }
        for p in manual { byHour[p.hours] = p.views }
        return byHour.map { FactPoint(hours: $0.key, views: $0.value) }.sorted { $0.hours < $1.hours }
    }

    enum Verdict: Equatable {
        case noData
        case above(percent: Int)
        case below(percent: Int)
        case onTrack

        var text: String {
            switch self {
            case .noData: "Факта пока нет"
            case .above(let p): "Выше прогноза на \(p)%"
            case .below(let p): "Ниже прогноза на \(p)%"
            case .onTrack: "Идёт по прогнозу"
            }
        }
    }

    /// Последний факт против ожидания на тот же час. В пределах ±10% считается «по прогнозу».
    static func verdict(_ f: Forecast, facts: [FactPoint]) -> Verdict {
        guard let last = facts.max(by: { $0.hours < $1.hours }),
              let exp = expected(f, at: last.hours), exp > 0 else { return .noData }
        let diff = (last.views - exp) / exp
        let p = Int((abs(diff) * 100).rounded())
        if p <= 10 { return .onTrack }
        return diff > 0 ? .above(percent: p) : .below(percent: p)
    }

    /// «~23%», «2,0%», «25 %» → 23 / 2 / 25. Диапазоны («60–200») и пусто → nil.
    static func percent(_ text: String) -> Double? {
        guard text.contains("%") else { return nil }
        let cleaned = text.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        return Double(cleaned)
    }

    /// Процент для карточки: «29 %», «0,6 %».
    static func pct(_ v: Double) -> String {
        let s = v >= 10 ? String(Int(v.rounded())) : String(format: "%.1f", v)
        return s.replacingOccurrences(of: ".", with: ",") + " %"
    }

    /// Последний факт и ожидание на тот же час.
    static func now(_ f: Forecast, facts: [FactPoint]) -> (fact: FactPoint, expected: Double)? {
        guard let last = facts.max(by: { $0.hours < $1.hours }), let e = expected(f, at: last.hours) else { return nil }
        return (last, e)
    }

    static func compact(_ v: Double) -> String {
        if v >= 1000 {
            let k = v / 1000
            let s = k >= 100 || k.rounded() == k ? String(Int(k.rounded())) : String(format: "%.1f", k)
            return s.replacingOccurrences(of: ".", with: ",") + " тыс."
        }
        return String(Int(v.rounded()))
    }
}
