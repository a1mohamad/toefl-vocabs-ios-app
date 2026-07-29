import SwiftUI

@main
struct TOEFLVocabApp: App {

    @StateObject private var content = ContentProvider()
    @StateObject private var progress = ProgressStore()
    @StateObject private var settings = SettingsStore()
    @StateObject private var speech = PronunciationService()
    @StateObject private var router = Router()

    @Environment(\.scenePhase) private var scenePhase

    private var language: AppLanguage { settings.settings.language.resolved }
    private var layoutDirection: LayoutDirection { language.layoutDirection }

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
                .environment(\.layoutDirection, layoutDirection)
                // Switching language rebuilds the tree instead of re-laying out
                // the existing one. SwiftUI otherwise reuses scroll views that
                // were built for the other direction, and a reused container
                // keeps the mirroring transform its new contents do not expect.
                .id(language)
                .preferredColorScheme(settings.settings.theme.colorScheme)
                // Keeps the UIKit layer pointing the same way as the SwiftUI
                // one; see LayoutDirectionBridge for why that is not automatic.
                .onAppear { LayoutDirectionBridge.apply(layoutDirection) }
                .onChange(of: layoutDirection) { LayoutDirectionBridge.apply($0) }
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
