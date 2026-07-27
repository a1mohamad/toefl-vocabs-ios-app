import XCTest
@testable import TOEFLVocab

/// The five-step rule, pinned down.
///
/// This is the piece of behaviour a user would notice instantly if it broke and
/// the piece that is impossible to eyeball from a Simulator screenshot, so it
/// gets the most thorough coverage in the suite.
final class WordStatsCycleTests: XCTestCase {

    func testChecklistFillsLeftToRightAndBanksOnTheFifthAnswer() {
        var stats = WordStats()

        for _ in 0..<4 {
            XCTAssertFalse(stats.record(correct: true), "A cycle must not complete before the fifth answer")
        }
        XCTAssertEqual(stats.currentCycle, [true, true, true, true])
        XCTAssertEqual(stats.completedCycles, 0)
        XCTAssertNil(stats.lastCycle)
        XCTAssertFalse(stats.isCompletedThisRun)

        XCTAssertTrue(stats.record(correct: false), "The fifth answer completes the cycle")
        XCTAssertEqual(stats.currentCycle, [], "The checklist resets for the next cycle")
        XCTAssertEqual(stats.lastCycle, [true, true, true, true, false])
        XCTAssertEqual(stats.completedCycles, 1)
        XCTAssertEqual(stats.completedCyclesThisRun, 1)
        XCTAssertTrue(stats.isCompletedThisRun)
    }

    func testBankedCycleStaysOnScreenAsARecapUntilTheNextAnswer() {
        var stats = WordStats()
        for _ in 0..<5 { stats.record(correct: true) }

        // The user must see their fifth answer land, not a row that blanks out.
        XCTAssertTrue(stats.checklist.isRecap)
        XCTAssertEqual(stats.checklist.filled, 5)
        XCTAssertEqual(stats.checklist.correctCount, 5)

        stats.record(correct: false)
        XCTAssertFalse(stats.checklist.isRecap)
        XCTAssertEqual(stats.checklist.marks, [false])
    }

    func testLifetimeTotalsAccumulateAcrossCycles() {
        var stats = WordStats()
        for _ in 0..<10 { stats.record(correct: true) }
        for _ in 0..<5 { stats.record(correct: false) }

        XCTAssertEqual(stats.attempts, 15)
        XCTAssertEqual(stats.correct, 10)
        XCTAssertEqual(stats.incorrect, 5)
        XCTAssertEqual(stats.completedCycles, 3)
        XCTAssertEqual(stats.accuracy, 10.0 / 15.0, accuracy: 0.0001)
    }

    func testConsecutiveCorrectResetsOnAWrongAnswer() {
        var stats = WordStats()
        stats.record(correct: true)
        stats.record(correct: true)
        XCTAssertEqual(stats.consecutiveCorrect, 2)

        stats.record(correct: false)
        XCTAssertEqual(stats.consecutiveCorrect, 0)
    }

    func testLastAnswerIsReadableThroughAJustCompletedCycle() {
        var stats = WordStats()
        for _ in 0..<4 { stats.record(correct: true) }
        stats.record(correct: false)

        // currentCycle is empty here, so this has to fall through to lastCycle
        // or the adaptive ordering loses the "just got it wrong" signal.
        XCTAssertEqual(stats.lastAnswerWasCorrect, false)
    }

    func testMasteryNeedsBothAFinishedCycleAndAStreak() {
        var stats = WordStats()
        for _ in 0..<3 { stats.record(correct: true) }
        XCTAssertFalse(stats.isMastered, "A streak alone is not mastery")

        for _ in 0..<2 { stats.record(correct: true) }
        XCTAssertTrue(stats.isMastered)

        stats.record(correct: false)
        XCTAssertFalse(stats.isMastered, "A wrong answer drops mastery immediately")
    }

    func testNewRunClearsPerRunCompletionButKeepsHistory() {
        var stats = WordStats()
        for _ in 0..<5 { stats.record(correct: true) }
        XCTAssertTrue(stats.isCompletedThisRun)

        stats.startNewRun()

        XCTAssertFalse(stats.isCompletedThisRun)
        XCTAssertEqual(stats.completedCyclesThisRun, 0)
        XCTAssertEqual(stats.completedCycles, 1, "Lifetime cycle count survives a restart")
        XCTAssertEqual(stats.attempts, 5, "Lifetime attempts survive a restart")
        XCTAssertEqual(stats.lastCycle, [true, true, true, true, true], "The recap survives a restart")
    }

    // MARK: Persistence resilience

    func testDecodingAFileWrittenBeforePerRunTrackingBackfillsIt() throws {
        let json = Data("""
        {
          "attempts": 5, "correct": 4, "incorrect": 1,
          "currentCycle": [], "completedCycles": 1, "consecutiveCorrect": 2
        }
        """.utf8)

        let stats = try JSONDecoder().decode(WordStats.self, from: json)

        XCTAssertEqual(stats.completedCyclesThisRun, 1)
        XCTAssertTrue(stats.isCompletedThisRun)
    }

    func testDecodingAnEmptyObjectYieldsAUsableZeroedRecord() throws {
        let stats = try JSONDecoder().decode(WordStats.self, from: Data("{}".utf8))

        XCTAssertEqual(stats.attempts, 0)
        XCTAssertEqual(stats.currentCycle, [])
        XCTAssertFalse(stats.hasBeenSeen)
    }

    func testDecodingRepairsAnOverfullChecklist() throws {
        // A hand-edited or half-written file must not produce a checklist that
        // can never reset.
        let json = Data("""
        {"attempts": 7, "correct": 7, "incorrect": 0,
         "currentCycle": [true, true, true, true, true, true, true],
         "completedCycles": 0, "consecutiveCorrect": 7}
        """.utf8)

        let stats = try JSONDecoder().decode(WordStats.self, from: json)

        XCTAssertLessThan(stats.currentCycle.count, WordStats.cycleLength)
        XCTAssertEqual(stats.currentCycle.count, WordStats.cycleLength - 1)
    }

    func testProgressStateRoundTripsThroughJSON() throws {
        let id = VocabID(bookID: "504", sectionID: "day_1", category: .main, term: "abandon")
        var state = ProgressState()
        state.record(id, mode: .main, correct: true)
        state.record(id, mode: .extra, correct: false)
        state.lastLocation = LastLocation(bookID: "504", sectionID: "day_1", category: .main)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(ProgressState.self, from: encoder.encode(state))

        XCTAssertEqual(restored.stats(for: id, mode: .main)?.correct, 1)
        XCTAssertEqual(restored.stats(for: id, mode: .extra)?.incorrect, 1)
        XCTAssertEqual(restored.lastLocation?.sectionID, "day_1")
    }

    func testWordIdSurvivesAStringRoundTripIncludingMultiWordTerms() {
        let id = VocabID(bookID: "400", sectionID: "day_3", category: .extra, term: "sent chills up and down my spine")
        let restored = VocabID(rawValue: id.rawValue)

        XCTAssertEqual(restored, id)
        XCTAssertEqual(restored?.term, "sent chills up and down my spine")
    }

    func testMalformedWordIdIsRejectedRatherThanGuessed() {
        XCTAssertNil(VocabID(rawValue: "504/day_1/main"))
        XCTAssertNil(VocabID(rawValue: "504/day_1/nonsense/abandon"))
        XCTAssertNil(VocabID(rawValue: "504//main/abandon"))
    }
}
