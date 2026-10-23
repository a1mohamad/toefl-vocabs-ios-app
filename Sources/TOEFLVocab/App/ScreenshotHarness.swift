#if DEBUG
import Foundation

/// Lets CI open the app directly on any screen, with realistic data already in
/// place, so every page can be photographed without UI automation.
///
/// Launched as:
///
///     xcrun simctl launch <udid> io.github.a1mohamad.toeflvocab screenshot:reports
///
/// The token deliberately avoids a leading dash: `simctl` could read `-foo` as
/// one of its own flags, and Foundation turns `-key value` argument pairs into
/// `UserDefaults` entries. `screenshot:reports` has neither problem.
///
/// Wrapped in `#if DEBUG`, so none of this exists in the Release build that
/// becomes the `.ipa` — the device-build job compiles with
/// `-configuration Release`.
enum ScreenshotHarness {

    private static let prefix = "screenshot:"

    static var requestedScreen: String? {
        for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix(prefix) {
            return String(argument.dropFirst(prefix.count))
        }
        return nil
    }

    static var isActive: Bool { requestedScreen != nil }

    // MARK: Entry point

    @MainActor
    static func prepare(progress: ProgressStore, catalog: VocabCatalog, router: Router) {
        guard let screen = requestedScreen, !catalog.isEmpty else { return }

        seed(progress: progress, catalog: catalog)

        // Select the tab immediately so its NavigationStack gets built.
        switch screen {
        case "reports": router.tab = .reports
        case "settings", "about": router.tab = .settings
        default: router.tab = .study
        }

        // Then defer the push by a tick. `navigationDestination(for:)` is
        // registered by the stack's content the first time it renders, so a
        // path set during the TabView's own onAppear resolves against an empty
        // destination table and pushes a blank screen. This only affects
        // launch-time navigation — by the time a user can tap anything, the
        // destinations are long since registered.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            navigate(to: screen, catalog: catalog, router: router)
        }
    }

    // MARK: Data

    /// Deterministic fake history, so Reports has numbers to show and the
    /// checklists have marks in them.
    ///
    /// Seeded from a fixed constant and applied in catalog order, so every run
    /// produces byte-identical screenshots — otherwise a visual diff between two
    /// CI runs would be pure noise. The store is wiped first because the
    /// simulator keeps the app container between the launches in one capture
    /// loop, and seeding nine times over would drift.
    @MainActor
    private static func seed(progress: ProgressStore, catalog: VocabCatalog) {
        progress.eraseAll()

        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func nextRandom() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }

        for (index, item) in catalog.allItems.enumerated() {
            // Leave every third word untouched so "not started" states are
            // visible in the screenshots too.
            guard index % 3 != 2 else { continue }

            let attempts = Int(nextRandom() % 7)
            for _ in 0..<attempts {
                progress.record(item.id, mode: .main, correct: nextRandom() % 10 >= 4)
            }
        }
    }

    // MARK: Navigation

    @MainActor
    private static func navigate(to screen: String, catalog: VocabCatalog, router: Router) {
        guard let book = catalog.books.first,
              let section = book.sections.first
        else { return }

        // The tip card is only worth photographing on a word that actually has
        // tips, which the first section of the first book does not.
        if screen == "practice-tip" {
            if let exemplar = tipExemplar(in: catalog) {
                router.startPractice(
                    .section(
                        bookID: exemplar.bookID,
                        sectionID: exemplar.sectionID,
                        category: exemplar.category
                    )
                )
            }
            return
        }

        switch screen {
        case "book":
            router.studyPath = [.book(bookID: book.id)]

        case "section":
            router.studyPath = [
                .book(bookID: book.id),
                .section(bookID: book.id, sectionID: section.id),
            ]

        // The practice states differ only in how far the session is driven,
        // which PracticeView handles on appear.
        case "practice", "practice-revealed", "summary":
            router.startPractice(
                .section(bookID: book.id, sectionID: section.id, category: .main)
            )

        case "about":
            router.settingsPath = [.about]

        default:
            break // "library" and anything unrecognised land on the root.
        }
    }

    /// The first word in the library carrying more than one usage tip, falling
    /// back to any word with one. Found by searching rather than hardcoded, so
    /// reordering the content cannot leave this pointing at a word with nothing
    /// to show.
    private static func tipExemplar(in catalog: VocabCatalog) -> VocabItem? {
        catalog.allItems.first { $0.usageTips.count > 1 }
            ?? catalog.allItems.first { !$0.usageTips.isEmpty }
    }

    /// The same choice again, narrowed to the session that is actually running.
    @MainActor
    private static func tipTerm(for viewModel: PracticeViewModel) -> String? {
        let queue = viewModel.queue
        let item = queue.first { $0.usageTips.count > 1 }
            ?? queue.first { !$0.usageTips.isEmpty }
        return item?.term
    }

    /// Drives a live session far enough to photograph the revealed, tip and
    /// summary states. Called from `PracticeView`, which owns the view model.
    @MainActor
    static func advance(_ viewModel: PracticeViewModel) {
        switch requestedScreen {
        case "practice-revealed":
            viewModel.answer(correct: false)

        case "practice-tip":
            // The session opens on whichever word the adaptive queue ranks
            // first, which is not necessarily the one with the tips, so step
            // forward until it comes up and then reveal it.
            guard let target = tipTerm(for: viewModel) else {
                viewModel.answer(correct: true)
                return
            }
            var tipSteps = 0
            while viewModel.phase != .finished, tipSteps < 500 {
                tipSteps += 1
                if viewModel.currentItem?.term == target {
                    if viewModel.revealedAnswer == nil { viewModel.answer(correct: true) }
                    return
                }
                if viewModel.revealedAnswer == nil {
                    viewModel.answer(correct: true)
                } else {
                    viewModel.advance()
                }
            }

        case "summary":
            // Bounded rather than `while true`: a logic slip here would hang the
            // app on the main thread and the capture step would time out with
            // nothing useful to show.
            var steps = 0
            while viewModel.phase != .finished, steps < 500 {
                steps += 1
                if viewModel.revealedAnswer == nil {
                    viewModel.answer(correct: steps % 3 != 0)
                } else {
                    viewModel.advance()
                }
            }

        default:
            break
        }
    }
}
#endif
