import Foundation

// MARK: - Summary

/// One rolled-up set of numbers, reused at every level: whole library, one
/// book, one section, one category.
struct MetricSummary: Equatable {
    let total: Int
    let seen: Int
    let completed: Int
    let mastered: Int
    let needsWork: Int
    let attempts: Int
    let correct: Int

    var incorrect: Int { max(0, attempts - correct) }
    var accuracy: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
    var seenFraction: Double { total == 0 ? 0 : Double(seen) / Double(total) }
    var completedFraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    var masteredFraction: Double { total == 0 ? 0 : Double(mastered) / Double(total) }
    var isUntouched: Bool { attempts == 0 }

    static let zero = MetricSummary(
        total: 0, seen: 0, completed: 0, mastered: 0, needsWork: 0, attempts: 0, correct: 0
    )

    static func make(items: [VocabItem], stats: (VocabID) -> WordStats?) -> MetricSummary {
        var seen = 0, completed = 0, mastered = 0, needsWork = 0, attempts = 0, correct = 0

        for item in items {
            guard let wordStats = stats(item.id), wordStats.attempts > 0 else { continue }
            seen += 1
            attempts += wordStats.attempts
            correct += wordStats.correct
            if wordStats.isCompletedThisRun { completed += 1 }
            if wordStats.isMastered { mastered += 1 }
            // "Needs work" = has actually got it wrong and is not currently on a
            // mastery streak. Deliberately not "score above a threshold" so the
            // number matches what the user would count by hand.
            if wordStats.incorrect > 0 && !wordStats.isMastered { needsWork += 1 }
        }

        return MetricSummary(
            total: items.count,
            seen: seen,
            completed: completed,
            mastered: mastered,
            needsWork: needsWork,
            attempts: attempts,
            correct: correct
        )
    }
}

// MARK: - Report shapes

struct SectionReport: Identifiable, Equatable {
    let id: String
    let bookID: String
    let sectionID: String
    let title: String
    let kind: SectionKind
    let summary: MetricSummary
}

struct BookReport: Identifiable, Equatable {
    let id: String
    let title: String
    let shortTitle: String
    let theme: BookTheme
    let summary: MetricSummary
    let sections: [SectionReport]
    let mainSummary: MetricSummary
    let extraSummary: MetricSummary
}

/// A word surfaced in "needs the most work", carrying enough context to be
/// rendered without another catalog lookup.
struct WeakWord: Identifiable, Equatable {
    var id: String { item.id.rawValue }
    let item: VocabItem
    let bookShortTitle: String
    let sectionTitle: String
    let mainStats: WordStats?
    let extraStats: WordStats?
    let score: Double

    static func == (lhs: WeakWord, rhs: WeakWord) -> Bool { lhs.id == rhs.id && lhs.score == rhs.score }
}

struct ReportData {
    let overall: MetricSummary
    let mainSummary: MetricSummary
    let extraSummary: MetricSummary
    let books: [BookReport]
    let weakest: [WeakWord]
    let recentSessions: [SessionRecord]
    let extraAttempts: Int
    let runNumber: Int
    /// Every word in the library has finished a five-answer cycle this run.
    let allWordsCompleted: Bool

    var hasData: Bool { overall.attempts > 0 }

    static let empty = ReportData(
        overall: .zero,
        mainSummary: .zero,
        extraSummary: .zero,
        books: [],
        weakest: [],
        recentSessions: [],
        extraAttempts: 0,
        runNumber: 1,
        allWordsCompleted: false
    )
}

// MARK: - Aggregator

/// Turns raw per-word records into everything the Reports screen shows.
///
/// Pure and synchronous: given the same catalog and progress it always returns
/// the same numbers, which keeps it trivially testable. The whole library is
/// only a few hundred words, so a full recompute per render is cheaper than any
/// caching scheme would be to maintain.
enum StatsAggregator {

