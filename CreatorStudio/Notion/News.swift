import Foundation
import SwiftUI

/// Инфоповод из базы Notion «Инфоповоды». Её заполняет задача Claude каждые 6 часов.
struct NewsItem: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var title: String
    var summary: String = ""
    var why: String = ""
    var idea: String = ""
    var source: String = ""
    var date: String? = nil
    var topic: String = ""
    var urgency: String = ""
    var potential: Double? = nil
    var status: String = ""
}

enum NewsParser {
    static func item(page: NotionParser.JSON) -> NewsItem? {
        guard let id = page["id"] as? String, let props = page["properties"] as? NotionParser.JSON else { return nil }
        let title = NotionParser.plainText(props["Название"])
        guard !title.isEmpty else { return nil }
        let url = (props["Источник"] as? NotionParser.JSON)?["url"] as? String ?? ""
        return NewsItem(
            id: id, title: title,
            summary: NotionParser.plainText(props["Суть"]),
            why: NotionParser.plainText(props["Почему важно"]),
            idea: NotionParser.plainText(props["Идея ролика"]),
            source: url,
            date: NotionParser.dateStart(props["Дата"]),
            topic: NotionParser.plainText(props["Тема"]),
            urgency: NotionParser.plainText(props["Срочность"]),
            potential: NotionParser.number(props["Потенциал"]),
            status: NotionParser.plainText(props["Статус"])
        )
    }

    static func urgencyRank(_ u: String) -> Int {
        ["Горит", "На неделе", "Не срочно"].firstIndex(of: u) ?? 3
    }

    /// Сначала горящие, внутри по потенциалу, потом по свежести.
    static func sorted(_ items: [NewsItem]) -> [NewsItem] {
        items.sorted {
            let a = urgencyRank($0.urgency), b = urgencyRank($1.urgency)
            if a != b { return a < b }
            let pa = $0.potential ?? 0, pb = $1.potential ?? 0
            if pa != pb { return pa > pb }
            return ($0.date ?? "") > ($1.date ?? "")
        }
    }
}

enum NewsFilter: String, CaseIterable, Identifiable {
    case fresh, taken, all
    var id: String { rawValue }
    var title: String {
        switch self { case .fresh: return "Новые"; case .taken: return "Взял"; case .all: return "Все" }
    }
    func apply(_ items: [NewsItem]) -> [NewsItem] {
        switch self {
        case .fresh: return items.filter { $0.status == "Новый" || $0.status.isEmpty }
        case .taken: return items.filter { $0.status == "Взял" }
        case .all: return items
        }
    }
}

/// Инфоповоды с копией на телефоне.
@MainActor
final class NewsStore: ObservableObject {
    @Published private(set) var items: [NewsItem] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("news.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([NewsItem].self, from: data) {
            items = saved
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        guard let client = NotionClient() else { error = NotionError.noKey.errorDescription; return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let pages = try await client.queryAll(dataSource: NotionConfig.newsDataSource)
            items = NewsParser.sorted(pages.compactMap(NewsParser.item(page:)))
            save()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Нет связи с Notion."
        }
    }

    func setStatus(_ status: String, for id: String) async {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        guard let client = NotionClient() else { error = NotionError.noKey.errorDescription; return }
        let old = items[i].status
        items[i].status = status
        save()
        do {
            try await client.setSelect(pageId: id, property: "Статус", value: status)
        } catch {
            if let j = items.firstIndex(where: { $0.id == id }) { items[j].status = old }
            save()
            self.error = NotionWrite.message(for: error)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: url, options: .atomic) }
    }
}

/// Вкладка «Инфоповоды».
struct NewsSection: View {
    @EnvironmentObject var news: NewsStore
    @State private var filter: NewsFilter = .fresh

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Обновляются каждые 6 часов")
                    .font(Typo.inter(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.ink3)
                Spacer()
                Button {
                    Task { await news.refresh() }
                } label: {
                    Text(news.isLoading ? "Загружаю" : "Обновить")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .disabled(news.isLoading)
            }
            if let e = news.error {
                Text(e).font(Typo.inter(14, relativeTo: .footnote)).foregroundStyle(Palette.ink2)
            }
            ChipPicker(options: NewsFilter.allCases, selection: $filter) { $0.title }
            let list = filter.apply(news.items)
            if list.isEmpty {
                Text(news.items.isEmpty ? "Пока пусто. Нажми «Обновить»." : "Здесь ничего нет.")
                    .font(Typo.inter(15)).foregroundStyle(Palette.ink2).padding(.top, 8)
            }
            ForEach(list) { item in NewsCard(item: item) }
        }
        .task { if news.items.isEmpty { await news.refresh() } }
    }
}

private struct NewsCard: View {
    let item: NewsItem
    @EnvironmentObject var news: NewsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if !item.urgency.isEmpty { Chip(text: item.urgency, hot: item.urgency == "Горит") }
                if let p = item.potential { Chip(text: "Потенциал \(Int(p))/10", hot: false) }
                if !item.topic.isEmpty { Chip(text: item.topic, hot: false) }
                Spacer()
            }
            Text(item.title).font(Typo.inter(17, .semibold))
            if !item.summary.isEmpty {
                Text(item.summary).font(Typo.inter(15)).foregroundStyle(Palette.ink2)
            }
            if !item.why.isEmpty { Labeled(label: "Почему важно", text: item.why) }
            if !item.idea.isEmpty { Labeled(label: "Идея ролика", text: item.idea) }
            HStack(spacing: 8) {
                if let u = URL(string: item.source), !item.source.isEmpty {
                    Link("Источник", destination: u).buttonStyle(PillButtonStyle(prominent: false))
                }
                Spacer()
                if item.status != "Взял" {
                    Button("Взял") { Task { await news.setStatus("Взял", for: item.id) } }
                        .buttonStyle(PillButtonStyle())
                }
                if item.status != "Пропустить" {
                    Button("Мимо") { Task { await news.setStatus("Пропустить", for: item.id) } }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Palette.line))
    }
}

private struct Chip: View {
    let text: String
    let hot: Bool
    var body: some View {
        Text(text)
            .font(Typo.inter(12, .semibold, relativeTo: .caption))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(hot ? Color.white : Palette.ink2)
            .background(hot ? Palette.brand : Palette.chip, in: Capsule())
    }
}

private struct Labeled: View {
    let label: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typo.inter(12, .semibold, relativeTo: .caption)).foregroundStyle(Palette.ink3)
            Text(text).font(Typo.inter(15)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
