import XCTest
@testable import TOEFLVocab

/// Loading rules, especially the ordering ones — the source data is two nested
/// JSON objects, and objects have no key order, so every ordering guarantee the
/// app makes has to come from somewhere else and be verified here.
final class VocabCatalogLoaderTests: XCTestCase {

    // MARK: Fixtures

    /// Deliberately written with `review_1` between the two days, and with word
    /// arrays whose order is not alphabetical.
    private let vocabs = Data("""
    {
      "504": {
        "day_1": {
          "main": [
            { "term": "zebra", "definition": "striped animal" },
            { "term": "abandon", "definition": "leave behind" }
          ],
          "extras": [
            { "term": "cloak", "definition": "a kind of coat" }
          ]
        },
        "review_1": {
          "main": [
            { "term": "recap", "definition": "a summary" }
          ]
        },
        "day_2": {
          "main": [
            { "term": "corpse", "definition": "a dead body" }
          ]
        }
      }
    }
    """.utf8)

    /// Section order here is day_1 -> review_1 -> day_2, which no sort function
    /// would produce from the ids.
    private let catalog = Data("""
    {
      "books": [
        {
          "id": "504",
          "title": "504 Absolutely Essential Words",
          "shortTitle": "504",
          "author": "Barron's",
          "theme": "indigo",
          "intro": "Book intro.",
          "sections": [
            { "id": "day_1", "title": "Day 1", "kind": "lesson", "intro": "First." },
            { "id": "review_1", "title": "Review 1", "kind": "review", "intro": "Recap." },
            { "id": "day_2", "title": "Day 2", "kind": "lesson", "intro": "Second." }
          ]
        }
      ]
    }
    """.utf8)

    // MARK: Ordering

    func testSectionOrderComesFromTheCatalogNotFromSorting() throws {
        let result = try VocabCatalogLoader.build(vocabsData: vocabs, catalogData: catalog)
        let book = try XCTUnwrap(result.book("504"))

        XCTAssertEqual(
            book.sections.map(\.id),
            ["day_1", "review_1", "day_2"],
            "Sorting the ids would put review_1 last; the catalog says otherwise"
        )
    }

    func testWordOrderComesFromTheArrayNotAlphabetically() throws {
        let result = try VocabCatalogLoader.build(vocabsData: vocabs, catalogData: catalog)
        let section = try XCTUnwrap(result.section(bookID: "504", sectionID: "day_1"))

        XCTAssertEqual(section.items(in: .main).map(\.term), ["zebra", "abandon"])
        XCTAssertEqual(section.items(in: .main).map(\.orderIndex), [0, 1])
    }

    func testLegacyObjectFormStillLoadsSortedAlphabetically() throws {
        let legacy = Data("""
        {
          "504": {
            "day_1": {
              "main": { "zebra": "striped animal", "abandon": "leave behind" }
            }
          }
        }
        """.utf8)

        let result = try VocabCatalogLoader.build(vocabsData: legacy, catalogData: nil)
        let section = try XCTUnwrap(result.section(bookID: "504", sectionID: "day_1"))

        XCTAssertEqual(section.items(in: .main).map(\.term), ["abandon", "zebra"])
    }

    // MARK: Metadata

    func testCatalogSuppliesTitlesAndIntros() throws {
        let result = try VocabCatalogLoader.build(vocabsData: vocabs, catalogData: catalog)
        let book = try XCTUnwrap(result.book("504"))

        XCTAssertEqual(book.title, "504 Absolutely Essential Words")
        XCTAssertEqual(book.shortTitle, "504")
        XCTAssertEqual(book.theme, .indigo)
        XCTAssertEqual(book.sections.first?.title, "Day 1")
        XCTAssertEqual(book.sections.first?.intro, "First.")
    }

    func testReviewSectionIsMarkedAndExposesOnlyTheListsItHas() throws {
        let result = try VocabCatalogLoader.build(vocabsData: vocabs, catalogData: catalog)
        let review = try XCTUnwrap(result.section(bookID: "504", sectionID: "review_1"))

        XCTAssertEqual(review.kind, .review)
        XCTAssertEqual(review.availableCategories, [.main], "review_1 has no extras and must not offer an empty list")
        XCTAssertTrue(review.items(in: .extra).isEmpty)
    }

    // MARK: Degradation

    func testSectionMissingFromTheCatalogIsAppendedWithAGeneratedTitle() throws {
        let extended = Data("""
        {
          "504": {
            "day_1": { "main": [ { "term": "abandon", "definition": "leave behind" } ] },
            "day_9": { "main": [ { "term": "newword", "definition": "recently added" } ] }
          }
        }
        """.utf8)

        let result = try VocabCatalogLoader.build(vocabsData: extended, catalogData: catalog)
        let book = try XCTUnwrap(result.book("504"))

        XCTAssertEqual(book.sections.map(\.id), ["day_1", "day_9"], "Unlisted sections go last, never missing")
        XCTAssertEqual(book.sections.last?.title, "Day 9")
    }

