import Foundation

// MARK: - Mode

/// Which counter an answer lands in.
///
/// `.main` is the study path through books and sections. `.extra` is the
/// drill launched from Reports; it keeps a completely separate set of counters
/// so a heavy drilling session can never flatter (or wreck) main progress.
enum PracticeMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case main
    case extra

    var id: String { rawValue }
    var countsTowardMainProgress: Bool { self == .main }
}

// MARK: - Checklist rendering

/// What the five boxes under a word should show right now.
struct ChecklistDisplay: Equatable {
    let marks: [Bool]
    /// True when these five boxes are a *finished* cycle being shown one last
    /// time before the row resets. Lets the UI label it "last 5".
    let isRecap: Bool

    var filled: Int { marks.count }
    var correctCount: Int { marks.filter { $0 }.count }
    var capacity: Int { WordStats.cycleLength }
}

// MARK: - Per-word statistics

/// Everything the app remembers about one word in one mode.
///
/// The five-step rule lives in `record(correct:at:)`: the checklist fills left
/// to right, and the instant the fifth box lands the cycle is banked into
/// `lastCycle` and a fresh empty checklist begins. The banked cycle stays
/// visible until the user moves on, so the fifth answer is actually seen
/// instead of the row blanking out underneath them.
struct WordStats: Codable, Hashable {
    static let cycleLength = 5
    /// Consecutive correct answers after which a word counts as mastered.
    static let masteryStreak = 3

    // Lifetime totals — never reset, so Reports can show real history.
    var attempts: Int
    var correct: Int
    var incorrect: Int

    // Current cycle state.
    var currentCycle: [Bool]
    var lastCycle: [Bool]?

    /// Lifetime count of finished five-answer cycles.
    var completedCycles: Int
    /// Finished cycles since the last full restart. Drives "is this word done
    /// for this run?", which is what the global completion check looks at.
    var completedCyclesThisRun: Int

    var consecutiveCorrect: Int
    var lastAnsweredAt: Date?

    init(
        attempts: Int = 0,
        correct: Int = 0,
        incorrect: Int = 0,
        currentCycle: [Bool] = [],
        lastCycle: [Bool]? = nil,
        completedCycles: Int = 0,
        completedCyclesThisRun: Int = 0,
        consecutiveCorrect: Int = 0,
        lastAnsweredAt: Date? = nil
    ) {
        self.attempts = attempts
        self.correct = correct
        self.incorrect = incorrect
        self.currentCycle = currentCycle
        self.lastCycle = lastCycle
        self.completedCycles = completedCycles
        self.completedCyclesThisRun = completedCyclesThisRun
        self.consecutiveCorrect = consecutiveCorrect
        self.lastAnsweredAt = lastAnsweredAt
    }

    // MARK: Derived

    var hasBeenSeen: Bool { attempts > 0 }

    var accuracy: Double {
        attempts == 0 ? 0 : Double(correct) / Double(attempts)
    }

    /// The most recent answer, looking through a just-completed cycle.
    var lastAnswerWasCorrect: Bool? {
        if let last = currentCycle.last { return last }
        return lastCycle?.last
    }

    /// Finished at least one five-answer cycle in the current run.
    var isCompletedThisRun: Bool { completedCyclesThisRun >= 1 }

    /// Finished a cycle *and* is currently on a correct streak.
    var isMastered: Bool {
        completedCyclesThisRun >= 1 && consecutiveCorrect >= Self.masteryStreak
    }

    var checklist: ChecklistDisplay {
        if currentCycle.isEmpty, let lastCycle, !lastCycle.isEmpty {
            return ChecklistDisplay(marks: lastCycle, isRecap: true)
        }
        return ChecklistDisplay(marks: currentCycle, isRecap: false)
    }

    // MARK: Mutation

    /// Records one self-graded answer and applies the five-step reset rule.
    /// Returns true when this answer completed a cycle.
    @discardableResult
    mutating func record(correct isCorrect: Bool, at date: Date = Date()) -> Bool {
        attempts += 1
        if isCorrect {
            correct += 1
            consecutiveCorrect += 1
        } else {
            incorrect += 1
            consecutiveCorrect = 0
        }
        lastAnsweredAt = date
        currentCycle.append(isCorrect)

        guard currentCycle.count >= Self.cycleLength else { return false }
        lastCycle = currentCycle
        currentCycle = []
        completedCycles += 1
        completedCyclesThisRun += 1
        return true
    }

    /// Called on a full restart. Lifetime totals survive; per-run completion is
    /// cleared so every word is "unfinished" again. The banked `lastCycle`
    /// survives too — that recap is the whole point of the reset rule.
    mutating func startNewRun() {
        completedCyclesThisRun = 0
        currentCycle = []
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case attempts, correct, incorrect
        case currentCycle, lastCycle
        case completedCycles, completedCyclesThisRun
        case consecutiveCorrect, lastAnsweredAt
    }

    /// Decoded key by key with defaults rather than by the synthesised
    /// initialiser: a saved file written by an older build is missing whatever
    /// fields were added since, and a hard throw there would wipe real progress.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attempts = try container.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        correct = try container.decodeIfPresent(Int.self, forKey: .correct) ?? 0
        incorrect = try container.decodeIfPresent(Int.self, forKey: .incorrect) ?? 0
        currentCycle = try container.decodeIfPresent([Bool].self, forKey: .currentCycle) ?? []
        lastCycle = try container.decodeIfPresent([Bool].self, forKey: .lastCycle)
        completedCycles = try container.decodeIfPresent(Int.self, forKey: .completedCycles) ?? 0
        completedCyclesThisRun = try container.decodeIfPresent(Int.self, forKey: .completedCyclesThisRun)
            ?? completedCycles
        consecutiveCorrect = try container.decodeIfPresent(Int.self, forKey: .consecutiveCorrect) ?? 0
        lastAnsweredAt = try container.decodeIfPresent(Date.self, forKey: .lastAnsweredAt)

