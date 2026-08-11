import NotchCore
import SwiftUI

/// The closed notch.
///
/// Layout is three columns: left shoulder, a dead spacer exactly as wide as the camera
/// housing, right rotor. The bar sizes itself to its content and reports that width up, so
/// the black surface narrows around slots as they collapse rather than jumping.
struct IdleBarView: View {
    let model: NotchShellModel
    let composition: IdleComposition
    let namespace: Namespace.ID
    let onWidth: (CGFloat) -> Void

    private var isSource: Bool { model.phase != .expanded }

    private var shoulderPadding: CGFloat {
        model.phase == .proximity
            ? ShellMetrics.proximityShoulderPadding
            : ShellMetrics.idleShoulderPadding
    }

    /// Side of the expanded music tile, handed down so the artwork thumb's rounding
    /// stays proportional to the tile it stands in for.
    private var musicBand: CGFloat {
        model.pane(.music)?.contentHeight ?? Metrics.defaultPaneHeight
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
            // The camera housing. Nothing is ever drawn here.
            Color.clear.frame(width: model.geometry.hardwareWidth)
            trailing
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxHeight: .infinity)
        .notchAnimation(Motion.slot, value: composition)
        .notchAnimation(Motion.slot, value: shoulderPadding)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidth($0) }
        .task(id: composition.rotor) {
            await model.runRotor(count: composition.rotor.count)
        }
    }

    private var leading: some View {
        HStack(spacing: Metrics.slotSpacing) {
            if let pinned = composition.pinned {
                IdleItemView(
                    entry: pinned, artworkFullSize: musicBand,
                    travel: namespace, isTravelSource: isSource
                )
            }
            if let identity = composition.identity {
                IdleItemView(
                    entry: identity, artworkFullSize: musicBand,
                    travel: namespace, isTravelSource: isSource
                )
            }
        }
        .padding(.horizontal, composition.hasLeading ? shoulderPadding : 0)
    }

    private var trailing: some View {
        RotorView(
            entries: composition.rotor,
            index: model.rotorIndex,
            artworkFullSize: musicBand,
            travel: namespace,
            isSource: isSource
        )
        .padding(.horizontal, composition.rotor.isEmpty ? 0 : shoulderPadding)
    }
}

/// The right shoulder. Items translate vertically through a clipped fixed-width window,
/// like a slot machine reel. Nothing ever cross-fades, and a single item never moves.
struct RotorView: View {
    let entries: [IdleEntry]
    let index: Int
    let artworkFullSize: CGFloat
    let travel: Namespace.ID
    let isSource: Bool

    private var clamped: Int {
        entries.isEmpty ? 0 : min(max(index, 0), entries.count - 1)
    }

    var body: some View {
        ZStack {
            ForEach(Array(entries.enumerated()), id: \.offset) { offset, entry in
                IdleItemView(
                    entry: entry,
                    artworkFullSize: artworkFullSize,
                    travel: travel,
                    // Only the item parked in the window sources the travel; a slot
                    // sliding through must never drag the travelling view with it.
                    isTravelSource: isSource && offset == clamped
                )
                .frame(width: Metrics.rotorWidth, height: Metrics.rotorHeight)
                .offset(y: CGFloat(offset - clamped) * Metrics.rotorHeight)
            }
        }
        .frame(
            width: entries.isEmpty ? 0 : Metrics.rotorWidth,
            height: Metrics.rotorHeight
        )
        .clipped()
        .notchAnimation(Motion.rotate, value: clamped)
    }
}

/// The elements that live through the open and close morphs: the bottom-edge progress
/// line, the album art and the waveform.
///
/// Components that exist in both states travel to their place, they never hide and
/// show (owner decision, 2026-08-12, restoring the move-don't-swap rule). Each has
/// exactly one instance, mounted continuously here, following matched anchors: the
/// progress line rides the surface's bottom edge (idle border, expanded border on
/// non-music panes, hidden while the scrubber owns it), and the art and waveform morph
/// between their idle slots and their places in the music pane.
///
/// Every anchor on both sides is a permanently mounted live view; only `isSource`
/// swaps with the phase. No anchor is ever inside a transition: a view leaving
/// through one freezes and stops updating, so it keeps claiming a geometry it no
/// longer has - that frozen-anchor failure is what made the border line vanish on
/// some panes and idle items linger over the open panel.
struct TravelLayer: View {
    let model: NotchShellModel
    let namespace: Namespace.ID

    private var isExpanded: Bool { model.phase == .expanded }
    private var isOnMusic: Bool { model.landed == .music }

