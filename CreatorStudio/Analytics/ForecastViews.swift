import Charts
import SwiftUI

struct ForecastRoute: Hashable {
    let scriptId: String
}

/// Вкладка «Прогнозы»: все ролики с прогнозом и как идут относительно него.
struct ForecastSection: View {
    @EnvironmentObject var store: ScriptStore
    @EnvironmentObject var plan: PlanStore

    var body: some View {
        let list = store.scripts.filter { $0.forecast != nil }
        VStack(alignment: .leading, spacing: 12) {
            if list.isEmpty {
                Text("Прогнозов пока нет. Они приходят из базы «Прогнозы» в Notion, нажми «Обновить».")
                    .font(Typo.inter(15)).foregroundStyle(Palette.ink2)
            }
            ForEach(list) { s in
                if let f = s.forecast {
                    let facts = ForecastMath.merged(notion: f.actual, manual: plan.manualFacts[s.id] ?? [])
                    NavigationLink(value: ForecastRoute(scriptId: s.id)) {
                        ForecastRow(script: s, forecast: f, facts: facts)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ForecastRow: View {
    let script: Script
    let forecast: Forecast
    let facts: [FactPoint]

    var body: some View {
        let verdict = ForecastMath.verdict(forecast, facts: facts)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(script.title).font(Typo.inter(16, .semibold)).multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink3)
            }
            ForecastChart(forecast: forecast, facts: facts, compact: true)
                .frame(height: 90)
            HStack {
                Text("96 ч: \(ForecastMath.compact(forecast.mid[3]))")
                    .font(Typo.inter(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.ink2)
                Spacer()
                VerdictChip(verdict: verdict)
            }
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Palette.line))
        .contentShape(Rectangle())
    }
}

struct VerdictChip: View {
    let verdict: ForecastMath.Verdict
    var body: some View {
        let (bg, ink): (Color, Color) = {
            switch verdict {
            case .above: (Palette.okBg, Palette.okInk)
            case .below: (Palette.mark, Palette.ink)
            case .onTrack, .noData: (Palette.chip, Palette.ink2)
            }
        }()
        Text(verdict.text)
            .font(Typo.inter(12, .semibold, relativeTo: .caption))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(ink)
            .background(bg, in: Capsule())
    }
}

/// Коридор прогноза (заливка), ожидание (пунктир) и факт (оранжевая линия с точками).
struct ForecastChart: View {
    let forecast: Forecast
    let facts: [FactPoint]
    var compact = false

    var body: some View {
        Group {
            if compact {
                chart.chartYAxis(.hidden)
            } else {
                chart.chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(Palette.line)
                        if let n = v.as(Double.self) {
                            AxisValueLabel { Text(ForecastMath.compact(n)).font(Typo.inter(11)) }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("График: прогноз \(ForecastMath.compact(forecast.mid[3])) за 96 часов. \(ForecastMath.verdict(forecast, facts: facts).text)")
    }

    private var chart: some View {
        let band = ForecastMath.band(forecast)
        let maxHours = max(96, facts.map(\.hours).max() ?? 0)
        return Chart {
            ForEach(band) { p in
                AreaMark(x: .value("Часы", p.hours), yStart: .value("Мин", p.lo), yEnd: .value("Макс", p.hi))
                    .foregroundStyle(Palette.brand.opacity(0.14))
                    .interpolationMethod(.monotone)
            }
            ForEach(band) { p in
                LineMark(x: .value("Часы", p.hours), y: .value("Просмотры", p.mid), series: .value("Ряд", "Прогноз"))
                    .foregroundStyle(Palette.ink3)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .interpolationMethod(.monotone)
            }
            ForEach(facts, id: \.hours) { p in
                LineMark(x: .value("Часы", p.hours), y: .value("Просмотры", p.views), series: .value("Ряд", "Факт"))
                    .foregroundStyle(Palette.brand)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(x: .value("Часы", p.hours), y: .value("Просмотры", p.views))
                    .foregroundStyle(Palette.brand)
                    .symbolSize(compact ? 18 : 36)
            }
        }
        .chartXScale(domain: 0...maxHours)
        .chartXAxis {
            AxisMarks(values: [0, 24, 48, 72, 96]) { v in
                AxisGridLine().foregroundStyle(Palette.line)
                if !compact, let h = v.as(Double.self) {
                    AxisValueLabel { Text("\(Int(h)) ч").font(Typo.inter(11)) }
                }
            }
        }
    }
}

/// Один ролик: большой график, метрики прогноза и ручной ввод факта.
struct ForecastDetail: View {
    let scriptId: String
    @EnvironmentObject var store: ScriptStore
    @EnvironmentObject var plan: PlanStore
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Double = 24
    @State private var viewsText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Palette.chip, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Назад")

                if let s = store.scripts.first(where: { $0.id == scriptId }), let f = s.forecast {
                    let manual = plan.manualFacts[s.id] ?? []
                    let facts = ForecastMath.merged(notion: f.actual, manual: manual)
                    Text(s.title).font(Typo.inter(24, .bold, relativeTo: .title)).tracking(-0.4)
                    HStack {
                        VerdictChip(verdict: ForecastMath.verdict(f, facts: facts))
                        if !f.confidence.isEmpty {
                            Text("Уверенность: \(f.confidence)")
                                .font(Typo.inter(12, .semibold, relativeTo: .caption)).foregroundStyle(Palette.ink2)
                        }
                    }
                    if let now = ForecastMath.now(f, facts: facts) {
                        NowCard(fact: now.fact, expected: now.expected)
                    }
                    ForecastChart(forecast: f, facts: facts)
                        .frame(height: 240)
                        .padding(14)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    metrics(f)
                    factInput(scriptId: s.id)
                    if !manual.isEmpty {
                        Text("Введено вручную").font(Typo.inter(13, .semibold, relativeTo: .footnote)).foregroundStyle(Palette.ink3)
                        ForEach(manual, id: \.hours) { p in
                            HStack {
                                Text("\(Self.hoursText(p.hours)): \(ForecastMath.compact(p.views))").font(Typo.inter(15))
                                Spacer()
                                Button("Удалить") { plan.removeFact(hours: p.hours, for: s.id) }
                                    .buttonStyle(PillButtonStyle(prominent: false))
                            }
                        }
                    }
                    if !f.why.isEmpty {
                        Text(f.why).font(Typo.inter(14, relativeTo: .footnote)).foregroundStyle(Palette.ink2)
                    }
                } else {
                    Text("Прогноз не найден. Обнови сценарии.").font(Typo.inter(15)).foregroundStyle(Palette.ink2)
                }
            }
            .padding(20)
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func metrics(_ f: Forecast) -> some View {
        let st = f.stats
        let rows: [CompareRow] = [
            CompareRow(label: "24 ч", plan: ForecastMath.compact(f.mid[0]), fact: nil),
            CompareRow(label: "48 ч", plan: ForecastMath.compact(f.mid[1]), fact: nil),
            CompareRow(label: "72 ч", plan: ForecastMath.compact(f.mid[2]), fact: nil),
            CompareRow(label: "96 ч", plan: ForecastMath.compact(f.mid[3]), fact: nil),
            CompareRow(label: "Пропуски", plan: f.skip, fact: st?.skip.map(ForecastMath.pct),
                       better: Self.better(plan: ForecastMath.percent(f.skip), fact: st?.skip, lowerIsBetter: true)),
            CompareRow(label: "Досмотр", plan: "", fact: st?.retention.map(ForecastMath.pct)),
            CompareRow(label: "Пересылки", plan: f.shares, fact: st.flatMap { $0.rate($0.shares) }.map(ForecastMath.pct),
                       better: Self.better(plan: ForecastMath.percent(f.shares), fact: st.flatMap { $0.rate($0.shares) })),
            CompareRow(label: "Сохранения", plan: f.saves, fact: st.flatMap { $0.rate($0.saves) }.map(ForecastMath.pct),
                       better: Self.better(plan: ForecastMath.percent(f.saves), fact: st.flatMap { $0.rate($0.saves) })),
            CompareRow(label: "Подписки", plan: f.subs, fact: st?.subs.map { String(Int($0)) }),
            CompareRow(label: "Лайки", plan: "", fact: st?.likes.map { ForecastMath.compact($0) }),
            CompareRow(label: "Комментарии", plan: "", fact: st?.comments.map { ForecastMath.compact($0) }),
        ].filter { !$0.plan.isEmpty || $0.fact != nil }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(rows, id: \.label) { r in
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.label).font(Typo.inter(12, .medium, relativeTo: .caption)).foregroundStyle(Palette.ink3)
                    if let fact = r.fact {
                        Text(fact).font(Typo.inter(16, .semibold))
                            .foregroundStyle(r.better == true ? Palette.okInk : Palette.ink)
                        if !r.plan.isEmpty {
                            Text("прогноз \(r.plan)").font(Typo.inter(12, relativeTo: .caption)).foregroundStyle(Palette.ink3)
                        }
                    } else {
                        Text(r.plan).font(Typo.inter(16, .semibold))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            }
        }
    }

    /// Факт лучше прогноза? Для пропусков лучше меньше.
    static func better(plan: Double?, fact: Double?, lowerIsBetter: Bool = false) -> Bool? {
        guard let plan, let fact else { return nil }
        return lowerIsBetter ? fact < plan : fact > plan
    }

    private func factInput(scriptId: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Добавить факт из Insights").font(Typo.inter(13, .semibold, relativeTo: .footnote)).foregroundStyle(Palette.ink3)
            Stepper(value: $hours, in: 1...168, step: 1) {
                Text("Через \(Self.hoursText(hours)) после публикации").font(Typo.inter(15, .medium))
            }
            HStack {
                TextField("Просмотры", text: $viewsText)
                    .keyboardType(.numberPad)
                    .font(Typo.inter(16))
                    .padding(12)
                    .background(Palette.soft, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                Button("Сохранить") {
                    if let v = FactInput.views(viewsText) {
                        plan.addFact(FactPoint(hours: hours, views: v), for: scriptId)
                        viewsText = ""
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(FactInput.views(viewsText) == nil)
            }
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    static func hoursText(_ h: Double) -> String { "\(Int(h)) ч" }
}

enum FactInput {
    /// «20 631», «20.631», «20631» → 20631. Пусто и ноль не принимаются.
    static func views(_ text: String) -> Double? {
        let digits = text.filter(\.isNumber)
        guard let v = Double(digits), v > 0 else { return nil }
        return v
    }
}

private struct CompareRow {
    var label: String
    var plan: String
    var fact: String?
    var better: Bool? = nil
}

/// «Сейчас 9 111 за 17 ч, прогноз на это время ≈ 4 950».
private struct NowCard: View {
    let fact: FactPoint
    let expected: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Сейчас, \(Int(fact.hours.rounded())) ч").font(Typo.inter(12, .medium, relativeTo: .caption)).foregroundStyle(Palette.ink3)
                Text(ForecastMath.compact(fact.views)).font(Typo.inter(24, .bold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Прогноз на это время").font(Typo.inter(12, .medium, relativeTo: .caption)).foregroundStyle(Palette.ink3)
                Text("≈ \(ForecastMath.compact(expected))").font(Typo.inter(24, .bold)).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
