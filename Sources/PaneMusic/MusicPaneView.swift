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
        HStack(spacing: 14) {
            ArtworkView(artwork: state.track?.artwork)

            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(text: title)
                Text(subtitle)
                    .font(Style.subtitle)
                    .foregroundStyle(Style.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                if state.isLive {
                    TransportBlock(pane: pane)
                } else {
                    EmptyStateActions(pane: pane)
                }
            }

            WaveformView(levels: pane.levels, isPlaying: state.status == .playing)
                .frame(width: state.isLive ? 26 : 0)
                .opacity(state.isLive ? 1 : 0)
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

private struct ArtworkView: View {
    let artwork: NotchImage?

    private static let side: CGFloat = 74

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
            .frame(width: Self.side, height: Self.side)
            .notchAnimation(Motion.content, value: artwork?.id)
    }
}

// MARK: Waveform

private struct WaveformView: View {
    let levels: [Float]
    let isPlaying: Bool

    private static let barWidth: CGFloat = 3
    private static let maxHeight: CGFloat = 46

    var body: some View {
        HStack(alignment: .center, spacing: Self.barWidth) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Style.ink.opacity(isPlaying ? 0.85 : 0.35))
                    .frame(
                        width: Self.barWidth,
                        height: max(Self.barWidth, CGFloat(level) * Self.maxHeight)
                    )
            }
        }
        .frame(height: Self.maxHeight)
        // Bars are already smoothed by the generator, so playing frames are drawn as they
        // come. Only the collapse into a flat line on pause is animated.
        .notchAnimation(Motion.ambient, value: isPlaying)
        .accessibilityHidden(true)
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
        VStack(spacing: 2) {
            Scrubber(
                fraction: shownFraction,
                onScrub: { scrubFraction = $0 },
                onCommit: { target in
                    pane.seek(fraction: target)
                    scrubFraction = nil
                }
            )

            ZStack {
                HStack(spacing: 0) {
                    Text(notchTime(shownElapsed))
                    Spacer(minLength: 0)
                    Text(notchTime(duration))
                }
                .font(Style.numeric)
                .foregroundStyle(Style.inkMuted)

                HStack(spacing: 0) {
                    NotchButton("backward.fill", size: 12) { pane.previous() }
                        .accessibilityLabel("Previous track")
                    NotchButton(state.status == .playing ? "pause.fill" : "play.fill", size: 16) {
                        pane.toggle()
                    }
                    .accessibilityLabel(state.status == .playing ? "Pause" : "Play")
                    NotchButton("forward.fill", size: 12) { pane.next() }
                        .accessibilityLabel("Next track")
                }
            }
        }
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
