import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backup envelope

/// A progress file plus enough metadata to recognise it later.
///
/// The raw `ProgressState` would round-trip on its own, but a bare JSON blob
/// gives the import side nothing to check: any `.json` the user picks would
/// decode into *something*, and a wrong file would silently replace real study
/// history. The `app` marker makes a mistaken pick fail loudly instead.
struct ProgressBackup: Codable {
    /// Bumped only if the envelope itself changes shape. `ProgressState` has its
    /// own `schemaVersion` and decodes field-by-field with defaults, so adding a
    /// field to progress does not require a new format here.
    static let currentFormat = 1
    static let marker = "TOEFLVocab"

    let format: Int
    let app: String
    let appVersion: String
    let exportedAt: Date
    let progress: ProgressState

    init(progress: ProgressState, appVersion: String, exportedAt: Date = Date()) {
        self.format = Self.currentFormat
        self.app = Self.marker
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.progress = progress
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Readable on purpose: a backup the user can open and eyeball is a
        // backup they can trust, and the file is a few hundred KB at most.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Decodes and validates. Throws rather than returning a partial result, so
    /// a caller can never half-apply a bad file.
    static func decode(from data: Data) throws -> ProgressBackup {
        let backup: ProgressBackup
        do {
            backup = try decoder.decode(ProgressBackup.self, from: data)
        } catch {
            throw BackupError.notABackupFile
        }

        guard backup.app == marker else { throw BackupError.notABackupFile }
        guard backup.format <= currentFormat else {
            throw BackupError.newerFormat(backup.format)
        }
        return backup
    }

    /// Summary shown in the confirmation prompt, so the user can see what they
    /// are about to restore before it replaces anything.
    var summary: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let words = Set(progress.main.keys).union(progress.extra.keys).count
        return "\(words) words · \(progress.sessions.count) sessions · \(formatter.string(from: exportedAt))"
    }
}

// MARK: - Errors

enum BackupError: LocalizedError, Equatable {
    case notABackupFile
    case newerFormat(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notABackupFile:
            return "That file is not a TOEFL Vocab progress backup."
        case .newerFormat(let format):
            return "This backup was made by a newer version of the app (format \(format))."
        case .unreadable:
            return "The file could not be read."
        }
    }
}

// MARK: - Document

/// Wrapper required by SwiftUI's `fileExporter`.
struct ProgressBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw BackupError.unreadable
        }
        self.data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Store integration

extension ProgressStore {

    /// Current progress as a backup file's contents.
    func exportBackup(appVersion: String = ProgressStore.bundleVersion) throws -> Data {
        let backup = ProgressBackup(progress: state, appVersion: appVersion)
        return try ProgressBackup.encoder.encode(backup)
    }

    /// Validates `data` and, only if it is a genuine backup, replaces all
    /// progress with it and writes through to disk immediately.
    ///
    /// Restoring is destructive by nature — the point is to overwrite whatever
    /// the current install has — so callers confirm with the user first. The
    /// decode happens before anything is touched, so an invalid file leaves the
    /// existing history intact.
    @discardableResult
    func importBackup(_ data: Data) throws -> ProgressBackup {
        let backup = try ProgressBackup.decode(from: data)
        replaceState(with: backup.progress)
        return backup
    }

    /// Reads a file returned by `fileImporter`, handling the security-scoped
    /// access that documents outside the app's container require.
    static func readBackupFile(at url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            return try Data(contentsOf: url)
        } catch {
            throw BackupError.unreadable
        }
    }

    static var bundleVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }
}
