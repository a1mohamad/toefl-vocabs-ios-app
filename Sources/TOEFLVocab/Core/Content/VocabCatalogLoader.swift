import Foundation

// MARK: - Errors

enum ContentError: LocalizedError, Equatable {
    case resourceMissing(String)
    case decodingFailed(String, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            return "\(name) is not inside the app bundle. Check the Resources/VocabData entry in project.yml."
        case .decodingFailed(let name, let reason):
            return "\(name) could not be read: \(reason)"
        case .empty:
            return "The content files loaded but contained no usable words."
        }
    }
}

// MARK: - Loader

/// Turns the two bundled JSON files into an ordered, indexed `VocabCatalog`.
///
/// Ordering, in full, because it is the subtle part:
///
/// * **Books and sections** are ordered by `catalog.json`, because they live in
///   JSON *objects* in `vocabs.json` and objects have no guaranteed key order.
///   No sort function would ever place `504/review_1` between `day_6` and
///   `day_7` where it belongs, so the order is stated explicitly instead.
/// * **Words** are ordered by their position in the `[{term, definition}]`
///   array. Legacy `{term: definition}` objects still load, sorted
///   alphabetically, with a console warning.
///
/// Definitions are also split here: everything after a `---` marker is a usage
/// note rather than part of the meaning, and is lifted into `usageTip`.
///
/// Anything present in `vocabs.json` but missing from `catalog.json` is still
/// shown — appended at the end with a generated title — so adding a day and
/// forgetting the catalog entry degrades instead of hiding words.
enum VocabCatalogLoader {

    // MARK: Entry points

    static func load(bundle: Bundle = .main) throws -> VocabCatalog {
        let vocabs = try data(named: "vocabs", bundle: bundle)
        // A missing catalog is survivable: everything falls back to generated
        // titles and natural ordering.
        let catalog = try? data(named: "catalog", bundle: bundle)
        return try build(vocabsData: vocabs, catalogData: catalog)
    }

    /// Testable seam — feeds JSON straight in, no bundle involved.
    static func build(vocabsData: Data, catalogData: Data?) throws -> VocabCatalog {
        let decoder = JSONDecoder()

        let raw: RawFile
        do {
            raw = try decoder.decode(RawFile.self, from: vocabsData)
        } catch {
            throw ContentError.decodingFailed("vocabs.json", String(describing: error))
        }

        var catalogFile: CatalogFile?
        if let catalogData {
            do {
                catalogFile = try decoder.decode(CatalogFile.self, from: catalogData)
            } catch {
                // Not fatal — order and titles degrade, words survive.
                log("catalog.json could not be read (\(error)). Falling back to generated titles.")
            }
        }

        var books: [Book] = []
        var handledBookIDs: Set<String> = []

        for meta in catalogFile?.books ?? [] {
            guard let rawBook = raw[meta.id] else {
                log("catalog.json lists book '\(meta.id)', which is not in vocabs.json. Skipping.")
                continue
            }
            guard !handledBookIDs.contains(meta.id) else { continue }
            if let book = makeBook(id: meta.id, meta: meta, rawBook: rawBook, order: books.count) {
                books.append(book)
            }
            handledBookIDs.insert(meta.id)
        }

        for bookID in raw.keys.sorted(by: naturallyPrecedes) where !handledBookIDs.contains(bookID) {
            log("Book '\(bookID)' is not in catalog.json — appending with a generated title.")
            if let book = makeBook(id: bookID, meta: nil, rawBook: raw[bookID] ?? [:], order: books.count) {
                books.append(book)
            }
        }

        let catalog = VocabCatalog(books: books)
        guard !catalog.isEmpty else { throw ContentError.empty }
        return catalog
    }

    // MARK: Building

