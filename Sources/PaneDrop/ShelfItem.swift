import Foundation

/// One file parked on the shelf.
///
/// `url` always points at TopNotch's own copy inside the scratch directory. The user's
/// original is never moved, renamed or referenced after the copy completes, so an item
/// stays valid even if the source is deleted, ejected or was never on disk to begin with.
struct ShelfItem: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
    let byteSize: Int64
    let isDirectory: Bool
    let addedAt: Date
    let expiresAt: Date
    let url: URL

    func isExpired(at now: Date) -> Bool { expiresAt <= now }

    /// "1.2 MB". Folders report the total of everything inside them.
    var sizeText: String { byteSize.formatted(.byteCount(style: .file)) }
}

/// The persisted form of a `ShelfItem`. The location is not stored: it is always
/// `<root>/items/<id>/<name>`, so the shelf survives the container path moving.
struct ShelfRecord: Codable, Sendable, Equatable {
    var id: UUID
    var name: String
    var byteSize: Int64
    var isDirectory: Bool
    var addedAt: Date
    var expiresAt: Date
}

/// The result of a store mutation: the whole shelf, plus whatever this call added.
struct ShelfChange: Sendable {
    var items: [ShelfItem]
    var inserted: ShelfItem?
}

/// Filename hygiene. Names arrive from dragged URLs and from file promises, and a promise
/// can suggest anything at all, so nothing is trusted into a path without passing here.
enum ShelfName {
    static let maximumLength = 180

    static func sanitized(_ raw: String) -> String {
        let flattened = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !flattened.isEmpty, flattened != ".", flattened != ".." else { return "Untitled" }
        guard flattened.count > maximumLength else { return flattened }

        let ext = (flattened as NSString).pathExtension
        let base = (flattened as NSString).deletingPathExtension
        let room = ext.isEmpty ? maximumLength : maximumLength - ext.count - 1
        let clipped = String(base.prefix(max(room, 1)))
        return ext.isEmpty ? clipped : clipped + "." + ext
    }
}

/// The guard on every delete in the app.
///
/// Purging is the one operation here that can destroy data, so a path is only ever removed
/// when it is provably a direct child of a directory we created, named with a UUID we
/// generated. Symlinks and `..` are resolved before the check, so neither can walk out of
/// the scratch directory, and a parent shallower than three components is refused outright
/// so a misconfigured root can never point the sweep at somewhere near the volume root.
enum ScratchGuard {
    static let minimumParentDepth = 3

    static func isPurgeable(_ candidate: URL, parent: URL) -> Bool {
        let child = components(of: candidate)
        let root = components(of: parent)

        guard root.count >= minimumParentDepth else { return false }
        guard child.count == root.count + 1 else { return false }
        guard Array(child.prefix(root.count)) == root else { return false }
        guard let leaf = child.last, UUID(uuidString: leaf) != nil else { return false }
        return true
    }

    private static func components(of url: URL) -> [String] {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    }
}
