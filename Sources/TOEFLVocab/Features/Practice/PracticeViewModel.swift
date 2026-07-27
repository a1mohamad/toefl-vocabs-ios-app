import Foundation

/// The practice state machine.
///
/// One epoch = one pass through the queue. The queue is built once when the
/// session starts and is *not* re-sorted mid-session: re-ranking after every
/// answer would make words jump around under the user and turn a 12-word
/// section into an unpredictable loop. Re-ordering happens on the next entry,
/// which is exactly the promise — "open a section, worst words first".
@MainActor
final class PracticeViewModel: ObservableObject {

    enum Phase: Equatable {
        case question
        case revealed(correct: Bool)
        case finished
    }

    struct Outcome: Equatable {
        let answered: Int
        let correct: Int
        let cyclesCompleted: Int

        var accuracy: Double { answered == 0 ? 0 : Double(correct) / Double(answered) }
    }

    // MARK: Published state

    @Published private(set) var queue: [VocabItem] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var phase: Phase = .question
    /// Live stats for the current word, so the checklist updates the instant an
    /// answer lands rather than after a store round trip.
    @Published private(set) var currentStats: WordStats?
    @Published var showQuitConfirmation = false
    /// Set when the user quits; the container watches this to dismiss.
    @Published private(set) var dismissRequested = false

    // MARK: Session identity

    let configuration: PracticeConfiguration
    let theme: BookTheme
    /// Content-derived heading (a section title). Not localizable — it is data.
    let headerTitle: String?
    /// Used instead of `headerTitle` for the drill, which has no section.
    let headerTitleKey: StringKey?
    let headerSubtitleKey: StringKey?

    // MARK: Private

    private let catalog: VocabCatalog
    private let progress: ProgressStore
    private var startedAt = Date()
    private var answeredCount = 0
    private var correctCount = 0
    private var cyclesCompleted = 0
    private var didFinalize = false

    // MARK: Init

    init(configuration: PracticeConfiguration, catalog: VocabCatalog, progress: ProgressStore) {
        self.configuration = configuration
        self.catalog = catalog
        self.progress = progress

        let book = configuration.bookID.flatMap { catalog.book($0) }
        let section = book.flatMap { book in configuration.sectionID.flatMap { book.section($0) } }

        self.theme = book?.theme ?? .indigo

        switch configuration.mode {
        case .main:
            if let section, let book {
                self.headerTitle = "\(book.shortTitle) · \(section.title)"
            } else if let section {
                self.headerTitle = section.title
            } else {
                self.headerTitle = nil
            }
            self.headerTitleKey = nil
            self.headerSubtitleKey = configuration.category?.titleKey

        case .extra:
            self.headerTitle = nil
            self.headerTitleKey = .reportsExtraPractice
            self.headerSubtitleKey = configuration.scope?.titleKey
        }

        self.queue = Self.buildQueue(configuration: configuration, catalog: catalog, progress: progress)
        self.currentStats = queue.first.flatMap { progress.stats(for: $0.id, mode: configuration.mode) }
        if queue.isEmpty { self.phase = .finished }
    }

    // MARK: Derived

    var currentItem: VocabItem? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    var isOnLastItem: Bool { index >= queue.count - 1 }

    var positionText: (current: Int, total: Int) {
        (min(index + 1, queue.count), queue.count)
    }

    var progressFraction: Double {
        guard !queue.isEmpty else { return 0 }
        return Double(index) / Double(queue.count)
    }

    var outcome: Outcome {
        Outcome(answered: answeredCount, correct: correctCount, cyclesCompleted: cyclesCompleted)
    }

    /// Checklist to draw. Falls back to an empty strip for a never-seen word.
    var checklist: ChecklistDisplay {
        currentStats?.checklist ?? ChecklistDisplay(marks: [], isRecap: false)
    }

    /// Lifetime tallies for the current word. Shown during the drill, where
    /// "how often have I got this one wrong?" is the whole point.
    var currentTallies: (correct: Int, incorrect: Int) {
        let main = currentItem.flatMap { progress.stats(for: $0.id, mode: .main) }
        let extra = currentItem.flatMap { progress.stats(for: $0.id, mode: .extra) }
        return (
            (main?.correct ?? 0) + (extra?.correct ?? 0),
            (main?.incorrect ?? 0) + (extra?.incorrect ?? 0)
        )
    }

    var revealedAnswer: Bool? {
        if case .revealed(let correct) = phase { return correct }
        return nil
    }

    // MARK: Actions

    func answer(correct: Bool) {
        guard phase == .question, let item = currentItem else { return }

        let before = progress.stats(for: item.id, mode: configuration.mode)?.completedCyclesThisRun ?? 0
        let updated = progress.record(item.id, mode: configuration.mode, correct: correct)
        if updated.completedCyclesThisRun > before { cyclesCompleted += 1 }

        answeredCount += 1
        if correct { correctCount += 1 }

        currentStats = updated
        phase = .revealed(correct: correct)
    }

    func advance() {
        guard revealedAnswer != nil else { return }

        if index + 1 < queue.count {
            index += 1
            phase = .question
            currentStats = progress.stats(for: queue[index].id, mode: configuration.mode)
        } else {
            finalize(completed: true)
            phase = .finished
        }
    }

    /// "Practise again" — rebuilds the queue so the words just answered wrong
    /// come back to the front.
    func restart() {
        queue = Self.buildQueue(configuration: configuration, catalog: catalog, progress: progress)
        index = 0
        answeredCount = 0
        correctCount = 0
        cyclesCompleted = 0
        didFinalize = false
        startedAt = Date()
        currentStats = queue.first.flatMap { progress.stats(for: $0.id, mode: configuration.mode) }
        phase = queue.isEmpty ? .finished : .question
    }

    func requestQuit() {
        // Nothing is at risk mid-word, so skip the dialog when no answer has
        // been given yet — a confirmation that is always trivially safe to
        // dismiss trains people to tap through it.
        if answeredCount == 0 {
            confirmQuit()
        } else {
            showQuitConfirmation = true
        }
    }

    func confirmQuit() {
        finalize(completed: false)
        dismissRequested = true
    }

    // MARK: Finalisation

    /// Writes the session record exactly once, whether the user finished or bailed.
    private func finalize(completed: Bool) {
        guard !didFinalize else { return }
        didFinalize = true

        // Nothing answered means nothing worth recording in the timeline.
        guard answeredCount > 0 else { return }

        progress.appendSession(
            SessionRecord(
                mode: configuration.mode,
                bookID: configuration.bookID,
                sectionID: configuration.sectionID,
                category: configuration.category,
                startedAt: startedAt,
                finishedAt: Date(),
                answered: answeredCount,
                correct: correctCount,
                completed: completed
            )
        )
        progress.saveNow()
    }

    // MARK: Queue building

    private static func buildQueue(
        configuration: PracticeConfiguration,
        catalog: VocabCatalog,
        progress: ProgressStore
    ) -> [VocabItem] {
        switch configuration.mode {
        case .main:
            guard let bookID = configuration.bookID,
                  let sectionID = configuration.sectionID,
                  let category = configuration.category
            else { return [] }

            let items = catalog.items(bookID: bookID, sectionID: sectionID, category: category)
            return AdaptiveOrdering.order(items) { progress.stats(for: $0, mode: .main) }

        case .extra:
            return AdaptiveOrdering.extraPracticeQueue(
                items: catalog.allItems,
                limit: (configuration.scope ?? .weakest25).limit,
                mainStats: { progress.stats(for: $0, mode: .main) },
                extraStats: { progress.stats(for: $0, mode: .extra) }
            )
        }
    }
}