    private static func makeBook(
        id: String,
        meta: CatalogBook?,
        rawBook: RawBook,
        order: Int
    ) -> Book? {
        var sections: [VocabSection] = []
        var handledSectionIDs: Set<String> = []

        for sectionMeta in meta?.sections ?? [] {
            guard let rawSection = rawBook[sectionMeta.id] else {
                log("catalog.json lists section '\(id)/\(sectionMeta.id)', which is not in vocabs.json. Skipping.")
                continue
            }
            guard !handledSectionIDs.contains(sectionMeta.id) else { continue }
            if let section = makeSection(
                bookID: id,
                sectionID: sectionMeta.id,
                meta: sectionMeta,
                rawSection: rawSection,
                order: sections.count
            ) {
                sections.append(section)
            }
            handledSectionIDs.insert(sectionMeta.id)
        }

        for sectionID in rawBook.keys.sorted(by: naturallyPrecedes) where !handledSectionIDs.contains(sectionID) {
            log("Section '\(id)/\(sectionID)' is not in catalog.json — appending with a generated title.")
            if let section = makeSection(
                bookID: id,
                sectionID: sectionID,
                meta: nil,
                rawSection: rawBook[sectionID] ?? [:],
                order: sections.count
            ) {
                sections.append(section)
            }
        }

        guard !sections.isEmpty else { return nil }

        let title = meta?.title ?? humanReadableTitle(from: id)
        return Book(
            id: id,
            title: title,
            shortTitle: meta?.shortTitle ?? title,
            author: meta?.author ?? "",
            intro: meta?.intro ?? "",
            theme: BookTheme.named(meta?.theme),
            order: order,
            sections: sections
        )
    }

    private static func makeSection(
        bookID: String,
        sectionID: String,
        meta: CatalogSection?,
        rawSection: RawSection,
        order: Int
    ) -> VocabSection? {
        var itemsByCategory: [VocabCategory: [VocabItem]] = [:]

        for (categoryKey, list) in rawSection {
            guard let category = VocabCategory.fromJSONKey(categoryKey) else {
                log("Unknown category '\(categoryKey)' in \(bookID)/\(sectionID). Skipping.")
                continue
            }
            if list.wasUnordered {
                log("\(bookID)/\(sectionID)/\(categoryKey) uses the legacy object form — "
                    + "words fall back to alphabetical order. Run Scripts/migrate_vocabs.py.")
            }

            var items: [VocabItem] = []
            var seenTerms: Set<String> = []

            for word in list.words {
                let term = word.term.trimmingCharacters(in: .whitespacesAndNewlines)
                let (definition, usageTip) = splitUsageTip(from: word.definition)

                // Skip rather than throw: one bad row should never cost the user
                // the whole library.
                guard !term.isEmpty, !definition.isEmpty else { continue }
                guard !term.contains("/") else {
                    log("Skipping '\(term)' in \(bookID)/\(sectionID): '/' is reserved in word ids.")
                    continue
                }
                guard seenTerms.insert(term.lowercased()).inserted else {
                    log("Skipping duplicate '\(term)' in \(bookID)/\(sectionID)/\(categoryKey).")
                    continue
                }

                items.append(
                    VocabItem(
                        id: VocabID(bookID: bookID, sectionID: sectionID, category: category, term: term),
                        term: term,
                        definition: definition,
                        usageTip: usageTip,
                        orderIndex: items.count
                    )
                )
            }

            if !items.isEmpty {
                itemsByCategory[category] = items
            }
        }

        guard !itemsByCategory.isEmpty else { return nil }

        return VocabSection(
            id: sectionID,
            bookID: bookID,
            title: meta?.title ?? humanReadableTitle(from: sectionID),
            intro: meta?.intro ?? "",
            kind: SectionKind(rawValue: meta?.kind ?? "lesson") ?? .lesson,
            order: order,
            itemsByCategory: itemsByCategory
        )
    }

    // MARK: Helpers

    /// The marker the source data uses to append a usage note to a definition.
    static let usageTipSeparator = "---"

