import XCTest
@testable import TOEFLVocab

/// The ordering promise: open a section and your worst words are first, but a
/// section you have never touched plays in book order.
final class AdaptiveOrderingTests: XCTestCase {

    // MARK: Helpers

    private func item(
        _ term: String,
        index: Int,
        book: String = "504",
        section: String = "day_1",
        category: VocabCategory = .main
    ) -> VocabItem {
        VocabItem(
            id: VocabID(bookID: book, sectionID: section, category: category, term: term),
            term: term,
            definition: "definition of \(term)",
            orderIndex: index
        )
    }

    private var sample: [VocabItem] {
        ["alpha", "bravo", "charlie", "delta"]
            .enumerated()
            .map { item($0.element, index: $0.offset) }
    }

    private func stats(correct: Int, incorrect: Int, endingWrong: Bool = false) -> WordStats {
        var value = WordStats()
        for _ in 0..<correct { value.record(correct: true) }
        for _ in 0..<incorrect { value.record(correct: false) }
        if endingWrong { value.record(correct: false) }
        return value
    }

    // MARK: Tests

    func testUntouchedSectionPlaysInBookOrder() {
        let ordered = AdaptiveOrdering.order(sample) { _ in nil }

        XCTAssertEqual(ordered.map(\.term), ["alpha", "bravo", "charlie", "delta"])
    }

    func testWordsAnsweredWrongMoveToTheFront() {
        var wrong = WordStats()
        wrong.record(correct: false)

        let ordered = AdaptiveOrdering.order(sample) { id in
            id.term == "charlie" ? wrong : nil
        }

        XCTAssertEqual(ordered.first?.term, "charlie")
    }

    func testWordsAnsweredRightSinkBelowUnseenWords() {
        var good = WordStats()
        for _ in 0..<3 { good.record(correct: true) }

        let ordered = AdaptiveOrdering.order(sample) { id in
            id.term == "alpha" ? good : nil
        }

        XCTAssertEqual(ordered.last?.term, "alpha", "A word you keep getting right should not lead the queue")
    }

    func testTheWorstOfSeveralWrongWordsLeads() {
        let terrible = stats(correct: 0, incorrect: 4)
        let shaky = stats(correct: 3, incorrect: 1)

        let ordered = AdaptiveOrdering.order(sample) { id in
            switch id.term {
            case "delta": return terrible
            case "bravo": return shaky
            default: return nil
            }
        }

        XCTAssertEqual(ordered.first?.term, "delta")
        XCTAssertLessThan(
            ordered.firstIndex(where: { $0.term == "delta" }) ?? .max,
            ordered.firstIndex(where: { $0.term == "bravo" }) ?? .max
        )
    }

    func testARecentMistakeOutweighsAGoodLongTermRecord() {
        // Nine right then one wrong is a good record, but the app should still
        // put it in front of a word with no history at all.
        let slipped = stats(correct: 9, incorrect: 0, endingWrong: true)

        let ordered = AdaptiveOrdering.order(sample) { id in
            id.term == "delta" ? slipped : nil
        }

        XCTAssertEqual(ordered.first?.term, "delta")
    }

    func testOrderingIsDeterministic() {
        let history: [String: WordStats] = [
            "alpha": stats(correct: 2, incorrect: 2),
            "bravo": stats(correct: 2, incorrect: 2),
            "charlie": stats(correct: 2, incorrect: 2),
        ]
        let provider: (VocabID) -> WordStats? = { history[$0.term] }

        let first = AdaptiveOrdering.order(sample, stats: provider).map(\.term)
        for _ in 0..<25 {
            XCTAssertEqual(AdaptiveOrdering.order(sample, stats: provider).map(\.term), first)
        }
    }

    func testTiedWordsFromDifferentSectionsStillGetATotalOrdering() {
        // Source index collides across sections, so the id has to break the tie
        // or the drill queue could reshuffle between launches.
        let mixed = [
            item("one", index: 0, section: "day_1"),
            item("two", index: 0, section: "day_2"),
            item("three", index: 0, book: "400", section: "day_1"),
        ]

        let first = AdaptiveOrdering.order(mixed) { _ in nil }.map(\.term)
        for _ in 0..<25 {
            XCTAssertEqual(AdaptiveOrdering.order(mixed) { _ in nil }.map(\.term), first)
        }
    }

    func testUnseenWordScoresExactlyTheDocumentedBaseline() {
        XCTAssertEqual(AdaptiveOrdering.weakness(nil), AdaptiveOrdering.unseenScore, accuracy: 0.0001)
        XCTAssertEqual(AdaptiveOrdering.weakness(WordStats()), AdaptiveOrdering.unseenScore, accuracy: 0.0001)
    }

    // MARK: Drill queue

    func testDrillQueueRespectsTheScopeLimit() {
        let many = (0..<40).map { item("word\($0)", index: $0) }

        let queue = AdaptiveOrdering.extraPracticeQueue(
            items: many,
            limit: 25,
            mainStats: { _ in nil },
            extraStats: { _ in nil }
        )

        XCTAssertEqual(queue.count, 25)
    }

    func testDrillQueueWithNoLimitCoversEverything() {
        let many = (0..<40).map { item("word\($0)", index: $0) }

        let queue = AdaptiveOrdering.extraPracticeQueue(
            items: many,
            limit: nil,
            mainStats: { _ in nil },
            extraStats: { _ in nil }
        )

        XCTAssertEqual(queue.count, 40)
    }

    func testDrillQueueRanksByMainHistoryNotDrillHistory() {
        let wrongInMain = stats(correct: 0, incorrect: 3)
        let wrongInDrill = stats(correct: 0, incorrect: 3)

        let queue = AdaptiveOrdering.extraPracticeQueue(
            items: sample,
            limit: nil,
            mainStats: { $0.term == "charlie" ? wrongInMain : nil },
            extraStats: { $0.term == "delta" ? wrongInDrill : nil }
        )

        XCTAssertEqual(queue.first?.term, "charlie", "The drill targets what the study path found weak")
    }

    func testEquallyWeakWordsPreferTheOneDrilledLeast() {
        let drilled = stats(correct: 2, incorrect: 0)

        let queue = AdaptiveOrdering.extraPracticeQueue(
            items: sample,
            limit: nil,
            mainStats: { _ in nil },
            extraStats: { $0.term == "alpha" ? drilled : nil }
        )

        XCTAssertNotEqual(queue.first?.term, "alpha", "A word already drilled should not lead a tie")
    }

    func testDrillQueueRunsWrongWordsBeforeCorrectOnes() {
        let bad = stats(correct: 0, incorrect: 3)
        let good = stats(correct: 5, incorrect: 0)

        let queue = AdaptiveOrdering.extraPracticeQueue(
            items: sample,
            limit: nil,
            mainStats: { id in
                switch id.term {
                case "delta": return bad
                case "alpha": return good
                default: return nil
                }
            },
            extraStats: { _ in nil }
        )

        let terms = queue.map(\.term)
        XCTAssertEqual(terms.first, "delta")
        XCTAssertEqual(terms.last, "alpha")
    }
}
