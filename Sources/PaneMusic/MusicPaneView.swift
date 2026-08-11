import AppKit
import NotchCore
import SwiftUI

/// The expanded music pane.
///
/// Artwork leads, waveform trails, and the column between them holds the title, the
/// scrubber and the transport. Those three slots are present whether or not anything is
/// playing, so going from silence to a track moves and fills them rather than replacing
/// the pane with a different one.
struct MusicPaneView: View {
    let pane: MusicPane

    private var state: NowPlayingState { pane.coordinator.state }

    var body: some View {
        // Top-aligned, the classic player layout: the top of the art lines up with the
        // top of the title. Centring the 74pt tile against the taller text column put
        // the title above the art, which read as misproportioned.
        HStack(alignment: .top, spacing: 14) {
            ArtworkView(artwork: state.track?.artwork)

            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(text: title)
                Text(subtitle)
                    .font(Style.subtitle)
                    .foregroundStyle(Style.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if state.isLive {
                    // Greedy: fills everything under the subtitle and distributes it
                    // evenly around the scrubber with its internal spacers.
                    TransportBlock(pane: pane)
                } else {
                    Spacer(minLength: 0)
                    EmptyStateActions(pane: pane)
                }
            }

            WaveformView(levels: pane.levels, isPlaying: state.status == .playing)
                .frame(width: state.isLive ? 26 : 0)
                .opacity(state.isLive ? 1 : 0)
                // Stays vertically centred as before the top-alignment change, so the
                // shell's travel anchor for the waveform still lands on it.
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paneInsets()
        .notchAnimation(Motion.content, value: state.isLive)
        .notchAnimation(Motion.content, value: state.track?.id)
    }

    private var title: String {
        guard let track = state.track, !track.title.isEmpty else { return "Nothing playing" }
        return track.title
    }

    private var subtitle: String {
        // A denied Apple Event is silent and permanent, so it has to be said out loud
        // wherever there is room. Without this the buttons simply do nothing.
        if case .automationDenied(let player) = state.issue {
            return "Allow Automation for \(player) in System Settings to control playback."
        }
        if let track = state.track {
            let parts = [track.artist, track.album].filter { !$0.isEmpty }
            return parts.isEmpty ? (state.player?.name ?? "") : parts.joined(separator: "  -  ")
        }
        if pane.coordinator.installedPlayers.isEmpty {
            return "No supported player is installed."
        }
        return "Start a track, or open one from here."
    }
}

// MARK: Artwork

/// The album art: a square spanning the full content band, top of the title to the
/// bottom of the transport. Sized by aspect ratio against the proposed band height
/// rather than a constant, so it tracks `contentHeight` without a second number.
private struct ArtworkView: View {
    let artwork: NotchImage?

    var body: some View {
        RoundedRectangle(cornerRadius: Style.artworkRadius, style: .continuous)
            .fill(Style.fill)
            .overlay {
                if let artwork, let image = ArtworkCache.shared.image(for: artwork) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: PaneID.music.glyph)
                        .font(Style.title)
                        .imageScale(.large)
                        .foregroundStyle(Style.inkFaint)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Style.artworkRadius, style: .continuous))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxHeight: .infinity)
            .notchAnimation(Motion.content, value: artwork?.id)
    }
}

// MARK: Waveform

/// The pane draws the shared waveform at its expanded size; the shell draws the same
/// element in the idle shoulder, so the two states are one drawing.
private struct WaveformView: View {
    let levels: [Float]
    let isPlaying: Bool

    private static let maxHeight: CGFloat = 46

    var body: some View {
        NotchWaveform(levels: levels, isPlaying: isPlaying)
            .frame(
                width: NotchWaveform.naturalWidth(barCount: levels.count),
                height: Self.maxHeight
            )
    }
}

// MARK: Transport

private struct TransportBlock: View {
    let pane: MusicPane

    @State private var scrubFraction: Double?

    private var state: NowPlayingState { pane.coordinator.state }
    private var duration: TimeInterval { state.track?.duration ?? 0 }
    private var shownFraction: Double { scrubFraction ?? pane.fraction }
    private var shownElapsed: TimeInterval {
        scrubFraction.map { $0 * duration } ?? pane.elapsed
    }

