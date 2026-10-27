import SwiftUI

/// Временный ввод текста. На этапе 2 сценарии придут из Notion.
struct ScriptEditor: View {
    @EnvironmentObject var settings: PrompterSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $settings.script)
                .font(.system(size: 18))
                .padding(.horizontal)
                .navigationTitle("Сценарий")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Вставить") {
                            if let s = UIPasteboard.general.string { settings.script = s }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
                }
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var settings: PrompterSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Суфлёр") {
                    VStack(alignment: .leading) {
                        Text("Скорость: \(Int(settings.speed))")
                        Slider(value: $settings.speed, in: 10...150, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("Размер текста: \(Int(settings.fontSize))")
                        Slider(value: $settings.fontSize, in: 18...56, step: 1)
                    }
                    Stepper("Отсчёт перед стартом: \(settings.countdown) с", value: $settings.countdown, in: 0...5)
                }
                Section("Кадр") {
                    Toggle("Безопасная зона Reels", isOn: $settings.showSafeZone)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Готово") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}