    func testCatalogEntryWithoutDataIsSkippedRatherThanShownEmpty() throws {
        let sparse = Data("""
        { "504": { "day_1": { "main": [ { "term": "abandon", "definition": "leave behind" } ] } } }
        """.utf8)

        let result = try VocabCatalogLoader.build(vocabsData: sparse, catalogData: catalog)
        let book = try XCTUnwrap(result.book("504"))

        XCTAssertEqual(book.sections.map(\.id), ["day_1"])
    }

    func testContentLoadsEvenWithNoCatalogAtAll() throws {
        let result = try VocabCatalogLoader.build(vocabsData: vocabs, catalogData: nil)
        let book = try XCTUnwrap(result.book("504"))

        XCTAssertEqual(book.sections.count, 3)
        XCTAssertEqual(book.title, "504")
        XCTAssertFalse(result.isEmpty)
    }

    func testBrokenRowsAreSkippedInsteadOfLosingTheWholeLibrary() throws {
        let messy = Data("""
        {
          "504": {
            "day_1": {
              "main": [
                { "term": "good", "definition": "fine" },
                { "term": "", "definition": "empty term" },
                { "term": "nodefinition", "definition": "" },
                { "term": "bad/slash", "definition": "reserved character" },
                { "term": "Good", "definition": "duplicate ignoring case" },
                { "term": "  spaced  ", "definition": "  padded  " }
              ]
            }
          }
        }
        """.utf8)

        let result = try VocabCatalogLoader.build(vocabsData: messy, catalogData: nil)
        let section = try XCTUnwrap(result.section(bookID: "504", sectionID: "day_1"))
        let terms = section.items(in: .main).map(\.term)

        XCTAssertEqual(terms, ["good", "spaced"])
        XCTAssertEqual(section.items(in: .main).last?.definition, "padded", "Whitespace is trimmed on load")
    }

    func testCompletelyUnusableContentThrowsRatherThanShowingABlankApp() {
        let empty = Data("{}".utf8)

        XCTAssertThrowsError(try VocabCatalogLoader.build(vocabsData: empty, catalogData: nil)) { error in
            XCTAssertEqual(error as? ContentError, ContentError.empty)
        }
    }

    func testInvalidJSONReportsWhichFileIsAtFault() {
        let broken = Data("{ not json".utf8)

        XCTAssertThrowsError(try VocabCatalogLoader.build(vocabsData: broken, catalogData: nil)) { error in
            guard case .decodingFailed(let file, _)? = error as? ContentError else {
                return XCTFail("Expected a decodingFailed error, got \(error)")
            }
            XCTAssertEqual(file, "vocabs.json")
        }
    }

    // MARK: Usage tips

    func testUsageNoteAfterTheMarkerIsLiftedOutOfTheDefinition() throws {
        let tipped = Data("""
        {
          "504": {
            "day_1": {
              "main": [
                { "term": "inherent", "definition": "naturally characteristic --- followed by in" },
                { "term": "corpse", "definition": "a dead body" }
              ]
            }
          }
        }
        """.utf8)

        let result = try VocabCatalogLoader.build(vocabsData: tipped, catalogData: nil)
        let items = try XCTUnwrap(result.section(bookID: "504", sectionID: "day_1")).items(in: .main)

        XCTAssertEqual(items[0].definition, "naturally characteristic", "The marker and everything after it is not the meaning")
        XCTAssertEqual(items[0].usageTips, ["followed by in"])
        XCTAssertTrue(items[1].usageTips.isEmpty, "A plain definition must not grow an empty tip")
    }

    func testSplittingUsageTips() {
        XCTAssertEqual(
            VocabCatalogLoader.splitDefinition(from: "a strong influence --- followed by on or of").definition,
            "a strong influence"
        )
        XCTAssertEqual(
            VocabCatalogLoader.splitDefinition(from: "a strong influence --- followed by on or of").usageTips,
            ["followed by on or of"]
        )

        // No marker at all — the whole string is the meaning.
        let plain = VocabCatalogLoader.splitDefinition(from: "  a dead body  ")
        XCTAssertEqual(plain.definition, "a dead body")
        XCTAssertTrue(plain.usageTips.isEmpty)

        // Each marker starts a new note. Several words in the 400 list carry two
        // independent pieces of advice, and joining them would hide that.
        let doubled = VocabCatalogLoader.splitDefinition(from: "meaning --- first --- second")
        XCTAssertEqual(doubled.definition, "meaning")
        XCTAssertEqual(doubled.usageTips, ["first", "second"])

        // An empty stretch between two markers is dropped rather than becoming
        // a blank tip row.
        let hollow = VocabCatalogLoader.splitDefinition(from: "meaning --- --- second")
        XCTAssertEqual(hollow.usageTips, ["second"])

        // Nothing before the marker: keep the row readable rather than blanking
        // the meaning and getting the whole word skipped on load.
        let headless = VocabCatalogLoader.splitDefinition(from: "--- followed by to")
        XCTAssertEqual(headless.definition, "--- followed by to")
        XCTAssertTrue(headless.usageTips.isEmpty)

        // Nothing after it either.
        let empty = VocabCatalogLoader.splitDefinition(from: "a dead body ---")
        XCTAssertEqual(empty.definition, "a dead body")
        XCTAssertTrue(empty.usageTips.isEmpty)
    }

