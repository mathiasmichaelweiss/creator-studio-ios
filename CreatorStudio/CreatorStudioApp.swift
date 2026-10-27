import SwiftUI

@main
struct CreatorStudioApp: App {
    @StateObject private var settings = PrompterSettings()
    @StateObject private var scripts = ScriptStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(scripts)
        }
    }
}

/// Применяет тему и размер текста ко всему приложению.
private struct RootView: View {
    @EnvironmentObject var settings: PrompterSettings
    var body: some View {
        RecordScreen()
            .preferredColorScheme(settings.theme.scheme)
            .dynamicTypeSize(settings.textScale.dynamicType)
            .tint(Palette.brand)
    }
}
