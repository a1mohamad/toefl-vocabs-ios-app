import SwiftUI
import XCTest
@testable import TOEFLVocab

final class ReportingTests: XCTestCase {

    private let vocabs = Data("""
    {
      "504": {
        "day_1": {
          "main": [
            { "term": "alpha", "definition": "first" },
            { "term": "bravo", "definition": "second" }
          ],
          "extras": [
            { "term": "charlie", "definition": "third" }
          ]
        }
      }
    }
    """.utf8)

    private func makeCatalog() throws -> VocabCatalog {
        try VocabCatalogLoader.build(vocabsData: vocabs, catalogData: nil)
    }

    private func id(_ term: String, category: VocabCategory = .main) -> VocabID {
        VocabID(bookID: "504", sectionID: "day_1", category: category, term: term)
    }

    // MARK: Global completion

    func testNothingPractisedMeansNotComplete() throws {
        let catalog = try makeCatalog()

        XCTAssertFalse(StatsAggregator.allWordsCompleted(catalog: catalog, progress: ProgressState()))
    }

    func testCompletionRequiresEverySingleWordToFinishACycle() throws {
        let catalog = try makeCatalog()
        var state = ProgressState()

        // Two of the three words finish a full cycle.
        for term in ["alpha", "bravo"] {
            for _ in 0..<WordStats.cycleLength {
                state.record(id(term), mode: .main, correct: true)
            }
        }
        XCTAssertFalse(
            StatsAggregator.allWordsCompleted(catalog: catalog, progress: state),
            "The extras word has not been touched, so the run is not finished"
        )

        for _ in 0..<WordStats.cycleLength {
            state.record(id("charlie", category: .extra), mode: .main, correct: false)
        }
        XCTAssertTrue(StatsAggregator.allWordsCompleted(catalog: catalog, progress: state))
    }

    func testDrillAnswersDoNotCountTowardMainCompletion() throws {
        let catalog = try makeCatalog()
        var state = ProgressState()

        for item in catalog.allItems {
            for _ in 0..<WordStats.cycleLength {
                state.record(item.id, mode: .extra, correct: true)
            }
        }

        XCTAssertFalse(
            StatsAggregator.allWordsCompleted(catalog: catalog, progress: state),
            "Extra practice is explicitly separate from main progress"
        )
    }

    func testStartingANewRunReopensCompletion() throws {
        let catalog = try makeCatalog()
        var state = ProgressState()
        for item in catalog.allItems {
            for _ in 0..<WordStats.cycleLength {
                state.record(item.id, mode: .main, correct: true)
            }
        }
        XCTAssertTrue(StatsAggregator.allWordsCompleted(catalog: catalog, progress: state))

        state.beginNewRun()

        XCTAssertFalse(StatsAggregator.allWordsCompleted(catalog: catalog, progress: state))
        XCTAssertEqual(state.runNumber, 2)
        XCTAssertEqual(
            state.main[id("alpha").rawValue]?.attempts,
            WordStats.cycleLength,
            "Lifetime history survives the restart"
        )
    }

    // MARK: Summaries

    func testSummaryCountsSeenAttemptsAndAccuracy() throws {
        let catalog = try makeCatalog()
        var state = ProgressState()
        state.record(id("alpha"), mode: .main, correct: true)
        state.record(id("alpha"), mode: .main, correct: false)
        state.record(id("bravo"), mode: .main, correct: true)

        let summary = MetricSummary.make(items: catalog.allItems) { state.stats(for: $0, mode: .main) }

        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.seen, 2)
        XCTAssertEqual(summary.attempts, 3)
        XCTAssertEqual(summary.correct, 2)
        XCTAssertEqual(summary.accuracy, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(summary.needsWork, 1, "Only alpha has been answered wrong")
    }

    func testUntouchedContentReportsZeroWithoutDividingByZero() throws {
        let catalog = try makeCatalog()
        let summary = MetricSummary.make(items: catalog.allItems) { _ in nil }

        XCTAssertEqual(summary.accuracy, 0)
        XCTAssertEqual(summary.completedFraction, 0)
        XCTAssertTrue(summary.isUntouched)
    }

