import SwiftUI

// MARK: - Practice configuration

/// Everything needed to start a practice session, in one hashable value so it
/// can travel through navigation and sheet presentation.
struct PracticeConfiguration: Hashable, Identifiable {
    let mode: PracticeMode
    let bookID: String?
    let sectionID: String?
    let category: VocabCategory?
    let scope: ExtraPracticeScope?

    var id: String {
        [
            mode.rawValue,
            bookID ?? "-",
            sectionID ?? "-",
            category?.rawValue ?? "-",
            scope?.rawValue ?? "-",
        ].joined(separator: "|")
    }

    static func section(bookID: String, sectionID: String, category: VocabCategory) -> PracticeConfiguration {
        PracticeConfiguration(
            mode: .main,
            bookID: bookID,
            sectionID: sectionID,
            category: category,
            scope: nil
        )
    }

    static func drill(scope: ExtraPracticeScope) -> PracticeConfiguration {
        PracticeConfiguration(
            mode: .extra,
            bookID: nil,
            sectionID: nil,
            category: nil,
            scope: scope
        )
    }
}

// MARK: - Routes

enum Route: Hashable {
    case book(bookID: String)
    case section(bookID: String, sectionID: String)
    case about
}

// MARK: - Router

/// Navigation state, kept out of the views so a session can be started from
/// either tab and torn down from one place.
///
/// Practice is presented as a full-screen cover rather than pushed: it is a
/// self-contained task with its own quit affordance, and modality is what stops
/// a half-finished session from being left behind in a navigation stack.
@MainActor
final class Router: ObservableObject {

    enum Tab: Hashable {
        case study
        case reports
        case settings
    }

    @Published var tab: Tab = .study
    @Published var studyPath: [Route] = []
    @Published var activePractice: PracticeConfiguration?

    func open(_ route: Route) {
        studyPath.append(route)
    }

    func startPractice(_ configuration: PracticeConfiguration) {
        activePractice = configuration
    }

    func endPractice() {
        activePractice = nil
    }

    /// Used by "Back to menu" on the summary screen — closes the session and
    /// unwinds to the book list in one step.
    func returnToLibrary() {
        activePractice = nil
        studyPath.removeAll()
        tab = .study
    }

    /// Used by "Next section".
    ///
    /// Dismisses first and re-presents on the next runloop rather than swapping
    /// the item in place: `fullScreenCover(item:)` does not reliably rebuild its
    /// content when the bound item changes while it is already presented, which
    /// would leave the finished session's summary on screen.
    func replacePractice(with configuration: PracticeConfiguration) {
        activePractice = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.activePractice = configuration
        }
    }
}
