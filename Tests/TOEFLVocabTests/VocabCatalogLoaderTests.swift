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
        XCTAssertEqual(items[0].usageTip, "followed by in")
        XCTAssertNil(items[1].usageTip, "A plain definition must not grow an empty tip")
    }

    func testSplittingUsageTips() {
        XCTAssertEqual(
            VocabCatalogLoader.splitUsageTip(from: "a strong influence --- followed by on or of").definition,
            "a strong influence"
        )
        XCTAssertEqual(
            VocabCatalogLoader.splitUsageTip(from: "a strong influence --- followed by on or of").usageTip,
            "followed by on or of"
        )

        // No marker at all — the whole string is the meaning.
        let plain = VocabCatalogLoader.splitUsageTip(from: "  a dead body  ")
        XCTAssertEqual(plain.definition, "a dead body")
        XCTAssertNil(plain.usageTip)

        // A second marker belongs to the note, not to a third field.
        let doubled = VocabCatalogLoader.splitUsageTip(from: "meaning --- first --- second")
        XCTAssertEqual(doubled.definition, "meaning")
        XCTAssertEqual(doubled.usageTip, "first --- second")

        // Nothing before the marker: keep the row readable rather than blanking
        // the meaning and getting the whole word skipped on load.
        let headless = VocabCatalogLoader.splitUsageTip(from: "--- followed by to")
        XCTAssertEqual(headless.definition, "--- followed by to")
        XCTAssertNil(headless.usageTip)

        // Nothing after it either.
        let empty = VocabCatalogLoader.splitUsageTip(from: "a dead body ---")
        XCTAssertEqual(empty.definition, "a dead body")
        XCTAssertNil(empty.usageTip)
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
