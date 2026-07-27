import Foundation

/// Loads the bundled catalog once at launch and holds it for the lifetime of
/// the app.
///
/// A load failure is surfaced rather than fatal: the app still opens, shows a
/// readable explanation, and Settings still works. Crashing on a packaging
/// mistake would be the worst possible outcome on a sideloaded build, where the
/// user has no console to look at.
@MainActor
final class ContentProvider: ObservableObject {

    let catalog: VocabCatalog
    let loadError: String?

    init() {
        do {
            catalog = try VocabCatalogLoader.load()
            loadError = nil
        } catch {
            catalog = .empty
            loadError = error.localizedDescription
            #if DEBUG
            print("[Content] Load failed: \(error)")
            #endif
        }
    }

    /// For previews and tests.
    init(catalog: VocabCatalog) {
        self.catalog = catalog
        self.loadError = nil
    }
}