    /// Splits `"meaning --- usage note"` into its two halves.
    ///
    /// The note is grammar advice ("followed by in", "usually comes before the
    /// noun it describes"), not part of what the word means, so it must not be
    /// read as the answer during practice.
    ///
    /// A row that is *only* a note, or only whitespace either side of the
    /// marker, keeps its original text and reports no tip — losing the meaning
    /// would be a far worse outcome than showing an unsplit line.
    static func splitUsageTip(from raw: String) -> (definition: String, usageTip: String?) {
        let whole = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = whole.components(separatedBy: usageTipSeparator)
        guard parts.count > 1 else { return (whole, nil) }

        let definition = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        // Any further markers belong to the note, not to another field.
        let tip = parts
            .dropFirst()
            .joined(separator: usageTipSeparator)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !definition.isEmpty else { return (whole, nil) }
        return (definition, tip.isEmpty ? nil : tip)
    }

    /// `day_9` -> `Day 9`, `review_1` -> `Review 1`, `504` -> `504`.
    static func humanReadableTitle(from identifier: String) -> String {
        let parts = identifier.split(whereSeparator: { $0 == "_" || $0 == "-" })
        guard !parts.isEmpty else { return identifier }
        return parts.map { part -> String in
            if Int(part) != nil { return String(part) }
            return part.prefix(1).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }

    /// Orders `day_2` before `day_10` — plain string sorting would not.
    static func naturallyPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        let left = splitTrailingNumber(lhs)
        let right = splitTrailingNumber(rhs)
        if left.prefix != right.prefix { return left.prefix < right.prefix }
        return (left.number ?? -1) < (right.number ?? -1)
    }

    private static func splitTrailingNumber(_ value: String) -> (prefix: String, number: Int?) {
        let digits = value.reversed().prefix { $0.isNumber }
        guard !digits.isEmpty else { return (value, nil) }
        let numberText = String(digits.reversed())
        let prefix = String(value.dropLast(numberText.count))
        return (prefix, Int(numberText))
    }

    private static func data(named name: String, bundle: Bundle) throws -> Data {
        // XcodeGen may flatten `Resources/VocabData` into the bundle root or keep
        // it as a folder reference depending on how the resource entry is
        // written, so try both rather than depending on one of them.
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "VocabData")
            ?? bundle.url(forResource: name, withExtension: "json")

        guard let url else { throw ContentError.resourceMissing("\(name).json") }

        do {
            return try Data(contentsOf: url)
        } catch {
            throw ContentError.decodingFailed("\(name).json", error.localizedDescription)
        }
    }

    private static func log(_ message: String) {
        #if DEBUG
        print("[Content] \(message)")
        #endif
    }
}

// MARK: - Raw decoding shapes

private typealias RawFile = [String: RawBook]
private typealias RawBook = [String: RawSection]
private typealias RawSection = [String: RawWordList]

private struct RawWord: Decodable {
    let term: String
    let definition: String

    init(term: String, definition: String) {
        self.term = term
        self.definition = definition
    }

    private enum CodingKeys: String, CodingKey {
        case term, definition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        term = try container.decode(String.self, forKey: .term)
        definition = try container.decodeIfPresent(String.self, forKey: .definition) ?? ""
    }
}

/// Accepts either shape:
///
///     [{ "term": "abandon", "definition": "..." }]   <- ordered, preferred
///     { "abandon": "..." }                           <- legacy, alphabetised
private struct RawWordList: Decodable {
    let words: [RawWord]
    let wasUnordered: Bool

    init(from decoder: Decoder) throws {
        if let ordered = try? [RawWord](from: decoder) {
            words = ordered
            wasUnordered = false
            return
        }
        if let map = try? [String: String](from: decoder) {
            words = map
                .sorted { $0.key.lowercased() < $1.key.lowercased() }
                .map { RawWord(term: $0.key, definition: $0.value) }
            wasUnordered = true
            return
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected an array of {term, definition} objects or a term -> definition object."
            )
        )
    }
}

private struct CatalogFile: Decodable {
    let books: [CatalogBook]
}

private struct CatalogBook: Decodable {
    let id: String
    let title: String
    let shortTitle: String?
    let author: String?
    let intro: String?
    let theme: String?
    let sections: [CatalogSection]?
}

private struct CatalogSection: Decodable {
    let id: String
    let title: String?
    let kind: String?
    let intro: String?
}
