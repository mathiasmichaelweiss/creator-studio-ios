import SwiftUI
import UIKit

/// Выбор сценария из Notion перед записью. Можно взять основной текст или вариацию.
struct ScriptPicker: View {
    @EnvironmentObject var settings: PrompterSettings
    @EnvironmentObject var store: ScriptStore
    @Environment(\.dismiss) private var dismiss
    @State private var tab: StudioTab = .scripts
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SheetHeader(title: "Студия") { dismiss() }
                    ChipPicker(options: StudioTab.allCases, selection: $tab) { $0.title }
                    syncRow
                    if let error = store.error {
                        Text(error)
                            .font(Typo.inter(14, relativeTo: .footnote))
                            .foregroundStyle(Palette.ink2)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.mark, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    }
                    switch tab {
                    case .scripts:
                        if store.scripts.isEmpty {
                            Text("Пока пусто. Добавь ключ Notion в настройках и нажми «Обновить».")
                                .font(Typo.inter(15))
                                .foregroundStyle(Palette.ink2)
                                .padding(.top, 8)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(ScriptFolder.visible(store.scripts)) { folder in
                                NavigationLink(value: folder) {
                                    FolderCard(folder: folder, scripts: folder.items(store.scripts))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button("Свой текст") { settings.scriptTitle = ""; showEditor = true }
                            .buttonStyle(PillButtonStyle(prominent: false))
                            .padding(.top, 6)
                    case .news:
                        NewsSection()
                    case .plan:
                        PlanSection()
                    case .forecasts:
                        ForecastSection()
                    }
                }
                .padding(20)
            }
            .foregroundStyle(Palette.ink)
            .background(Palette.bg.ignoresSafeArea())
            .navigationDestination(for: ScriptFolder.self) { folder in
                FolderView(folder: folder)
            }
            .navigationDestination(for: Script.self) { script in
                ScriptDetail(script: script) { text, title in
                    settings.script = text
                    settings.scriptTitle = title
                    dismiss()
                }
            }
            .navigationDestination(for: ForecastRoute.self) { route in
                ForecastDetail(scriptId: route.scriptId)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showEditor) { ScriptEditor() }
        .task { if store.scripts.isEmpty, store.hasKey { await store.refresh() } }
    }

    private var syncRow: some View {
        HStack(spacing: 10) {
            Text(syncText)
                .font(Typo.inter(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.ink3)
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                HStack(spacing: 6) {
                    if store.isLoading { ProgressView().controlSize(.small).tint(Palette.btnInk) }
                    Text(store.isLoading ? "Загружаю" : "Обновить")
                }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(store.isLoading)
        }
    }

    private var syncText: String {
        guard let d = store.lastSync else { return "Ещё не загружено" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return "Обновлено \(f.string(from: d)) · \(store.scripts.count)"
    }
}

enum StudioTab: String, CaseIterable, Identifiable {
    case scripts, news, plan, forecasts
    var id: String { rawValue }
    var title: String {
        switch self { case .scripts: "Сценарии"; case .news: "Поводы"; case .plan: "План"; case .forecasts: "Прогнозы" }
    }
}

private struct ScriptRow: View {
    let script: Script
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TagChip(script.type)
                TagChip(script.status)
                if let v = ScriptScore.views(script) { TagChip(ScriptScore.short(v)) }
                if ScriptScore.provocative(script) != nil { TagChip("Провокация") }
                else if !script.variants.isEmpty { TagChip("+\(script.variants.count) вар.") }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink3)
            }
            Text(script.title).font(Typo.inter(17, .semibold))
            if !script.body.hook.isEmpty {
                Text(script.body.hook)
                    .font(Typo.inter(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Palette.line))
        .contentShape(Rectangle())
    }
}

private struct TagChip: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(Typo.inter(12, .semibold, relativeTo: .caption))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(Palette.ink2)
                .background(Palette.chip, in: Capsule())
        }
    }
}

/// Пункт выбора текста: основной или одна из вариаций.
struct VariantChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let variant: ScriptVariant?

    static func list(for script: Script) -> [VariantChoice] {
        [VariantChoice(id: "main", title: "Основной", variant: nil)] +
            script.variants
                .sorted { ScriptScore.isProvocative($0) && !ScriptScore.isProvocative($1) }
                .map { VariantChoice(id: $0.id, title: ScriptScore.isProvocative($0) ? "Провокация" : $0.kind, variant: $0) }
    }
}

private struct ScriptDetail: View {
    let script: Script
    @EnvironmentObject var store: ScriptStore
    @State private var copied = false
    let onUse: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choice: VariantChoice

    init(script: Script, onUse: @escaping (String, String) -> Void) {
        self.script = script
        self.onUse = onUse
        _choice = State(initialValue: VariantChoice.list(for: script)[0])
    }