    // MARK: Meanings and tip markup

    func testDefinitionsSplitIntoNumberedMeanings() {
        // The source data writes every sense of a word on one `;`-separated
        // line; the practice screen numbers them, so the split has to be here.
        XCTAssertEqual(
            VocabItem.splitMeanings("keep; keep up; carry on; uphold"),
            ["keep", "keep up", "carry on", "uphold"]
        )

        // One meaning stays one meaning — the screen keeps it as a centred line
        // rather than a list of one.
        XCTAssertEqual(VocabItem.splitMeanings("a dead body"), ["a dead body"])

        // A trailing separator must not produce an empty numbered row.
        XCTAssertEqual(VocabItem.splitMeanings("empty; not filled;"), ["empty", "not filled"])

        // And a definition of nothing but separators keeps its text, because an
        // empty list would leave the practice screen with no answer on it.
        XCTAssertEqual(VocabItem.splitMeanings(";;"), [";;"])
    }

    func testTipMarkupFindsTheQuotedWords() {
        let segments = TipMarkup.segments(of: "followed by 'of'")
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0], TipMarkup.Segment(text: "followed by ", highlightIndex: nil))
        XCTAssertEqual(segments[1], TipMarkup.Segment(text: "of", highlightIndex: 0))

        // Several quoted words in one tip are numbered in order, which is what
        // gives each of them a different colour.
        let two = TipMarkup.segments(of: "cast is 'singular', elsewhere it is 'plural'")
        XCTAssertEqual(two.filter(\.isHighlighted).map(\.text), ["singular", "plural"])
        XCTAssertEqual(two.filter(\.isHighlighted).compactMap(\.highlightIndex), [0, 1])

        // The apostrophe in a possessive must not open a quote and swallow the
        // word that genuinely deserves the colour.
        let possessive = TipMarkup.segments(of: "the object of 'impair' is often someone's 'ability' to")
        XCTAssertEqual(possessive.filter(\.isHighlighted).map(\.text), ["impair", "ability"])

        // An unclosed quote is prose: the tip renders whole rather than losing
        // its tail.
        let unclosed = TipMarkup.segments(of: "comes from 'a latin word")
        XCTAssertEqual(unclosed.count, 1)
        XCTAssertFalse(unclosed[0].isHighlighted)

        // What VoiceOver reads: the same sentence without the quote marks.
        XCTAssertEqual(
            TipMarkup.plainText(of: "notice the root 'certain', meaning 'sure'"),
            "notice the root certain, meaning sure"
        )
    }

    // MARK: Identity

    func testTheSameTermInTwoBooksGetsTwoIndependentRecords() throws {
        let shared = Data("""
        {
          "504": { "day_1": { "main": [ { "term": "abandon", "definition": "leave" } ] } },
          "400": { "day_1": { "main": [ { "term": "abandon", "definition": "give up" } ] } }
        }
        """.utf8)

        let result = try VocabCatalogLoader.build(vocabsData: shared, catalogData: nil)
        let ids = result.allItems.map(\.id.rawValue)

        XCTAssertEqual(Set(ids).count, 2, "abandon appears in both books and must not share progress")
    }

    // MARK: Helpers

    func testGeneratedTitles() {
        XCTAssertEqual(VocabCatalogLoader.humanReadableTitle(from: "day_9"), "Day 9")
        XCTAssertEqual(VocabCatalogLoader.humanReadableTitle(from: "review_1"), "Review 1")
        XCTAssertEqual(VocabCatalogLoader.humanReadableTitle(from: "504"), "504")
    }

    func testNaturalOrderingPutsDayTwoBeforeDayTen() {
        XCTAssertTrue(VocabCatalogLoader.naturallyPrecedes("day_2", "day_10"))
        XCTAssertFalse(VocabCatalogLoader.naturallyPrecedes("day_10", "day_2"))
    }
}
