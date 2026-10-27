import SwiftUI

/// Вкладка «План»: что и когда снимаем или публикуем, кнопка «В календарь».
struct PlanSection: View {
    @EnvironmentObject var store: ScriptStore
    @EnvironmentObject var plan: PlanStore
    @State private var editing: Script?
    @State private var message: String?

    var body: some View {
        let items = PlanMath.items(scripts: store.scripts, plans: plan.plans)
        let days = PlanMath.days(items)
        let unplanned = store.scripts.filter { s in
            !items.contains { $0.id == s.id } && (s.status == "Готов к съёмке" || s.status == "Снято")
        }

        VStack(alignment: .leading, spacing: 14) {
            if let message {
                Text(message)
                    .font(Typo.inter(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink2)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.soft, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            }
            if days.isEmpty {
                Text("Пока ничего не запланировано. Выбери сценарий ниже и поставь дату.")
                    .font(Typo.inter(15)).foregroundStyle(Palette.ink2)
            }
            ForEach(days) { day in
                Text(Self.dayTitle(day.day))
                    .font(Typo.inter(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink3)
                    .padding(.top, 4)
                ForEach(day.items) { item in
                    PlanRow(item: item, onEdit: { editing = item.script }, onCalendar: { addToCalendar(item) })
                }
            }
            if !unplanned.isEmpty {
                Text("Без даты")
                    .font(Typo.inter(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink3)
                    .padding(.top, 8)
                ForEach(unplanned) { s in
                    Button { editing = s } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.title).font(Typo.inter(16, .semibold)).multilineTextAlignment(.leading)
                                Text(s.status).font(Typo.inter(13, relativeTo: .footnote)).foregroundStyle(Palette.ink2)
                            }
                            Spacer()
                            Image(systemName: "calendar.badge.plus").font(.system(size: 18, weight: .semibold))
                        }
                        .padding(14)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).stroke(Palette.line))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $editing) { s in
            ScheduleSheet(script: s, current: plan.plans[s.id] ?? PlanMath.items(scripts: [s], plans: [:]).first.map {
                PlanEntry(date: $0.date, kind: $0.kind)
            })
        }
    }

    private func addToCalendar(_ item: PlanMath.Item) {
        Task { @MainActor in
            do {
                try await CalendarExport.add(item)
                if plan.plans[item.id] == nil { plan.setPlan(PlanEntry(date: item.date, kind: item.kind), for: item.id) }
                plan.markInCalendar(item.id)
                message = "Добавлено в календарь, напоминание за 30 минут."
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? "Не получилось добавить событие."
            }
        }
    }

    static func dayTitle(_ d: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return "Сегодня" }
        if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(d, inSameDayAs: t) { return "Завтра" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: d).capitalized(with: f.locale)
    }
}

private struct PlanRow: View {
    let item: PlanMath.Item
    let onEdit: () -> Void
    let onCalendar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.date.formatted(.dateTime.hour().minute()))
                .font(Typo.inter(15, .semibold).monospacedDigit())
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.kind.title)
                    .font(Typo.inter(12, .semibold, relativeTo: .caption))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .foregroundStyle(item.kind == .shoot ? Color.white : Palette.ink2)
                    .background(item.kind == .shoot ? AnyShapeStyle(Palette.brand) : AnyShapeStyle(Palette.chip), in: Capsule())
                Text(item.script.title).font(Typo.inter(16, .semibold))
            }
            Spacer()
            Button(action: onCalendar) {
                Image(systemName: item.inCalendar ? "checkmark" : "calendar.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Palette.chip, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.inCalendar ? "Уже в календаре, добавить ещё раз" : "Добавить в календарь")
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).stroke(Palette.line))
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

/// Дата и вид события для одного сценария.
private struct ScheduleSheet: View {
    let script: Script
    @EnvironmentObject var plan: PlanStore
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var kind: PlanKind

    init(script: Script, current: PlanEntry?) {
        self.script = script
        _date = State(initialValue: current?.date ?? PlanSchedule.nextSlot())
        _kind = State(initialValue: current?.kind ?? PlanMath.defaultKind(for: script))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Запланировать") {
                plan.setPlan(PlanEntry(date: date, kind: kind), for: script.id)
                dismiss()
            }
            Text(script.title).font(Typo.inter(18, .semibold))
            ChipPicker(options: PlanKind.allCases, selection: $kind) { $0.title }
            DatePicker("Когда", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .tint(Palette.brand)
            if plan.plans[script.id] != nil {
                Button("Убрать из плана") {
                    plan.setPlan(nil, for: script.id)
                    dismiss()
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .foregroundStyle(Palette.ink)
        .background(Palette.bg.ignoresSafeArea())
        .presentationDetents([.large])
    }
}

enum PlanSchedule {
    /// Ближайшие 17:00 (лучшее время публикации по активности аудитории).
    static func nextSlot(now: Date = Date(), calendar: Calendar = .current) -> Date {
        var c = calendar.dateComponents([.year, .month, .day], from: now)
        c.hour = 17; c.minute = 0
        let today = calendar.date(from: c) ?? now
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
