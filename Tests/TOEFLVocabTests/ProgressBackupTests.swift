import XCTest
@testable import TOEFLVocab

/// Backup and restore is the one feature where a bug costs the user something
/// irreplaceable, so the failure paths get as much attention as the happy one.
final class ProgressBackupTests: XCTestCase {

    private func id(_ term: String) -> VocabID {
        VocabID(bookID: "504", sectionID: "day_1", category: .main, term: term)
    }

    private func populatedState() -> ProgressState {
        var state = ProgressState()
        for _ in 0..<3 { state.record(id("abandon"), mode: .main, correct: true) }
        state.record(id("keen"), mode: .main, correct: false)
        state.record(id("keen"), mode: .extra, correct: true)
        state.lastLocation = LastLocation(bookID: "504", sectionID: "day_1", category: .main)
        state.append(
            SessionRecord(
                mode: .main, bookID: "504", sectionID: "day_1", category: .main,
                startedAt: Date(), finishedAt: Date(),
                answered: 4, correct: 3, completed: true
            )
        )
        return state
    }

    // MARK: Round trip

    func testBackupRestoresEveryPartOfProgress() throws {
        let original = populatedState()
        let data = try ProgressBackup.encoder.encode(
            ProgressBackup(progress: original, appVersion: "1.1")
        )

        let restored = try ProgressBackup.decode(from: data).progress

        XCTAssertEqual(restored.main[id("abandon").rawValue]?.correct, 3)
        XCTAssertEqual(restored.main[id("keen").rawValue]?.incorrect, 1)
        XCTAssertEqual(restored.extra[id("keen").rawValue]?.correct, 1)
        XCTAssertEqual(restored.sessions.count, 1)
        XCTAssertEqual(restored.lastLocation?.sectionID, "day_1")
        XCTAssertEqual(restored.runNumber, original.runNumber)
    }

    func testChecklistStateSurvivesTheRoundTrip() throws {
        var state = ProgressState()
        // Land mid-cycle: two answers in, three boxes still empty.
        state.record(id("abandon"), mode: .main, correct: true)
        state.record(id("abandon"), mode: .main, correct: false)

        let data = try ProgressBackup.encoder.encode(ProgressBackup(progress: state, appVersion: "1.1"))
        let restored = try ProgressBackup.decode(from: data).progress
        let stats = try XCTUnwrap(restored.main[id("abandon").rawValue])

        XCTAssertEqual(stats.currentCycle, [true, false])
        XCTAssertEqual(stats.checklist.filled, 2)
        XCTAssertFalse(stats.checklist.isRecap)
    }

    func testBackupCarriesItsOwnMetadata() throws {
        let backup = ProgressBackup(progress: populatedState(), appVersion: "1.1")
        let decoded = try ProgressBackup.decode(
            from: try ProgressBackup.encoder.encode(backup)
        )

        XCTAssertEqual(decoded.app, ProgressBackup.marker)
        XCTAssertEqual(decoded.format, ProgressBackup.currentFormat)
        XCTAssertEqual(decoded.appVersion, "1.1")
    }

    // MARK: Rejection

    func testUnrelatedJSONIsRejected() {
        let data = Data(#"{"hello": "world"}"#.utf8)

        XCTAssertThrowsError(try ProgressBackup.decode(from: data)) { error in
            XCTAssertEqual(error as? BackupError, .notABackupFile)
        }
    }

    func testABareProgressFileIsRejected() throws {
        // Decodes as valid JSON and even as a ProgressState, but has no marker.
        // Without the envelope check this would silently replace real history.
        let raw = try ProgressBackup.encoder.encode(populatedState())

        XCTAssertThrowsError(try ProgressBackup.decode(from: raw)) { error in
            XCTAssertEqual(error as? BackupError, .notABackupFile)
        }
    }

    func testABackupFromAnotherAppIsRejected() throws {
        let data = Data("""
        {"app":"SomeOtherApp","format":1,"appVersion":"1.0",
         "exportedAt":"2026-01-01T00:00:00Z","progress":{}}
        """.utf8)

        XCTAssertThrowsError(try ProgressBackup.decode(from: data)) { error in
            XCTAssertEqual(error as? BackupError, .notABackupFile)
        }
    }

    func testABackupFromANewerFormatIsRefusedRatherThanGuessedAt() {
        let data = Data("""
        {"app":"TOEFLVocab","format":99,"appVersion":"9.0",
         "exportedAt":"2026-01-01T00:00:00Z","progress":{}}
        """.utf8)

        XCTAssertThrowsError(try ProgressBackup.decode(from: data)) { error in
            XCTAssertEqual(error as? BackupError, .newerFormat(99))
        }
    }

    func testGarbageBytesAreRejectedWithoutCrashing() {
        XCTAssertThrowsError(try ProgressBackup.decode(from: Data([0x00, 0xFF, 0x10])))
        XCTAssertThrowsError(try ProgressBackup.decode(from: Data()))
    }

    // MARK: Store integration

    @MainActor
    func testImportingReplacesProgressAndExportingReturnsIt() throws {
        let store = ProgressStore.inMemory(state: populatedState())
        let exported = try store.exportBackup(appVersion: "1.1")

        // Simulate a fresh install: everything gone.
        store.eraseAll()
        XCTAssertNil(store.stats(for: id("abandon"), mode: .main))

        let restored = try store.importBackup(exported)

        XCTAssertEqual(restored.app, ProgressBackup.marker)
        XCTAssertEqual(store.stats(for: id("abandon"), mode: .main)?.correct, 3)
        XCTAssertEqual(store.state.sessions.count, 1)
        XCTAssertEqual(store.lastLocation?.sectionID, "day_1")
    }

    @MainActor
    func testAFailedImportLeavesExistingProgressUntouched() throws {
        let store = ProgressStore.inMemory(state: populatedState())

        XCTAssertThrowsError(try store.importBackup(Data("not a backup".utf8)))

        // The whole point: a mistaken file pick must not cost the user anything.
        XCTAssertEqual(store.stats(for: id("abandon"), mode: .main)?.correct, 3)
        XCTAssertEqual(store.state.sessions.count, 1)
    }
}
