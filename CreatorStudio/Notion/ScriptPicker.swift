import SwiftUI

/// Выбор сценария из Notion перед записью. Можно взять основной текст или вариацию.
struct ScriptPicker: View {
    @EnvironmentObject var settings: PrompterSettings
    @EnvironmentObject var store: ScriptStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter: StatusFilter = .ready
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
                        ChipPicker(options: StatusFilter.allCases, selection: $filter) { $0.title }
                        let list = filter.apply(store.scripts)
                        if list.isEmpty {
                            Text(store.scripts.isEmpty
                                 ? "Пока пусто. Добавь ключ Notion в настройках и нажми «Обновить»."
                                 : "В этом статусе ничего нет.")
                                .font(Typo.inter(15))
                                .foregroundStyle(Palette.ink2)
                                .padding(.top, 8)
                        }
                        ForEach(list) { script in
                            NavigationLink(value: script) { ScriptRow(script: script) }
                                .buttonStyle(.plain)
                        }
                        Button("Свой текст") { settings.scriptTitle = ""; showEditor = true }
                            .buttonStyle(PillButtonStyle(prominent: false))
                            .padding(.top, 6)
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
    case scripts, plan, forecasts
    var id: String { rawValue }
    var title: String {
        switch self { case .scripts: "Сценарии"; case .plan: "План"; case .forecasts: "Прогнозы" }
    }
}

enum StatusFilter: String, CaseIterable, Identifiable {
    case ready, idea, all
    var id: String { rawValue }
    var title: String {
        switch self { case .ready: "К съёмке"; case .idea: "Идеи"; case .all: "Все" }
    }
    func apply(_ s: [Script]) -> [Script] {
        switch self {
        case .ready: s.filter { $0.status == "Готов к съёмке" }
        case .idea: s.filter { $0.status == "Идея" }
        case .all: s
        }
    }
}

private struct ScriptRow: View {
    let script: Script
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TagChip(script.type)
                TagChip(script.status)
                if !script.variants.isEmpty { TagChip("+\(script.variants.count) вар.") }
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
            script.variants.map { VariantChoice(id: $0.id, title: $0.kind, variant: $0) }
    }
}

private struct ScriptDetail: View {
    let script: Script
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
                Button {
                    onUse(text.prompterText, script.title)
                } label: {
                    Text("Взять в суфлёр").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle())
                .disabled(text.isEmpty)
                .padding(.top, 6)
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
