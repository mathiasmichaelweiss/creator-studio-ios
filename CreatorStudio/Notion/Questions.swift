import Foundation
import SwiftUI

/// Вопрос аудитории из базы Notion «Вопросы аудитории» (из комментариев под рилсами).
struct AudienceQuestion: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var title: String
    var topic: String = ""
    var likes: Double? = nil
    var reel: String = ""
    var date: String? = nil
    var status: String = ""
}

enum QuestionParser {
    static func item(page: NotionParser.JSON) -> AudienceQuestion? {
        guard let id = page["id"] as? String, let props = page["properties"] as? NotionParser.JSON else { return nil }
        let title = NotionParser.plainText(props["Вопрос"])
        guard !title.isEmpty else { return nil }
        return AudienceQuestion(
            id: id, title: title,
            topic: NotionParser.plainText(props["Тема"]),
            likes: NotionParser.number(props["Лайки"]),
            reel: (props["Рилс"] as? NotionParser.JSON)?["url"] as? String ?? "",
            date: NotionParser.dateStart(props["Дата"]),
            status: NotionParser.plainText(props["Статус"])
        )
    }

    /// Сначала новые, внутри по лайкам, потом по свежести.
    static func sorted(_ items: [AudienceQuestion]) -> [AudienceQuestion] {
        items.sorted {
            let a = $0.status == "Новый" || $0.status.isEmpty, b = $1.status == "Новый" || $1.status.isEmpty
            if a != b { return a }
            let la = $0.likes ?? 0, lb = $1.likes ?? 0
            if la != lb { return la > lb }
            return ($0.date ?? "") > ($1.date ?? "")
        }
    }

    /// Темы для фильтра в порядке частоты; «Все» первой.
    static func topics(_ items: [AudienceQuestion]) -> [String] {
        var count: [String: Int] = [:]
        for q in items where !q.topic.isEmpty { count[q.topic, default: 0] += 1 }
        return ["Все"] + count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    static func filter(_ items: [AudienceQuestion], topic: String, showAll: Bool) -> [AudienceQuestion] {
        items.filter { q in
            (topic == "Все" || q.topic == topic) && (showAll || q.status == "Новый" || q.status.isEmpty)
        }
    }

    /// Свойства новой строки в «Сценариях» из вопроса.
    static func scriptProperties(for q: AudienceQuestion) -> [String: Any] {
        func text(_ s: String) -> [String: Any] { ["rich_text": [["text": ["content": s]]]] }
        var note = "Из вопросов аудитории"
        if !q.reel.isEmpty { note += ": \(q.reel)" }
        return [
            "Название": ["title": [["text": ["content": q.title]]]],
            "Тип": ["select": ["name": "Рилс"]],
            "Статус": ["select": ["name": "Идея"]],
            "Хук": text(q.title),
            "Заметки": text(note),
        ]
    }
}

@MainActor
final class QuestionStore: ObservableObject {
    @Published private(set) var items: [AudienceQuestion] = []
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published var notice: String?

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("questions.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([AudienceQuestion].self, from: data) {
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
            let pages = try await client.queryAll(dataSource: NotionConfig.questionsDataSource)
            items = QuestionParser.sorted(pages.compactMap(QuestionParser.item(page:)))
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

    /// Черновик в «Сценариях» и отметка «Взял» у вопроса.
    func toScript(_ q: AudienceQuestion) async {
        guard let client = NotionClient() else { error = NotionError.noKey.errorDescription; return }
        do {
            try await client.createPage(dataSource: NotionConfig.scriptsDataSource,
                                        properties: QuestionParser.scriptProperties(for: q))
            notice = "Добавлено в «Сценарии» как идея. Нажми «Обновить» во вкладке «Сценарии»."
            await setStatus("Взял", for: q.id)
        } catch {
            self.error = NotionWrite.message(for: error)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: url, options: .atomic) }
    }
}

/// Вкладка «Вопросы».
struct QuestionsSection: View {
    @EnvironmentObject var questions: QuestionStore
    @State private var topic = "Все"
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Вопросы из комментариев")
                    .font(Typo.inter(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.ink3)
                Spacer()
                Button { Task { await questions.refresh() } } label: {
                    Text(questions.isLoading ? "Загружаю" : "Обновить")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .disabled(questions.isLoading)
            }
            if let e = questions.error {
                Text(e).font(Typo.inter(14, relativeTo: .footnote)).foregroundStyle(Palette.ink2)
            }
            if let n = questions.notice {
                Text(n).font(Typo.inter(14, relativeTo: .footnote)).foregroundStyle(Palette.okInk)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(QuestionParser.topics(questions.items), id: \.self) { t in
                        let on = t == topic
                        Button { withAnimation(.easeOut(duration: 0.15)) { topic = t } } label: {
                            Text(t)
                                .font(Typo.inter(14, on ? .semibold : .medium))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .foregroundStyle(on ? Palette.btnInk : Palette.ink2)
                                .background(on ? Palette.btn : Palette.chip, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            Toggle("Показывать взятые и пропущенные", isOn: $showAll)
                .font(Typo.inter(14))
                .tint(Palette.brand)
            let list = QuestionParser.filter(questions.items, topic: topic, showAll: showAll)
            if list.isEmpty {
                Text(questions.items.isEmpty ? "Пока пусто. Нажми «Обновить»." : "Здесь ничего нет.")
                    .font(Typo.inter(15)).foregroundStyle(Palette.ink2).padding(.top, 8)
            }
            ForEach(list) { q in QuestionCard(q: q) }
        }
        .task { if questions.items.isEmpty { await questions.refresh() } }
    }
}

private struct QuestionCard: View {
    let q: AudienceQuestion
    @EnvironmentObject var questions: QuestionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if !q.topic.isEmpty { chip(q.topic) }
                if let l = q.likes, l > 0 { chip("\(Int(l)) лайков") }
                if !q.status.isEmpty && q.status != "Новый" { chip(q.status) }
                Spacer()
            }
            Text(q.title).font(Typo.inter(17, .semibold)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let u = URL(string: q.reel), !q.reel.isEmpty {
                    Link("Рилс", destination: u).buttonStyle(PillButtonStyle(prominent: false))
                }
                Spacer()
                if q.status != "Взял" {
                    Button("В сценарии") { Task { await questions.toScript(q) } }
                        .buttonStyle(PillButtonStyle())
                }
                if q.status != "Мимо" {
                    Button("Мимо") { Task { await questions.setStatus("Мимо", for: q.id) } }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Palette.line))
    }

    private func chip(_ t: String) -> some View {
        Text(t)
            .font(Typo.inter(12, .semibold, relativeTo: .caption))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(Palette.ink2)
            .background(Palette.chip, in: Capsule())
    }
}
