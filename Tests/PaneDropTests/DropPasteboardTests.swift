// The real pasteboard path: what lands on the shelf for a Finder drag.

import AppKit
import XCTest

@testable import PaneDrop

@MainActor
final class DropPasteboardTests: XCTestCase {

    func testFinderStyleDragKeepsTheFilename() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drop-pb-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let file = source.appendingPathComponent("report.pdf")
        try Data("x".utf8).write(to: file)

        let shelf = DropShelf(store: ShelfStore(root: root.appendingPathComponent("store")))
        let well = DropWellView()

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("topnotch.test.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])

        XCTAssertTrue(well.accepts(pasteboard))
        XCTAssertTrue(well.take(pasteboard, into: shelf))

        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(shelf.items.map(\.name), ["report.pdf"])
        XCTAssertEqual(shelf.items.first?.url.lastPathComponent, "report.pdf")
    }
}
