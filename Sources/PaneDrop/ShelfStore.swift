import Foundation

/// The scratch directory: copies in, expiry, purge and the on-disk index.
///
/// Layout, all of it created and owned by this type:
///
///     <root>/shelf.json          the index
///     <root>/items/<uuid>/<name> one parked file or folder per uuid directory
///     <root>/staging/<uuid>/     where a file promise is delivered before it is adopted
///
/// A uuid directory per item means two files called `report.pdf` never collide, the
/// original filename is preserved for the drag back out, and removing an item is a single
/// directory delete whose path shape can be verified before anything is unlinked.
///
/// Everything here runs off the main actor. The pane awaits it.
actor ShelfStore {
    /// How long an item lives before the sweep takes it.
    static let defaultLifetime: TimeInterval = 24 * 60 * 60
    /// The shelf is a parking space, not storage. Past this the oldest items fall off.
    static let defaultCapacity = 40
    /// A promise that never delivers leaves a staging directory behind. It is not an item,
    /// so it is not covered by item expiry and gets its own much shorter deadline.
    static let stagingLifetime: TimeInterval = 60 * 60

    nonisolated let root: URL
    nonisolated let itemsRoot: URL
    nonisolated let stagingRoot: URL
    private nonisolated let indexURL: URL

    private let lifetime: TimeInterval
    private let capacity: Int
    private var records: [ShelfRecord] = []

    init(
        root: URL? = nil,
        lifetime: TimeInterval = ShelfStore.defaultLifetime,
        capacity: Int = ShelfStore.defaultCapacity
    ) {
        let base = (root ?? ShelfStore.defaultRoot()).standardizedFileURL
        self.root = base
        self.itemsRoot = base.appending(path: "items", directoryHint: .isDirectory)
        self.stagingRoot = base.appending(path: "staging", directoryHint: .isDirectory)
        self.indexURL = base.appending(path: "shelf.json", directoryHint: .notDirectory)
        self.lifetime = max(lifetime, 1)
        self.capacity = max(capacity, 1)
    }

    /// `~/Library/Caches/<bundle id>/DropShelf`. Caches is right for a shelf that expires
    /// in a day, and the sweep reconciles the index if the system reclaims the directory.
    nonisolated static func defaultRoot() -> URL {
        let caches = FileManager().urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let bundle = Bundle.main.bundleIdentifier ?? "com.aliteo.topnotch"
        return caches
            .appending(path: bundle, directoryHint: .isDirectory)
            .appending(path: "DropShelf", directoryHint: .isDirectory)
    }

    // MARK: Reading

    /// Reads the index, drops entries whose files went missing, then sweeps. Call once at
    /// launch: this is where expired items from the last session are destroyed.
    func load() -> [ShelfItem] {
        prepareDirectories()
        records = readIndex().filter { record in
            FileManager().fileExists(atPath: fileURL(for: record).path(percentEncoded: false))
        }
        records.sort { $0.addedAt < $1.addedAt }
        sweep()
        return items()
    }

    func items() -> [ShelfItem] {
        records.map { record in
            ShelfItem(
                id: record.id,
                name: record.name,
                byteSize: record.byteSize,
                isDirectory: record.isDirectory,
                addedAt: record.addedAt,
                expiresAt: record.expiresAt,
                url: fileURL(for: record)
            )
        }
    }

    // MARK: Writing

    /// Copies a dropped URL in. The original is read and never touched again.
    func ingest(_ source: URL, now: Date = .now) -> ShelfChange {
        guard let record = install(source, now: now, move: false) else {
            return ShelfChange(items: items(), inserted: nil)
        }
        return admit(record)
    }

    /// Takes ownership of a file a promise just delivered into staging. It already lives
    /// in the scratch directory, so this moves rather than copies, then clears the
    /// staging directory the receiver created.
    func adopt(_ delivered: URL, now: Date = .now) -> ShelfChange {
        let staging = delivered.deletingLastPathComponent()
        defer { discard(staging, under: stagingRoot) }
        guard let record = install(delivered, now: now, move: true) else {
            return ShelfChange(items: items(), inserted: nil)
        }
        return admit(record)
    }

    func remove(_ id: UUID) -> [ShelfItem] {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return items() }
        let record = records.remove(at: index)
        destroy(record)
        writeIndex()
        return items()
    }

    func removeAll() -> [ShelfItem] {
        let doomed = records
        records = []
        for record in doomed { destroy(record) }
        purgeOrphans()
        writeIndex()
        return items()
    }

    // MARK: Expiry

    /// Removes everything past its deadline, trims to capacity, and deletes any directory
    /// under the scratch root that the index does not account for. Returns the live shelf.
    @discardableResult
    func sweep(now: Date = .now) -> [ShelfItem] {
        prepareDirectories()

        var kept: [ShelfRecord] = []
        for record in records {
            if record.expiresAt <= now { destroy(record) } else { kept.append(record) }
        }
        while kept.count > capacity {
            destroy(kept.removeFirst())
        }
        records = kept

        purgeOrphans()
        purgeStaging(now: now)
        writeIndex()
        return items()
    }

    // MARK: Paths

    nonisolated func fileURL(for record: ShelfRecord) -> URL {
        itemDirectory(record.id).appending(
            path: record.name,
            directoryHint: record.isDirectory ? .isDirectory : .notDirectory
        )
    }

    nonisolated func itemDirectory(_ id: UUID) -> URL {
        itemsRoot.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// A fresh directory for one file promise receiver to deliver into. Created eagerly
    /// because `NSFilePromiseReceiver` needs a destination that already exists.
    nonisolated func makeStagingDirectory() -> URL? {
        let directory = stagingRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager().createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }

    // MARK: Internals

    private func admit(_ record: ShelfRecord) -> ShelfChange {
        records.append(record)
        while records.count > capacity {
            destroy(records.removeFirst())
        }
        writeIndex()
        let inserted = items().first { $0.id == record.id }
        return ShelfChange(items: items(), inserted: inserted)
    }

    /// Copies or moves `source` into a new uuid directory. Returns nil and leaves nothing
    /// behind if anything fails, so a half-copied file never reaches the shelf.
    private func install(_ source: URL, now: Date, move: Bool) -> ShelfRecord? {
        prepareDirectories()
        let fm = FileManager()

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path(percentEncoded: false), isDirectory: &isDirectory)
        else { return nil }

        let id = UUID()
        let name = ShelfName.sanitized(source.lastPathComponent)
        let directory = itemDirectory(id)
        let destination = directory.appending(
            path: name,
            directoryHint: isDirectory.boolValue ? .isDirectory : .notDirectory
        )

        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            if move {
                try fm.moveItem(at: source, to: destination)
            } else {
                try fm.copyItem(at: source, to: destination)
            }
        } catch {
            discard(directory, under: itemsRoot)
            return nil
        }

        return ShelfRecord(
            id: id,
            name: name,
            byteSize: Self.byteSize(of: destination, isDirectory: isDirectory.boolValue),
            isDirectory: isDirectory.boolValue,
            addedAt: now,
            expiresAt: now.addingTimeInterval(lifetime)
        )
    }

    private func destroy(_ record: ShelfRecord) {
        discard(itemDirectory(record.id), under: itemsRoot)
    }

    /// The only delete in the module. Nothing is unlinked unless `ScratchGuard` agrees the
    /// path is a uuid directory directly inside a directory this store owns.
    private func discard(_ directory: URL, under parent: URL) {
        guard ScratchGuard.isPurgeable(directory, parent: parent) else { return }
        try? FileManager().removeItem(at: directory)
    }

    /// Directories the index does not know about: a crash between the copy and the index
    /// write, or a leftover from an older build.
    private func purgeOrphans() {
        let known = Set(records.map(\.id))
        for child in children(of: itemsRoot) {
            guard let id = UUID(uuidString: child.lastPathComponent) else { continue }
            guard !known.contains(id) else { continue }
            discard(child, under: itemsRoot)
        }
    }

    private func purgeStaging(now: Date) {
        for child in children(of: stagingRoot) {
            let created = (try? child.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? .distantPast
            guard now.timeIntervalSince(created) > Self.stagingLifetime else { continue }
            discard(child, under: stagingRoot)
        }
    }

    private func children(of directory: URL) -> [URL] {
        (try? FileManager().contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsSubdirectoryDescendants]
        )) ?? []
    }

    private func prepareDirectories() {
        let fm = FileManager()
        for directory in [itemsRoot, stagingRoot] {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func readIndex() -> [ShelfRecord] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ShelfRecord].self, from: data)) ?? []
    }

    private func writeIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Folder sizes come from a bounded walk. A shelf chip is never worth an unbounded
    /// enumeration of something the user dropped by accident.
    static func byteSize(of url: URL, isDirectory: Bool) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard isDirectory else {
            let values = try? url.resourceValues(forKeys: keys)
            return Int64(values?.fileSize ?? 0)
        }
        guard let walk = FileManager().enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        var seen = 0
        for case let child as URL in walk {
            seen += 1
            if seen > 20_000 { break }
            let values = try? child.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}