    /// Side of the expanded music tile: the pane's artwork spans its full content band,
    /// so the travelling art's destination is a square of that height at the pane inset.
    private var musicBand: CGFloat {
        model.pane(.music)?.contentHeight ?? Metrics.defaultPaneHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The travelling album art: one instance, mounted continuously while any
            // pane parks artwork on the left shoulder. Matched to the idle slot while
            // closed and to the music tile's spot while open, so opening morphs the
            // little thumb up and into the tile's place; the pane's own tile fades in
            // over the same rectangle and takes over.
            if model.travellingArtwork.present {
                ArtworkView(image: model.travellingArtwork.image, fullSize: musicBand)
                    .matchedGeometryEffect(
                        id: NotchTravelID.artwork.rawValue, in: namespace, isSource: false
                    )
                    .opacity(isExpanded ? 0 : 1)
            }

            // The travelling waveform, same deal: idle rotor slot to the music
            // pane's trailing waveform, one instance, handing off by opacity at the
            // ends of the flight.
            if let levels = model.travellingWaveform {
                NotchWaveform(levels: levels, isPlaying: levels.contains { $0 > 0.06 })
                    .matchedGeometryEffect(
                        id: NotchTravelID.waveform.rawValue, in: namespace, isSource: false
                    )
                    .opacity(isExpanded ? 0 : 1)
            }

            // The progress line is laid out directly, not matched: this layer spans
            // the live surface in every phase, so the line hugging its bottom edge
            // with phase-driven insets is pure token math. No anchors, no sources,
            // nothing that can be lost or fought over mid-morph.
            if let progress = model.composition.progress {
                NotchProgress(
                    value: progress,
                    height: Metrics.idleProgressHeight,
                    tint: Style.accent(
                        for: model.composition.progressPane ?? model.focusedID
                    ),
                    // Music's accent is plain white. At full strength on a black notch
                    // that is a glowing stub, not a progress line.
                    prominence: 0.25
                )
                .padding(.horizontal, lineInset)
                .padding(.bottom, lineLift)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .opacity(isExpanded && isOnMusic ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The expanded anchors ride an overlay so their fixed sizes can never
        // inflate this layer. As ZStack children they did exactly that: the artwork
        // anchor's square plus its top padding set a 208pt floor under the layer,
        // and on any pane whose panel is shorter (drop, at 178) the bottom-aligned
        // progress line was pushed below the drawn surface and clipped away. An
        // overlay never affects its host's layout, so the layer is always exactly
        // the surface and the line always sits on the real bottom edge.
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                expandedArtworkAnchor
                expandedWaveAnchor
            }
        }
        .allowsHitTesting(false)
    }

    /// The line's horizontal inset from the surface edges: stops short of where the
    /// bottom corners curve away in each state, and pulls in to the pane inset while
    /// the music pane is landed so it meets the scrubber it hands over to.
    private var lineInset: CGFloat {
        guard isExpanded else { return Metrics.idleProgressInset }
        return isOnMusic ? Metrics.paneInset : ShellMetrics.expandedProgressInset
    }

    /// The line's lift off the bottom edge: the border lift everywhere, the pane
    /// bottom while the scrubber owns the music pane.
    private var lineLift: CGFloat {
        isExpanded && isOnMusic ? Metrics.paneBottom : ShellMetrics.progressEdgeLift
    }

    /// Where the travelling art lands while the panel is open: the music pane's tile,
    /// which top-aligns with the pane band at the pane inset and spans the band's full
    /// height. The same spot regardless of the landed pane, so on a non-music landing
    /// the art still reads as absorbed into the panel rather than snapping away.
    private var expandedArtworkAnchor: some View {
        Color.clear
            .frame(width: musicBand, height: musicBand)
            .matchedGeometryEffect(
                id: NotchTravelID.artwork.rawValue, in: namespace, isSource: isExpanded
            )
            .padding(.leading, Metrics.paneInset)
            .padding(.top, Metrics.paneTop + ShellMetrics.pillBreathingRoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Where the travelling waveform lands: the music pane's trailing waveform, a
    /// fixed-width column against the trailing pane inset, vertically centred in the
    /// content band exactly as the pane lays its own out.
    private var expandedWaveAnchor: some View {
        Color.clear
            .frame(width: ShellMetrics.expandedWaveWidth, height: musicBand)
            .matchedGeometryEffect(
                id: NotchTravelID.waveform.rawValue, in: namespace, isSource: isExpanded
            )
            .padding(.trailing, Metrics.paneInset)
            .padding(.top, Metrics.paneTop + ShellMetrics.pillBreathingRoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
