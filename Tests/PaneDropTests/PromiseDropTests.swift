// A file promise is what arrives from Safari or Mail: no file on disk yet, only a promise
// to write one. AppKit will not resolve a promise inside one process, so what is checked
// here is that the well recognises one at all; the delivery itself is exercised by
// dragging a real promise onto the notch.

import AppKit
import UniformTypeIdentifiers
import XCTest

@testable import PaneDrop

/// Stands in for Safari: promises one file and writes its bytes on demand.
final class TestPromiseSource: NSObject, NSFilePromiseProviderDelegate {
    let promisedName: String
    init(promisedName: String) { self.promisedName = promisedName }

    func filePromiseProvider(
        _ provider: NSFilePromiseProvider,
        fileNameForType type: String
    ) -> String {
        promisedName
    }

    func filePromiseProvider(
        _ provider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        do {
            try Data("x".utf8).write(to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

@MainActor
final class PromiseDropTests: XCTestCase {

    /// A promise must be read as a promise. Reading it as a URL instead is how a dragged
    /// image from a browser silently vanishes.
    func testPromiseIsAcceptedAndReadAsAPromise() throws {
        let source = TestPromiseSource(promisedName: "photo.png")
        let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: source)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("topnotch.promise.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([provider])

        let well = DropWellView()
        XCTAssertTrue(well.accepts(pasteboard))

        let read = pasteboard.readObjects(
            forClasses: DropWellView.readableClasses,
            options: DropWellView.readingOptions
        ) ?? []
        XCTAssertEqual(read.count, 1)
        XCTAssertTrue(read.first is NSFilePromiseReceiver)
        withExtendedLifetime(source) {}
    }
}