    static func build(
        catalog: VocabCatalog,
        progress: ProgressState,
        weakestLimit: Int = 8
    ) -> ReportData {
        guard !catalog.isEmpty else { return .empty }

        let mainStats: (VocabID) -> WordStats? = { progress.stats(for: $0, mode: .main) }
        let extraStats: (VocabID) -> WordStats? = { progress.stats(for: $0, mode: .extra) }

        var bookReports: [BookReport] = []

        for book in catalog.books {
            var sectionReports: [SectionReport] = []
            for section in book.sections {
                sectionReports.append(
                    SectionReport(
                        id: "\(book.id)/\(section.id)",
                        bookID: book.id,
                        sectionID: section.id,
                        title: section.title,
                        kind: section.kind,
                        summary: MetricSummary.make(items: section.allItems, stats: mainStats)
                    )
                )
            }

            let items = book.allItems
            bookReports.append(
                BookReport(
                    id: book.id,
                    title: book.title,
                    shortTitle: book.shortTitle,
                    theme: book.theme,
                    summary: MetricSummary.make(items: items, stats: mainStats),
                    sections: sectionReports,
                    mainSummary: MetricSummary.make(
                        items: items.filter { $0.category == .main }, stats: mainStats
                    ),
                    extraSummary: MetricSummary.make(
                        items: items.filter { $0.category == .extra }, stats: mainStats
                    )
                )
            )
        }

        let allItems = catalog.allItems
        let overall = MetricSummary.make(items: allItems, stats: mainStats)

        let weakest = weakestWords(
            catalog: catalog,
            mainStats: mainStats,
            extraStats: extraStats,
            limit: weakestLimit
        )

        let extraOverall = MetricSummary.make(items: allItems, stats: extraStats)

        return ReportData(
            overall: overall,
            mainSummary: MetricSummary.make(
                items: allItems.filter { $0.category == .main }, stats: mainStats
            ),
            extraSummary: MetricSummary.make(
                items: allItems.filter { $0.category == .extra }, stats: mainStats
            ),
            books: bookReports,
            weakest: weakest,
            recentSessions: Array(progress.sessions.suffix(12).reversed()),
            extraAttempts: extraOverall.attempts,
            runNumber: progress.runNumber,
            allWordsCompleted: allWordsCompleted(catalog: catalog, progress: progress)
        )
    }

    /// The words to put in front of the user, highest weakness first. Only words
    /// that have actually been answered wrong at least once qualify — an unseen
    /// word is not "weak", it is just new, and mixing the two makes the list
    /// useless right after a fresh install.
    static func weakestWords(
        catalog: VocabCatalog,
        mainStats: (VocabID) -> WordStats?,
        extraStats: (VocabID) -> WordStats?,
        limit: Int
    ) -> [WeakWord] {
        var titles: [String: (book: String, sections: [String: String])] = [:]
        for book in catalog.books {
            var sectionTitles: [String: String] = [:]
            for section in book.sections { sectionTitles[section.id] = section.title }
            titles[book.id] = (book.shortTitle, sectionTitles)
        }

        return catalog.allItems
            .compactMap { item -> WeakWord? in
                guard let stats = mainStats(item.id), stats.incorrect > 0, !stats.isMastered else { return nil }
                let bookInfo = titles[item.bookID]
                return WeakWord(
                    item: item,
                    bookShortTitle: bookInfo?.book ?? item.bookID,
                    sectionTitle: bookInfo?.sections[item.sectionID] ?? item.sectionID,
                    mainStats: stats,
                    extraStats: extraStats(item.id),
                    score: AdaptiveOrdering.weakness(stats)
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.id < rhs.id
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Drives the "you've been through everything" notice. True only when every
    /// single word has banked a full five-answer cycle in the current run.
    static func allWordsCompleted(catalog: VocabCatalog, progress: ProgressState) -> Bool {
        guard !catalog.isEmpty else { return false }
        for item in catalog.allItems {
            guard let stats = progress.stats(for: item.id, mode: .main), stats.isCompletedThisRun else {
                return false
            }
        }
        return true
    }
}
