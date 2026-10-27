import SwiftUI

@main
struct CreatorStudioApp: App {
    @StateObject private var settings = PrompterSettings()

    var body: some Scene {
        WindowGroup {
            RecordScreen()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }
}
