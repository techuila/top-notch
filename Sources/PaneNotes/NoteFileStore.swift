import Foundation

/// One note as it sits on disk.
///
/// Everything outside `sealed` is metadata the app needs before it can decrypt anything.
/// It is deliberately thin: no title, no preview, no word count, nothing that would let a
/// reader of the file learn what the note says.
struct NoteRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var isPrivate: Bool
    var created: Date
    var modified: Date
    /// 0 to 3. A very coarse bucket of the title's length, and the only thing a private
    /// note leaks. It exists so the blurred placeholder in the list is roughly as wide as
    /// the real title, which is what makes a locked row read as hidden rather than empty.
    var titleHint: Int
    /// AES-GCM combined box: nonce, ciphertext, tag.
    var sealed: Data
    var format: Int

    static func titleHint(for text: String) -> Int {
        let firstLine = text.prefix(while: { !$0.isNewline }).count
        return min(3, firstLine / 8)
    }
}

/// Reads and writes note files. Knows nothing about keys: it only ever sees sealed bytes.
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

    func prepare() throws(NoteLockError) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw NoteLockError.storage(error.localizedDescription)
        }
    }

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

    func write(_ record: NoteRecord) throws(NoteLockError) {
        try prepare()
        do {
            let data = try JSONEncoder().encode(record)
            let url = url(for: record.id)
            try data.write(to: url, options: [.atomic])
            // 0600 after the fact: `Data.write` creates the temporary file with the
            // process umask, so the mode has to be set on the final file.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw NoteLockError.storage(error.localizedDescription)
        }
    }

    func delete(id: UUID) throws(NoteLockError) {
        do {
            let url = url(for: id)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            throw NoteLockError.storage(error.localizedDescription)
        }
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(Self.fileExtension)
    }
}
