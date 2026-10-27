import EventKit
import Foundation

/// Что запланировано: съёмка или публикация.
enum PlanKind: String, Codable, CaseIterable, Identifiable {
    case shoot, publish
    var id: String { rawValue }
    var title: String { self == .shoot ? "Съёмка" : "Публикация" }
}

struct PlanEntry: Codable, Equatable {
    var date: Date
    var kind: PlanKind
    /// Событие уже добавлено в календарь iOS (с этой датой).
    var inCalendar: Bool = false
}

/// План и ручной факт хранятся на телефоне. Notion не меняется: у ключа права только на чтение.
@MainActor
final class PlanStore: ObservableObject {
    @Published private(set) var plans: [String: PlanEntry] = [:]
    @Published private(set) var manualFacts: [String: [FactPoint]] = [:]

    private let defaults: UserDefaults
    private static let plansKey = "plans.v1"
    private static let factsKey = "manualFacts.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        plans = Self.read(defaults, Self.plansKey) ?? [:]
        manualFacts = Self.read(defaults, Self.factsKey) ?? [:]
    }

    func setPlan(_ entry: PlanEntry?, for scriptId: String) {
        plans[scriptId] = entry
        Self.write(defaults, Self.plansKey, plans)
    }

    func markInCalendar(_ scriptId: String) {
        guard var e = plans[scriptId] else { return }
        e.inCalendar = true
        setPlan(e, for: scriptId)
    }

    func addFact(_ point: FactPoint, for scriptId: String) {
        var list = manualFacts[scriptId, default: []].filter { $0.hours != point.hours }
        list.append(point)
        manualFacts[scriptId] = list.sorted { $0.hours < $1.hours }
        Self.write(defaults, Self.factsKey, manualFacts)
    }

    func removeFact(hours: Double, for scriptId: String) {
        manualFacts[scriptId] = manualFacts[scriptId, default: []].filter { $0.hours != hours }
        Self.write(defaults, Self.factsKey, manualFacts)
    }

    private static func read<T: Decodable>(_ d: UserDefaults, _ key: String) -> T? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ d: UserDefaults, _ key: String, _ value: T) {
        if let data = try? JSONEncoder().encode(value) { d.set(data, forKey: key) }
    }
}

/// Сборка плана из сценариев: своя дата в приложении важнее даты из Notion.
enum PlanMath {
    struct Item: Identifiable, Equatable {
        var script: Script
        var date: Date
        var kind: PlanKind
        var inCalendar: Bool
        var id: String { script.id }
    }

    /// «2026-10-28» + «17:00» или полная дата-время из Notion.
    static func date(notionDate: String?, time: String?, calendar: Calendar = .current) -> Date? {
        guard let raw = notionDate?.trimmed, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }

        let parts = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 9, minute: 0)
        if let t = time?.trimmed, !t.isEmpty {
            let hm = t.split(whereSeparator: { $0 == ":" || $0 == "." }).compactMap { Int($0) }
            if hm.count >= 1, (0..<24).contains(hm[0]) { c.hour = hm[0]; c.minute = hm.count > 1 ? hm[1] : 0 }
        }
        return calendar.date(from: c)
    }

    /// Готовые к съёмке сначала планируются как съёмка, остальные как публикация.
    static func defaultKind(for script: Script) -> PlanKind {
        script.status == "Готов к съёмке" || script.status == "Идея" ? .shoot : .publish
    }

    static func items(scripts: [Script], plans: [String: PlanEntry]) -> [Item] {
        scripts.compactMap { s -> Item? in
            if let p = plans[s.id] { return Item(script: s, date: p.date, kind: p.kind, inCalendar: p.inCalendar) }
            guard let d = date(notionDate: s.notionDate, time: s.notionTime) else { return nil }
            return Item(script: s, date: d, kind: defaultKind(for: s), inCalendar: false)
        }
        .sorted { $0.date < $1.date }
    }

    /// Группы по дням; прошедшие дни (до сегодня) не показываются.
    struct Day: Identifiable, Equatable {
        var day: Date
        var items: [Item]
        var id: Date { day }
    }

    static func days(_ items: [Item], now: Date = Date(), calendar: Calendar = .current) -> [Day] {
        let today = calendar.startOfDay(for: now)
        let upcoming = items.filter { $0.date >= today }
        let grouped = Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { key in
            Day(day: key, items: (grouped[key] ?? []).sorted { $0.date < $1.date })
        }
    }
}

/// Событие в календаре iOS: только запись, приложение календарь не читает.
enum CalendarExport {
    enum Failure: LocalizedError {
        case denied, failed
        var errorDescription: String? {
            switch self {
            case .denied: "Нет доступа к календарю. Einstellungen → Apps → Студия → Kalender → Nur hinzufügen."
            case .failed: "Не получилось добавить событие. Попробуй ещё раз."
            }
        }
    }

    static func event(for item: PlanMath.Item, store: EKEventStore) -> EKEvent {
        let e = EKEvent(eventStore: store)
        e.title = "\(item.kind.title): \(item.script.title)"
        e.startDate = item.date
        e.endDate = item.date.addingTimeInterval(item.kind == .shoot ? 3600 : 900)
        e.notes = [item.script.body.hook, item.script.body.cta].filter { !$0.isEmpty }.joined(separator: "\n\n")
        e.addAlarm(EKAlarm(relativeOffset: -30 * 60))
        e.calendar = store.defaultCalendarForNewEvents
        return e
    }

    static func add(_ item: PlanMath.Item) async throws {
        let store = EKEventStore()
        let granted = try await store.requestWriteOnlyAccessToEvents()
        guard granted else { throw Failure.denied }
        do { try store.save(event(for: item, store: store), span: .thisEvent) } catch { throw Failure.failed }
    }
}
