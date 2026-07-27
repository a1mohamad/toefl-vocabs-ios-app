import Foundation

/// Owns all mutable user progress and its single JSON file on disk.
///
/// Why a plain Codable file rather than SwiftData:
///
/// * SwiftData needs iOS 17, which would cut off older devices for a sideloaded
///   build that already has enough install friction.
/// * There is no local Simulator on this project, so a schema or migration bug
///   costs a full CI round trip to see and another to confirm a fix. A file
///   that is one `Data.write(_:options:.atomic)` call has far less that can go
///   wrong, and `ProgressState` decodes field-by-field with defaults so an old
///   file never fails to load.
/// * The whole dataset is a few hundred small records. There is no query load
///   here that would justify a database.
///
/// The SwiftData move stays open: `ProgressState` is the only shape that would
/// need porting, and `ProgressStore` is the only type the UI talks to.
@MainActor
final class ProgressStore: ObservableObject {

    @Published private(set) var state: ProgressState

    private let fileURL: URL?
    private var saveTask: Task<Void, Never>?

    /// Answers arrive one tap at a time; batching them keeps the app off the
    /// filesystem during a fast session.
    private static let saveDebounceNanoseconds: UInt64 = 600_000_000

    // MARK: Init

    init(fileURL: URL? = ProgressStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.state = ProgressStore.loadState(from: fileURL)
    }

    /// In-memory only. Used by tests and SwiftUI previews.
    static func inMemory(state: ProgressState = ProgressState()) -> ProgressStore {
        let store = ProgressStore(fileURL: nil)
        store.state = state
        return store
    }

    static func defaultFileURL() -> URL? {
        let manager = FileManager.default
        guard let directory = try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return directory.appendingPathComponent("progress.json")
    }

    // MARK: Reading

    func stats(for id: VocabID, mode: PracticeMode) -> WordStats? {
        state.stats(for: id, mode: mode)
    }

    /// Convenience for handing a lookup to `AdaptiveOrdering`.
    func statsProvider(for mode: PracticeMode) -> (VocabID) -> WordStats? {
        { [weak self] id in self?.state.stats(for: id, mode: mode) }
    }

    var lastLocation: LastLocation? { state.lastLocation }
    var runNumber: Int { state.runNumber }

    // MARK: Writing

    @discardableResult
    func record(_ id: VocabID, mode: PracticeMode, correct: Bool, at date: Date = Date()) -> WordStats {
        let updated = state.record(id, mode: mode, correct: correct, at: date)
        scheduleSave()
        return updated
    }

    func appendSession(_ record: SessionRecord) {
        state.append(record)
        scheduleSave()
    }

    func rememberLocation(_ location: LastLocation) {
        guard state.lastLocation != location else { return }
        state.lastLocation = location
        scheduleSave()
    }

    /// Full restart once every word has finished a cycle. Lifetime totals and
    /// session history survive so Reports keeps its history.
    func beginNewRun() {
        state.beginNewRun()
        saveNow()
    }

    /// Settings → Reset all progress.
    func eraseAll() {
        state.eraseAll()
        saveNow()
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: ProgressStore.saveDebounceNanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
    }

    /// Called on backgrounding and on any change that must not be lost.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil

        guard let fileURL else { return }
        do {
            let data = try ProgressStore.encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("[Progress] Save failed: \(error)")
            #endif
        }
    }

    private static func loadState(from fileURL: URL?) -> ProgressState {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return ProgressState()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(ProgressState.self, from: data)
        } catch {
            // Never crash on a bad file. Move it aside so the user gets a
            // working app and the original is still there to inspect.
            #if DEBUG
            print("[Progress] Load failed: \(error). Quarantining the file.")
            #endif
            let quarantine = fileURL.deletingLastPathComponent()
                .appendingPathComponent("progress-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: quarantine)
            return ProgressState()
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
