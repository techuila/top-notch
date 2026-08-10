import Foundation

/// One note as it sits on disk: plain JSON with the text in the clear.
///
/// Format 2. Format 1 was an encrypted record whose body lived in a `sealed` field and
/// whose key sat in the Keychain. That feature is gone, so a format 1 file can no longer
/// be read at all. `loadAll` skips such files and leaves them on disk untouched.
struct NoteRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var created: Date
    var modified: Date
    var text: String
    var format: Int

    static let currentFormat = 2
}

/// Every way reading or writing a note file can fail, with a sentence for the user.
enum NoteStoreError: Error, Equatable {
    case storage(String)

    var message: String {
        switch self {
        case .storage(let detail):
            "The note could not be written: \(detail)"
        }
    }
}

/// Reads and writes note files.
struct NoteFileStore {
    let directory: URL

    private static let fileExtension = "tnote"

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.directory = support.appendingPathComponent("TopNotch/Notes", isDirectory: true)
        }
    }

    func prepare() throws(NoteStoreError) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw NoteStoreError.storage(error.localizedDescription)
        }
    }

    /// Loads every readable note, newest first.
    ///
    /// A file that does not decode as a current record is skipped, not deleted. That
    /// covers notes encrypted by an earlier build: they cannot be decrypted any more,
    /// but the bytes stay on disk exactly as they were, so nothing is lost if the user
    /// ever wants to recover them by other means.
    func loadAll() -> [NoteRecord] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let decoder = JSONDecoder()
        return urls
            .filter { $0.pathExtension == Self.fileExtension }
            .compactMap { url -> NoteRecord? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(NoteRecord.self, from: data)
            }
            .sorted { $0.modified > $1.modified }
    }

    func write(_ record: NoteRecord) throws(NoteStoreError) {
        try prepare()
        do {
            let data = try JSONEncoder().encode(record)
            let url = url(for: record.id)
            try data.write(to: url, options: [.atomic])
            // 0600 after the fact: `Data.write` creates the temporary file with the
            // process umask, so the mode has to be set on the final file.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw NoteStoreError.storage(error.localizedDescription)
        }
    }

    func delete(id: UUID) throws(NoteStoreError) {
        do {
            let url = url(for: id)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            throw NoteStoreError.storage(error.localizedDescription)
        }
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(Self.fileExtension)
    }
}
