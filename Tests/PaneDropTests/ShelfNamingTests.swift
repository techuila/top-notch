// Naming of files parked on the shelf.

import AppKit
import XCTest

@testable import PaneDrop

final class ShelfNamingTests: XCTestCase {

    private var root: URL!
    private var source: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drop-tests-\(UUID().uuidString)")
        source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = source.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    func testDroppedURLKeepsItsFilename() async throws {
        let store = ShelfStore(root: root.appendingPathComponent("store"))
        let file = try makeFile("report.pdf")
        let change = await store.ingest(file)
        XCTAssertEqual(change.inserted?.name, "report.pdf")
    }

    func testPromisedFileKeepsItsFilename() async throws {
        let store = ShelfStore(root: root.appendingPathComponent("store"))
        let staging = store.makeStagingDirectory()!
        let delivered = staging.appendingPathComponent("photo.png")
        try Data("x".utf8).write(to: delivered)
        let change = await store.adopt(delivered)
        XCTAssertEqual(change.inserted?.name, "photo.png")
    }

    /// Dragging a chip out used to land as `report.pdf.pdf`: the receiver appends the
    /// extension for the type it asked for, so the name handed over must not carry one.
    func testSuggestedNameForADragOutDropsTheExtension() {
        XCTAssertEqual(ShelfName.suggested("report.pdf"), "report")
        XCTAssertEqual(ShelfName.suggested("photo.png"), "photo")
        XCTAssertEqual(ShelfName.suggested("archive.tar.gz"), "archive.tar")
        XCTAssertEqual(ShelfName.suggested("README"), "README")
        XCTAssertEqual(ShelfName.suggested("notes.2026.06.txt"), "notes.2026.06")
    }

    func testSanitizerDoesNotRepeatTheExtension() {
        XCTAssertEqual(ShelfName.sanitized("photo.png"), "photo.png")
        XCTAssertEqual(ShelfName.sanitized("archive.tar.gz"), "archive.tar.gz")
        let long = String(repeating: "a", count: 400) + ".png"
        let clipped = ShelfName.sanitized(long)
        XCTAssertTrue(clipped.hasSuffix(".png"))
        XCTAssertFalse(clipped.hasSuffix(".png.png"))
    }
}