    func testWeakestListSkipsUnseenAndMasteredWords() throws {
        let catalog = try makeCatalog()
        var state = ProgressState()

        // alpha: struggling. bravo: mastered. charlie: never seen.
        for _ in 0..<3 { state.record(id("alpha"), mode: .main, correct: false) }
        for _ in 0..<WordStats.cycleLength { state.record(id("bravo"), mode: .main, correct: true) }

        let weakest = StatsAggregator.weakestWords(
            catalog: catalog,
            mainStats: { state.stats(for: $0, mode: .main) },
            extraStats: { state.stats(for: $0, mode: .extra) },
            limit: 10
        )

        XCTAssertEqual(weakest.map(\.item.term), ["alpha"])
    }

    func testReportBuildProducesOneEntryPerBookAndSection() throws {
        let catalog = try makeCatalog()
        var state = ProgressState()
        state.record(id("alpha"), mode: .main, correct: true)

        let report = StatsAggregator.build(catalog: catalog, progress: state)

        XCTAssertTrue(report.hasData)
        XCTAssertEqual(report.books.count, 1)
        XCTAssertEqual(report.books.first?.sections.count, 1)
        XCTAssertEqual(report.mainSummary.total, 2, "Two main words")
        XCTAssertEqual(report.extraSummary.total, 1, "One extra word")
    }

    func testSessionHistoryIsCappedSoTheFileCannotGrowForever() {
        var state = ProgressState()
        for _ in 0..<(ProgressState.maxStoredSessions + 40) {
            state.append(
                SessionRecord(
                    mode: .main,
                    bookID: "504",
                    sectionID: "day_1",
                    category: .main,
                    startedAt: Date(),
                    finishedAt: Date(),
                    answered: 1,
                    correct: 1,
                    completed: true
                )
            )
        }

        XCTAssertEqual(state.sessions.count, ProgressState.maxStoredSessions)
    }
}

// MARK: - Localisation

final class StringsTests: XCTestCase {

    func testEveryKeyHasEnglishCopy() {
        let missing = StringKey.allCases.filter { Strings.english[$0] == nil }

        XCTAssertTrue(missing.isEmpty, "Missing English copy for: \(missing.map(\.rawValue))")
    }

    func testNoKeyFallsBackToItsOwnRawValue() {
        let strings = Strings(language: .english)
        let leaked = StringKey.allCases.filter { strings[$0] == $0.rawValue }

        XCTAssertTrue(leaked.isEmpty, "These keys would render as raw identifiers: \(leaked.map(\.rawValue))")
    }

    func testATranslationGapFallsBackToEnglishRatherThanTheKey() {
        let persian = Strings(language: .persian)

        for key in StringKey.allCases {
            let value = persian[key]
            XCTAssertFalse(value.isEmpty)
            XCTAssertNotEqual(value, key.rawValue, "\(key.rawValue) rendered as a raw key")
        }
    }

    func testFormattedKeysSubstituteTheirPlaceholders() {
        let strings = Strings(language: .english)

        XCTAssertEqual(strings.format(.practiceProgress, 3, 12), "3 of 12")
        XCTAssertTrue(strings.format(.bookWordsCount, 42).contains("42"))
    }

    func testPersianIsRightToLeftAndEnglishIsNot() {
        XCTAssertTrue(AppLanguage.persian.isRightToLeft)
        XCTAssertFalse(AppLanguage.english.isRightToLeft)
        XCTAssertEqual(AppLanguage.persian.layoutDirection, .rightToLeft)
    }

    func testSpeechRateIsClampedToTheUsableBand() {
        XCTAssertEqual(AppSettings(speechRate: 5.0).speechRate, AppSettings.maximumSpeechRate)
        XCTAssertEqual(AppSettings(speechRate: -1).speechRate, AppSettings.minimumSpeechRate)
    }

    func testSettingsDecodeFromAnEmptyObject() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.accent, .american)
        XCTAssertEqual(settings.speechRate, AppSettings.defaultSpeechRate)
    }
}
