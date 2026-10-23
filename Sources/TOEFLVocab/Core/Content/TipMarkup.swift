import Foundation

/// Finds the `'quoted'` words inside a usage tip.
///
/// The source data uses single quotes to mark the part of a tip that actually
/// has to be remembered: in `"followed by 'of'"` the whole value of the note is
/// the word `of`, and in `"cast is 'singular', in some other varieties it is
/// 'plural'"` there are two such words. Highlighting them is the difference
/// between a tip being read and a tip being skipped.
///
/// Kept here, away from SwiftUI, for two reasons: the rule below is the kind of
/// thing that needs unit tests, and the Android port has to split tips exactly
/// the same way or the two apps would highlight different words.
///
/// The rule, in one line: a `'` opens a highlight only at a word boundary.
/// Without that, the apostrophe in `"someone's 'ability' to"` would open a
/// quote, swallow `s ` and colour the wrong run. Contractions in the data use a
/// typographic apostrophe (`’`) and never match at all, but plain `'` shows up
/// too, so the boundary test — not the character — is what keeps this honest.
enum TipMarkup {

    /// One run of a tip: either prose, or a quoted word with its position.
    struct Segment: Equatable {
        let text: String
        /// `nil` for prose. Otherwise the index of this quoted word within the
        /// tip, which the design system turns into one of its highlight
        /// colours — first quote, first colour.
        let highlightIndex: Int?

        var isHighlighted: Bool { highlightIndex != nil }
    }

    /// Splits `tip` into prose and quoted runs, in order, with the quotes
    /// themselves dropped. Joining every `text` back together returns the tip
    /// without its quote marks.
    static func segments(of tip: String) -> [Segment] {
        let characters = Array(tip)
        var segments: [Segment] = []
        var prose = ""
        var highlightCount = 0
        var index = 0

        func flushProse() {
            guard !prose.isEmpty else { return }
            segments.append(Segment(text: prose, highlightIndex: nil))
            prose = ""
        }

        while index < characters.count {
            guard characters[index] == quote,
                  opensHighlight(at: index, in: characters),
                  let close = closingQuote(after: index, in: characters)
            else {
                prose.append(characters[index])
                index += 1
                continue
            }

            flushProse()
            segments.append(
                Segment(
                    text: String(characters[(index + 1)..<close]),
                    highlightIndex: highlightCount
                )
            )
            highlightCount += 1
            index = close + 1
        }

        flushProse()
        return segments
    }

    /// The tip with its quote marks removed and nothing else changed. This is
    /// what VoiceOver reads, since a spoken apostrophe carries no meaning.
    static func plainText(of tip: String) -> String {
        segments(of: tip).map(\.text).joined()
    }

    // MARK: - Private

    private static let quote: Character = "'"

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func opensHighlight(at index: Int, in characters: [Character]) -> Bool {
        index == 0 || !isWordCharacter(characters[index - 1])
    }

    /// The matching close quote, or nil — in which case the `'` is prose and the
    /// tip renders unchanged rather than losing its tail to a half-open quote.
    private static func closingQuote(after openIndex: Int, in characters: [Character]) -> Int? {
        var index = openIndex + 1
        var sawContent = false

        while index < characters.count {
            let character = characters[index]
            if character == quote {
                let insideWord = index + 1 < characters.count
                    && isWordCharacter(characters[index + 1])
                if sawContent, !insideWord { return index }
            } else if !character.isWhitespace {
                sawContent = true
            }
            index += 1
        }

        return nil
    }
}
