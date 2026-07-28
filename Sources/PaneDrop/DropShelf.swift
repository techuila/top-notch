import AppKit
import Foundation
import NotchCore
import SwiftUI

/// The shelf as the UI sees it: an ordered list of parked files, a drag-hover flag, and
/// the sweep that enforces expiry.
///
/// All disk work is delegated to `ShelfStore`, which is an actor, so nothing here blocks
/// the main thread. Mutations are serialised through a single chain so five files dropped
/// at once land in the order they were dropped.
@MainActor
@Observable
final class DropShelf {
    /// Oldest first, which is the order the chips are laid out in.
    private(set) var items: [ShelfItem] = []

    /// True while a drag is over the notch. Drives the dashed border and the panel lift.
    private(set) var isTargeted = false

    /// Set by the shell. Fired the instant a drag enters the notch, including while the
    /// notch is still collapsed, so the panel can open and reveal the drop target without
    /// the user having to hover first.
    var onDragRequestsExpand: (() -> Void)?

    /// Gap between one file landing and the next, so a five file drop reads as five events.
    static let stagger: Duration = .milliseconds(70)
    /// How often expiry is checked. Deliberately lazy, and it only runs while the shelf
    /// has something on it.
    static let sweepInterval: Duration = .seconds(15 * 60)
    static let sweepTolerance: Duration = .seconds(120)

    /// Whether the expiry timer is running. It must be false whenever the shelf is empty:
    /// the app sits on screen all day and an empty shelf has nothing to expire.
    var isSweeping: Bool { sweepTask != nil }

    private let store: ShelfStore
    private var sweepTask: Task<Void, Never>?
    private var chain: Task<Void, Never>?
    private var didLoad = false

    init(store: ShelfStore = ShelfStore()) {
        self.store = store
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.byteSize } }

    // MARK: Lifecycle

    /// Restores the shelf and purges anything that expired while the app was not running.
    func load() {
        guard !didLoad else { return }
        didLoad = true
        enqueue { [weak self] in
            guard let self else { return }
            let restored = await self.store.load()
            self.apply(restored)
        }
    }

    // MARK: Drag in

    func beginTargeting() {
        onDragRequestsExpand?()
        guard !isTargeted else { return }
        withAnimation(Motion.reduced(Motion.tap)) { isTargeted = true }
    }

    func endTargeting() {
        guard isTargeted else { return }
        withAnimation(Motion.reduced(Motion.tap)) { isTargeted = false }
    }

    /// Copies real files in, one at a time, staggered.
    func ingest(urls: [URL]) {
        guard !urls.isEmpty else { return }
        enqueue { [weak self] in
            guard let self else { return }
            for (index, url) in urls.enumerated() {
                if index > 0 { try? await Task.sleep(for: Self.stagger) }
                let change = await self.store.ingest(url)
                self.apply(change.items)
            }
        }
    }

    /// A destination for one `NSFilePromiseReceiver` to write into.
    nonisolated func makeStagingDirectory() -> URL? {
        store.makeStagingDirectory()
    }

    /// Called once per file a promise delivers. The file is already inside the scratch
    /// directory at this point, so adopting it is a move.
    func adoptPromisedFile(at url: URL) {
        enqueue { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: Self.stagger)
            let change = await self.store.adopt(url)
            self.apply(change.items)
        }
    }

    // MARK: Mutation

    func remove(_ item: ShelfItem) {
        enqueue { [weak self] in
            guard let self else { return }
            let remaining = await self.store.remove(item.id)
            ThumbnailCache.shared.forget(item.id)
            self.apply(remaining)
        }
    }

    func clear() {
        let doomed = items.map(\.id)
        enqueue { [weak self] in
            guard let self else { return }
            let remaining = await self.store.removeAll()
            for id in doomed { ThumbnailCache.shared.forget(id) }
            self.apply(remaining)
        }
    }

    // MARK: Expiry

    private func sweep() async {
        let remaining = await store.sweep()
        apply(remaining)
    }

    /// One timer, only while the shelf has items, cancelled the moment it empties.
    private func updateSweepTask() {
        guard !items.isEmpty else {
            sweepTask?.cancel()
            sweepTask = nil
            return
        }
        guard sweepTask == nil else { return }
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.sweepInterval, tolerance: Self.sweepTolerance)
                guard !Task.isCancelled, let self else { return }
                await self.sweep()
            }
        }
    }

    // MARK: Plumbing

    private func apply(_ next: [ShelfItem]) {
        if next != items {
            withAnimation(Motion.reduced(Motion.content)) { items = next }
        }
        updateSweepTask()
    }

    /// Serialises every mutation. Two drops racing would otherwise interleave their
    /// staggered inserts and the shelf order would depend on copy speed.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = chain
        chain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}