    var body: some View {
        let text = script.body(for: choice.variant)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                            .frame(width: 40, height: 40)
                            .background(Palette.chip, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Назад")
                    Spacer()
                }
                Text(script.title).font(Typo.inter(24, .bold, relativeTo: .title)).tracking(-0.4)
                StatusMenu(script: store.scripts.first { $0.id == script.id } ?? script)
                if let e = store.error {
                    Text(e).font(Typo.inter(13, relativeTo: .footnote)).foregroundStyle(Palette.ink2)
                }
                ScoreCard(script: script)
                if !script.variants.isEmpty {
                    ChipPicker(options: VariantChoice.list(for: script), selection: $choice) { $0.title }
                }
                if text.isEmpty {
                    Text("В Notion у этого сценария нет текста. Добавь раздел «Текст» на странице.")
                        .font(Typo.inter(15)).foregroundStyle(Palette.ink2)
                } else {
                    Part(label: "Хук", text: text.hook)
                    ForEach(Array(text.sections.enumerated()), id: \.offset) { _, s in
                        Part(label: s.label, text: s.text)
                    }
                    Part(label: "Призыв", text: text.cta)
                }
                if StatusFlow.usesPrompter(script) {
                    Button {
                        onUse(text.prompterText, script.title)
                    } label: {
                        Text("Взять в суфлёр").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(text.isEmpty)
                    .padding(.top, 6)
                } else {
                    Button {
                        UIPasteboard.general.string = text.prompterText
                        copied = true
                    } label: {
                        Text(copied ? "Скопировано" : "Скопировать текст").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(text.isEmpty)
                    .padding(.top, 6)
                }
            }
            .padding(20)
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct Part: View {
    let label: String?
    let text: String
    var body: some View {
        if !text.trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let label, !label.isEmpty {
                    Text(label).font(Typo.inter(13, .semibold, relativeTo: .footnote)).foregroundStyle(Palette.ink3)
                }
                Text(text).font(Typo.inter(16)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        }
    }
}

// MARK: Папки

private struct FolderCard: View {
    let folder: ScriptFolder
    let scripts: [Script]

    var body: some View {
        let ready = StatusFilter.ready.count(scripts)
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.brand)
                Image(systemName: folder.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            Spacer(minLength: 4)
            Text(folder.title).font(Typo.inter(18, .semibold))
            Text(ready > 0 ? "\(scripts.count) · \(ready) к съёмке" : "\(scripts.count)")
                .font(Typo.inter(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.ink3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Palette.line))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct FolderView: View {
    let folder: ScriptFolder
    @EnvironmentObject var store: ScriptStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter: StatusFilter = .all

    var body: some View {
        let inFolder = folder.items(store.scripts)
        let list = filter.apply(inFolder)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                            .frame(width: 40, height: 40)
                            .background(Palette.chip, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Назад")
                    Text(folder.title).font(Typo.inter(24, .bold, relativeTo: .title)).tracking(-0.4)
                    Spacer()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(StatusFilter.allCases) { f in
                            let on = f == filter
                            Button { withAnimation(.easeOut(duration: 0.15)) { filter = f } } label: {
                                Text("\(f.title) \(f.count(inFolder))")
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
                if list.isEmpty {
                    Text(inFolder.isEmpty ? "В этой папке пока ничего нет." : "В этом статусе ничего нет.")
                        .font(Typo.inter(15))
                        .foregroundStyle(Palette.ink2)
                        .padding(.top, 8)
                }
                ForEach(list) { script in
                    NavigationLink(value: script) { ScriptRow(script: script) }
                        .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Оценка в карточке сценария: просмотры за 96 ч, вирусность, есть ли провокационная версия.
private struct ScoreCard: View {
    let script: Script

    var body: some View {
        let views = ScriptScore.views(script)
        let virality = ScriptScore.virality(script)
        let provocative = ScriptScore.provocative(script)
        if views != nil || virality != nil || provocative != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    if let views {
                        Metric(label: "Просмотры за 96 ч", value: ScriptScore.short(views))
                    }
                    if let virality {
                        Metric(label: "Вирусность", value: virality)
                    }
                    Spacer(minLength: 0)
                }
                if provocative != nil {
                    Text("Есть провокационная версия. Выбери её ниже.")
                        .font(Typo.inter(13, .medium, relativeTo: .footnote))
                        .foregroundStyle(Palette.ink2)
                }
                if script.forecast != nil {
                    NavigationLink(value: ForecastRoute(scriptId: script.id)) {
                        Text("Открыть прогноз").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        }
    }
}

private struct Metric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typo.inter(12, .semibold, relativeTo: .caption)).foregroundStyle(Palette.ink3)
            Text(value).font(Typo.inter(20, .bold))
        }
    }
}

/// Статус сценария: меняется прямо здесь и сохраняется в Notion.
private struct StatusMenu: View {
    let script: Script
    @EnvironmentObject var store: ScriptStore

    var body: some View {
        let options = StatusFlow.options(for: ScriptFolder.of(type: script.type))
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    Task { await store.setStatus(option, for: script.id) }
                } label: {
                    if option == script.status { Label(option, systemImage: "checkmark") } else { Text(option) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("Статус").font(Typo.inter(13, .semibold, relativeTo: .footnote)).foregroundStyle(Palette.ink3)
                Text(script.status.isEmpty ? "Не указан" : script.status).font(Typo.inter(16, .semibold))
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink3)
            }
            .padding(14)
            .foregroundStyle(Palette.ink)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        }
        .accessibilityLabel("Статус: \(script.status)")
    }
}
