import Foundation

/// Tunable knobs for the weakness score. Exposed as a struct so the behaviour
/// can be pinned down in tests instead of being hard-coded magic numbers.
struct OrderingWeights: Equatable {
    /// Multiplier on the smoothed error rate — the main signal.
    var errorWeight: Double = 1.0
    /// Added when the most recent answer was wrong. Big enough to lift a word
    /// above an unseen one immediately after a mistake.
    var recentMistakeBonus: Double = 0.35
    /// Subtracted per consecutive correct answer, so mastered words sink.
    var masteryPenaltyPerStreak: Double = 0.06
    var maximumStreakConsidered: Int = 5
    /// Subtracted per finished cycle in this run, so words that are genuinely
    /// done stop crowding the front of the queue.
    var completedCyclePenalty: Double = 0.04
    var maximumCyclesConsidered: Int = 5

    static let `default` = OrderingWeights()
}

/// Decides what order words are presented in.
///
/// The rule the app promises: **open a section and the words you get wrong most
/// come first**. A section you have never touched plays in book order, because
/// every word scores identically and the tie-break is the source position.
///
/// The score is deliberately deterministic — no randomness, no shuffling. Two
/// runs with the same history produce the same queue, which is what makes the
/// behaviour explainable to the user and testable in CI.
enum AdaptiveOrdering {

    /// Score for a word with no history. Laplace smoothing puts an unseen word
    /// at exactly 0.5, which lands it *below* anything you have actually got
    /// wrong and *above* anything you have been getting right.
    static let unseenScore: Double = 0.5

    static func weakness(_ stats: WordStats?, weights: OrderingWeights = .default) -> Double {
        guard let stats, stats.attempts > 0 else { return unseenScore }

        // (incorrect + 0.5) / (attempts + 1) — smoothed so that a single wrong
        // answer does not read as a 100% error rate forever.
        let smoothedErrorRate = (Double(stats.incorrect) + 0.5) / (Double(stats.attempts) + 1.0)
        var score = weights.errorWeight * smoothedErrorRate

        if stats.lastAnswerWasCorrect == false {
            score += weights.recentMistakeBonus
        }

        let streak = min(stats.consecutiveCorrect, weights.maximumStreakConsidered)
        score -= Double(streak) * weights.masteryPenaltyPerStreak

        let cycles = min(stats.completedCyclesThisRun, weights.maximumCyclesConsidered)
        score -= Double(cycles) * weights.completedCyclePenalty

        return score
    }

    /// Weakest first. Ties break on source order, then on id, giving a total
    /// ordering — `sort` is not stable in Swift, so the comparator has to be
    /// complete or the queue could shuffle between launches.
    static func order(
        _ items: [VocabItem],
        weights: OrderingWeights = .default,
        stats: (VocabID) -> WordStats?
    ) -> [VocabItem] {
        items
            .map { (item: $0, score: weakness(stats($0.id), weights: weights)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.item.orderIndex != rhs.item.orderIndex { return lhs.item.orderIndex < rhs.item.orderIndex }
                return lhs.item.id.rawValue < rhs.item.id.rawValue
            }
            .map(\.item)
    }

    /// Queue for the Reports drill, which spans the whole library.
    ///
    /// Ranked by **main-mode** weakness, because that is where the real learning
    /// history lives — the drill is meant to target what the study path has
    /// shown you are bad at. Among equally weak words, the ones drilled least
    /// come first, so a long session keeps moving instead of looping over the
    /// same handful.
    ///
    /// Running the full list weakest-to-strongest is also what gives the
    /// behaviour asked for: wrong words first, then the rest, then a full pass
    /// is complete and the queue starts over.
    static func extraPracticeQueue(
        items: [VocabItem],
        limit: Int?,
        weights: OrderingWeights = .default,
        mainStats: (VocabID) -> WordStats?,
        extraStats: (VocabID) -> WordStats?
    ) -> [VocabItem] {
        let ranked = items
            .map { item -> (item: VocabItem, main: Double, drills: Int, drillScore: Double) in
                let extra = extraStats(item.id)
                return (
                    item: item,
                    main: weakness(mainStats(item.id), weights: weights),
                    drills: extra?.attempts ?? 0,
                    drillScore: weakness(extra, weights: weights)
                )
            }
            .sorted { lhs, rhs in
                if lhs.main != rhs.main { return lhs.main > rhs.main }
                if lhs.drills != rhs.drills { return lhs.drills < rhs.drills }
                if lhs.drillScore != rhs.drillScore { return lhs.drillScore > rhs.drillScore }
                return lhs.item.id.rawValue < rhs.item.id.rawValue
            }
            .map(\.item)

        guard let limit, limit > 0, ranked.count > limit else { return ranked }
        return Array(ranked.prefix(limit))
    }
}