    var body: some View {
        // Twin spacers centre the scrubber between the text block above and the
        // buttons below: the two gaps are equal by construction.
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Scrubber(
                fraction: shownFraction,
                onScrub: { scrubFraction = $0 },
                onCommit: { target in
                    pane.seek(fraction: target)
                    scrubFraction = nil
                }
            )

            Spacer(minLength: 0)

            ZStack {
                HStack(spacing: 0) {
                    Text(notchTime(shownElapsed))
                    Spacer(minLength: 0)
                    Text(notchTime(duration))
                }
                .font(Style.numeric)
                .foregroundStyle(Style.inkMuted)

                HStack(spacing: 0) {
                    ModeButton(
                        symbol: "shuffle",
                        available: state.shuffle != nil,
                        selected: state.shuffle == true,
                        label: state.shuffle == true ? "Shuffle on" : "Shuffle off"
                    ) { pane.toggleShuffle() }
                    NotchButton("backward.fill", size: 12) { pane.previous() }
                        .accessibilityLabel("Previous track")
                    NotchButton(state.status == .playing ? "pause.fill" : "play.fill", size: 16) {
                        pane.toggle()
                    }
                    .accessibilityLabel(state.status == .playing ? "Pause" : "Play")
                    NotchButton("forward.fill", size: 12) { pane.next() }
                        .accessibilityLabel("Next track")
                    ModeButton(
                        symbol: state.repeatMode == .one ? "repeat.1" : "repeat",
                        available: state.repeatMode != nil,
                        selected: (state.repeatMode ?? .off) != .off,
                        label: repeatLabel
                    ) { pane.cycleRepeat() }
                }
            }
        }
    }

    private var repeatLabel: String {
        switch state.repeatMode ?? .off {
        case .off: "Repeat off"
        case .all: "Repeat all"
        case .one: "Repeat one"
        }
    }
}

/// Shuffle or repeat: a toggle that exists only when the active source can read the
/// state it would show. When it cannot, the slot collapses to zero width and the
/// transport slides together, the same move the trailing waveform makes, rather than
/// the button vanishing in place.
private struct ModeButton: View {
    let symbol: String
    let available: Bool
    let selected: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        NotchButton(symbol, size: 10, isSelected: selected, action: action)
            .frame(width: available ? nil : 0)
            .opacity(available ? 1 : 0)
            .allowsHitTesting(available)
            .notchAnimation(Motion.content, value: available)
            .accessibilityLabel(label)
            .accessibilityHidden(!available)
    }
}

/// The scrubber. Visually the 3pt line the rest of the app uses, with a grab target more
/// than five times taller so it can actually be hit without aiming.
private struct Scrubber: View {
    let fraction: Double
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void

    @State private var width: CGFloat = 0
    @State private var hovering = false
    @State private var dragging = false

    private static let grabHeight: CGFloat = 18

    var body: some View {
        NotchProgress(value: fraction, height: hovering || dragging ? 5 : 3)
            .frame(height: Self.grabHeight)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        onScrub(target(from: value.location.x))
                    }
                    .onEnded { value in
                        dragging = false
                        onCommit(target(from: value.location.x))
                    }
            )
            .notchAnimation(Motion.tap, value: hovering)
            .notchAnimation(Motion.tap, value: dragging)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Int(fraction * 100)) percent")
    }

    private func target(from x: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }
}

// MARK: Empty state

/// What the pane offers when nothing is playing.
///
/// The requirement it exists for: with Spotify closed, the user can open Spotify and start
/// playback without leaving the notch.
private struct EmptyStateActions: View {
    let pane: MusicPane

    private var coordinator: NowPlayingCoordinator { pane.coordinator }

    var body: some View {
        HStack(spacing: 8) {
            if case .automationDenied = coordinator.state.issue {
                ActionChip(symbol: "lock.open", label: "Open Settings") {
                    coordinator.openAutomationSettings()
                }
            }
            ForEach(coordinator.installedPlayers) { option in
                LaunchChip(
                    option: option,
                    launching: coordinator.launchingPlayer == option.id,
                    action: { coordinator.launch(option) }
                )
            }
            Spacer(minLength: 0)
        }
        .frame(height: 34)
    }
}

private struct LaunchChip: View {
    let option: MusicPlayerOption
    let launching: Bool
    let action: () -> Void

    @State private var icon: NSImage?

    var body: some View {
        NotchTile {
            HStack(spacing: 6) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 15, height: 15)
                } else {
                    Image(systemName: "play.circle")
                        .font(Style.subtitle)
                }
                Text(launching ? "Starting \(option.name)" : "Play in \(option.name)")
                    .font(Style.subtitle)
                    .foregroundStyle(Style.ink)
                    .lineLimit(1)
            }
        }
        .opacity(launching ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .task { icon = option.icon }
        .notchAnimation(Motion.tap, value: launching)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Play in \(option.name)")
    }
}

private struct ActionChip: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        NotchTile {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(Style.subtitle)
                Text(label).font(Style.subtitle).lineLimit(1)
            }
            .foregroundStyle(Style.ink)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityAddTraits(.isButton)
    }
}
