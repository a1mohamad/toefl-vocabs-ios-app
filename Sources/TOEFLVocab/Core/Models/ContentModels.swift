import Foundation

// MARK: - Category

/// The two word lists that live inside every section.
///
/// The data file calls these `main` and `extras`; the app calls them
/// `.main` and `.extra`. `jsonKey` is the only place that mismatch matters.
enum VocabCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case main
    case extra

    var id: String { rawValue }

    var jsonKey: String {
        switch self {
        case .main: return "main"
        case .extra: return "extras"
        }
    }

    static func fromJSONKey(_ key: String) -> VocabCategory? {
        switch key {
        case "main": return .main
        case "extras", "extra": return .extra
        default: return nil
        }
    }

    var symbolName: String {
        switch self {
        case .main: return "book.closed.fill"
        case .extra: return "sparkles"
        }
    }

    var titleKey: StringKey {
        switch self {
        case .main: return .categoryMain
        case .extra: return .categoryExtra
        }
    }

    var subtitleKey: StringKey {
        switch self {
        case .main: return .categoryMainSubtitle
        case .extra: return .categoryExtraSubtitle
        }
    }
}

// MARK: - Word identity

/// Stable identity for a single word.
///
/// Scoped by book *and* section *and* category on purpose: four terms
/// (`abandon`, `circulate`, `feature`, `survive`) appear in more than one place
/// in the source data, and each occurrence deserves its own progress record.
///
/// Serialised as one `book/section/category/term` string so the saved progress
/// file stays human-readable. Terms are validated to contain no `/`.
struct VocabID: Hashable, Codable, CustomStringConvertible {
    let bookID: String
    let sectionID: String
    let category: VocabCategory
    let term: String

    init(bookID: String, sectionID: String, category: VocabCategory, term: String) {
        self.bookID = bookID
        self.sectionID = sectionID
        self.category = category
        self.term = term
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "/", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4,
              let category = VocabCategory(rawValue: String(parts[2])),
              !parts[0].isEmpty, !parts[1].isEmpty, !parts[3].isEmpty
        else { return nil }

        self.init(
            bookID: String(parts[0]),
            sectionID: String(parts[1]),
            category: category,
            term: String(parts[3])
        )
    }

    var rawValue: String { "\(bookID)/\(sectionID)/\(category.rawValue)/\(term)" }

    var description: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = VocabID(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Malformed VocabID: \(raw)"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Word

struct VocabItem: Identifiable, Hashable {
    let id: VocabID
    let term: String
    let definition: String
    /// Usage note that the source data appends to the definition after ` --- `,
    /// e.g. "followed by in". Not part of the meaning, so it is carried
    /// separately and presented as a hint rather than as dictionary text.
    let usageTip: String?
    /// Position within its category, straight from the source array. This is
    /// what makes a never-practised section play back in book order.
    let orderIndex: Int

    init(
        id: VocabID,
        term: String,
        definition: String,
        usageTip: String? = nil,
        orderIndex: Int
    ) {
        self.id = id
        self.term = term
        self.definition = definition
        self.usageTip = usageTip
        self.orderIndex = orderIndex
    }

    var bookID: String { id.bookID }
    var sectionID: String { id.sectionID }
    var category: VocabCategory { id.category }
}

// MARK: - Section

enum SectionKind: String, Codable, Hashable {
    case lesson
    case review

    var symbolName: String {
        switch self {
        case .lesson: return "calendar"
        case .review: return "arrow.triangle.2.circlepath"
        }
    }
}

struct VocabSection: Identifiable, Hashable {
    let id: String
    let bookID: String
    let title: String
    let intro: String
    let kind: SectionKind
    /// Display order inside the book, assigned by the loader from catalog.json.
    let order: Int
    let itemsByCategory: [VocabCategory: [VocabItem]]

    func items(in category: VocabCategory) -> [VocabItem] {
        itemsByCategory[category] ?? []
    }

    /// Only the categories that actually have words. `504/review_1` has no
    /// extras, so the section screen must not offer an empty Extra list.
    var availableCategories: [VocabCategory] {
        VocabCategory.allCases.filter { !items(in: $0).isEmpty }
    }

    var allItems: [VocabItem] {
        VocabCategory.allCases.flatMap { items(in: $0) }
    }

    var wordCount: Int { allItems.count }

    func wordCount(in category: VocabCategory) -> Int {
        items(in: category).count
    }
}

// MARK: - Book

/// Accent identity for a book, resolved to real colours in the design system.
enum BookTheme: String, Codable, Hashable, CaseIterable {
    case indigo
    case teal
    case amber
    case rose

    static func named(_ raw: String?) -> BookTheme {
        guard let raw else { return .indigo }
        return BookTheme(rawValue: raw.lowercased()) ?? .indigo
    }
}

struct Book: Identifiable, Hashable {
    let id: String
    let title: String
    let shortTitle: String
    let author: String
    let intro: String
    let theme: BookTheme
    let order: Int
    let sections: [VocabSection]

    var allItems: [VocabItem] {
        sections.flatMap { $0.allItems }
    }

    var wordCount: Int {
        sections.reduce(0) { $0 + $1.wordCount }
    }

    func section(_ sectionID: String) -> VocabSection? {
        sections.first { $0.id == sectionID }
    }

    /// The section that follows `sectionID`, or nil at the end of the book.
    func sectionAfter(_ sectionID: String) -> VocabSection? {
        guard let index = sections.firstIndex(where: { $0.id == sectionID }),
              sections.indices.contains(index + 1)
        else { return nil }
        return sections[index + 1]
    }
}

// MARK: - Catalog

/// The whole content library, already ordered and indexed. Built once at launch
/// and treated as immutable afterwards.
struct VocabCatalog {
    let books: [Book]
    let allItems: [VocabItem]

    private let itemIndex: [String: VocabItem]

    init(books: [Book]) {
        self.books = books

        var items: [VocabItem] = []
        var index: [String: VocabItem] = [:]
        for book in books {
            for section in book.sections {
                for item in section.allItems {
                    items.append(item)
                    index[item.id.rawValue] = item
                }
            }
        }
        self.allItems = items
        self.itemIndex = index
    }

    static let empty = VocabCatalog(books: [])

    var isEmpty: Bool { allItems.isEmpty }
    var totalWordCount: Int { allItems.count }

    func book(_ bookID: String) -> Book? {
        books.first { $0.id == bookID }
    }

    func section(bookID: String, sectionID: String) -> VocabSection? {
        book(bookID)?.section(sectionID)
    }

    func item(_ id: VocabID) -> VocabItem? {
        itemIndex[id.rawValue]
    }

    func items(bookID: String, sectionID: String, category: VocabCategory) -> [VocabItem] {
        section(bookID: bookID, sectionID: sectionID)?.items(in: category) ?? []
    }
}