        // Defend against a hand-edited or truncated file.
        if currentCycle.count >= Self.cycleLength {
            currentCycle = Array(currentCycle.suffix(Self.cycleLength - 1))
        }
    }
}

// MARK: - Session history

/// One finished (or abandoned) practice run, kept for the Reports timeline.
struct SessionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let mode: PracticeMode
    let bookID: String?
    let sectionID: String?
    let category: VocabCategory?
    let startedAt: Date
    let finishedAt: Date
    let answered: Int
    let correct: Int
    /// False when the user quit part-way.
    let completed: Bool

    var accuracy: Double {
        answered == 0 ? 0 : Double(correct) / Double(answered)
    }

    init(
        id: UUID = UUID(),
        mode: PracticeMode,
        bookID: String?,
        sectionID: String?,
        category: VocabCategory?,
        startedAt: Date,
        finishedAt: Date,
        answered: Int,
        correct: Int,
        completed: Bool
    ) {
        self.id = id
        self.mode = mode
        self.bookID = bookID
        self.sectionID = sectionID
        self.category = category
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.answered = answered
        self.correct = correct
        self.completed = completed
    }

    private enum CodingKeys: String, CodingKey {
        case id, mode, bookID, sectionID, category, startedAt, finishedAt, answered, correct, completed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mode = try container.decodeIfPresent(PracticeMode.self, forKey: .mode) ?? .main
        bookID = try container.decodeIfPresent(String.self, forKey: .bookID)
        sectionID = try container.decodeIfPresent(String.self, forKey: .sectionID)
        category = try container.decodeIfPresent(VocabCategory.self, forKey: .category)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt) ?? Date()
        answered = try container.decodeIfPresent(Int.self, forKey: .answered) ?? 0
        correct = try container.decodeIfPresent(Int.self, forKey: .correct) ?? 0
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? true
    }
}

/// Where the user was last, so the library can offer "continue".
struct LastLocation: Codable, Hashable {
    var bookID: String
    var sectionID: String
    var category: VocabCategory
}

// MARK: - Persisted root

struct ProgressState: Codable {
    static let currentSchemaVersion = 1
    /// Session history is capped so the file cannot grow without bound.
    static let maxStoredSessions = 250

    var schemaVersion: Int
    /// Keyed by `VocabID.rawValue`. A `[VocabID: WordStats]` dictionary would
    /// encode as a flat JSON *array* of alternating keys and values, because
    /// VocabID is not a String key — this keeps the file readable.
    var main: [String: WordStats]
    var extra: [String: WordStats]
    var sessions: [SessionRecord]
    /// Increments on every full restart, so Reports can say "run 2".
    var runNumber: Int
    var lastLocation: LastLocation?

    init(
        schemaVersion: Int = ProgressState.currentSchemaVersion,
        main: [String: WordStats] = [:],
        extra: [String: WordStats] = [:],
        sessions: [SessionRecord] = [],
        runNumber: Int = 1,
        lastLocation: LastLocation? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.main = main
        self.extra = extra
        self.sessions = sessions
        self.runNumber = runNumber
        self.lastLocation = lastLocation
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, main, extra, sessions, runNumber, lastLocation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? ProgressState.currentSchemaVersion
        main = try container.decodeIfPresent([String: WordStats].self, forKey: .main) ?? [:]
        extra = try container.decodeIfPresent([String: WordStats].self, forKey: .extra) ?? [:]
        sessions = try container.decodeIfPresent([SessionRecord].self, forKey: .sessions) ?? []
        runNumber = try container.decodeIfPresent(Int.self, forKey: .runNumber) ?? 1
        lastLocation = try container.decodeIfPresent(LastLocation.self, forKey: .lastLocation)
    }

    // MARK: Access

    func stats(for id: VocabID, mode: PracticeMode) -> WordStats? {
        switch mode {
        case .main: return main[id.rawValue]
        case .extra: return extra[id.rawValue]
        }
    }

    mutating func setStats(_ stats: WordStats, for id: VocabID, mode: PracticeMode) {
        switch mode {
        case .main: main[id.rawValue] = stats
        case .extra: extra[id.rawValue] = stats
        }
    }

    @discardableResult
    mutating func record(_ id: VocabID, mode: PracticeMode, correct: Bool, at date: Date = Date()) -> WordStats {
        var stats = self.stats(for: id, mode: mode) ?? WordStats()
        stats.record(correct: correct, at: date)
        setStats(stats, for: id, mode: mode)
        return stats
    }

    mutating func append(_ session: SessionRecord) {
        sessions.append(session)
        if sessions.count > Self.maxStoredSessions {
            sessions.removeFirst(sessions.count - Self.maxStoredSessions)
        }
    }

    /// Full restart. Lifetime counters and session history survive so Reports
    /// keeps its history; per-run completion is cleared everywhere.
    mutating func beginNewRun() {
        runNumber += 1
        for key in main.keys { main[key]?.startNewRun() }
        for key in extra.keys { extra[key]?.startNewRun() }
    }

    /// Wipes everything. Used by Settings → Reset all progress.
    mutating func eraseAll() {
        main = [:]
        extra = [:]
        sessions = []
        runNumber = 1
        lastLocation = nil
    }
}
