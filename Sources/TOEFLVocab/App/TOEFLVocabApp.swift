import SwiftUI

@main
struct TOEFLVocabApp: App {

    @StateObject private var content = ContentProvider()
    @StateObject private var progress = ProgressStore()
    @StateObject private var settings = SettingsStore()
    @StateObject private var speech = PronunciationService()
    @StateObject private var router = Router()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(content)
                .environmentObject(progress)
                .environmentObject(settings)
                .environmentObject(speech)
                .environmentObject(router)
                // Language and theme are app-level choices, so they are applied
                // once here rather than threaded through every screen.
                .environment(\.strings, settings.strings)
                .environment(\.layoutDirection, settings.settings.language.layoutDirection)
                .preferredColorScheme(settings.settings.theme.colorScheme)
        }
        .onChange(of: scenePhase) { phase in
            // Debounced writes are pending for up to ~0.6s; flush them before
            // the app can be suspended or killed in the background.
            if phase != .active {
                progress.saveNow()
                speech.stop()
            }
        }
    }
}
