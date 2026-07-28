import NotchCore
import SwiftUI

/// Draws one idle slot item.
///
/// Artwork and waveform are drawn as clear anchors here and rendered for real by
/// `TravelLayer`, so the same view survives the jump from the idle bar to the open panel.
/// No `AnyView` anywhere in this path: every case resolves to a concrete view.
struct IdleItemView: View {
    let entry: IdleEntry
    let namespace: Namespace.ID
    let isSource: Bool

    var body: some View {
        switch entry.item {
        case .artwork:
            Color.clear
                .frame(width: Metrics.artworkIdleSize, height: Metrics.artworkIdleSize)
                .matchedGeometryEffect(
                    id: NotchTravelID.artwork.rawValue, in: namespace, isSource: isSource
                )

        case .waveform:
            Color.clear
                .frame(width: Metrics.rotorWidth, height: Metrics.rotorHeight)
                .matchedGeometryEffect(
                    id: NotchTravelID.waveform.rawValue, in: namespace, isSource: isSource
                )

        case .ring(let progress, let label):
            HStack(spacing: ShellMetrics.itemSpacing) {
                NotchRing(
                    value: progress,
                    size: Metrics.ringIdleSize,
                    lineWidth: Metrics.idleProgressHeight,
                    tint: Style.accent(for: entry.pane)
                )
                if !label.isEmpty {
                    Text(label)
                        .font(Style.numeric)
                        .foregroundStyle(Style.ink)
                        .lineLimit(1)
                }
            }

        case .badge(let symbol, let text):
            HStack(spacing: ShellMetrics.itemSpacing) {
                Image(systemName: symbol)
                    .font(Style.numeric)
                    .foregroundStyle(Style.accent(for: entry.pane))
                if !text.isEmpty {
                    Text(text)
                        .font(Style.numeric)
                        .foregroundStyle(Style.ink)
                        .lineLimit(1)
                }
            }

        case .glyph(let symbol):
            Image(systemName: symbol)
                .font(Style.numeric)
                .foregroundStyle(Style.accent(for: entry.pane))
                .frame(width: Metrics.ringIdleSize, height: Metrics.ringIdleSize)
        }
    }
}

/// Album art at whatever size the matched geometry hands it. The corner radius scales with
/// the travel so the same rounding reads correctly at 24pt and at full size.
struct ArtworkView: View {
    let image: NotchImage?

    var body: some View {
        GeometryReader { geo in
            let radius = Style.artworkRadius * (geo.size.width / ShellMetrics.expandedArtwork)
            Group {
                if let image, let decoded = ArtworkCache.shared.image(for: image) {
                    Image(nsImage: decoded)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Style.fill)
                        .overlay {
                            Image(systemName: PaneID.music.glyph)
                                .font(Style.numeric)
                                .foregroundStyle(Style.inkFaint)
                        }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: max(radius, 1), style: .continuous))
        }
    }
}

/// Five bars by house convention, but it draws whatever it is given.
struct WaveformView: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geo in
            let count = max(levels.count, 1)
            let unit = geo.size.width / CGFloat(count * 2 - 1)
            HStack(alignment: .center, spacing: unit) {
                ForEach(0..<count, id: \.self) { index in
                    let level = index < levels.count ? CGFloat(levels[index]) : 0
                    Capsule()
                        .fill(Style.ink)
                        .frame(
                            width: unit,
                            height: max(geo.size.height * min(max(level, 0), 1), unit)
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .notchAnimation(Motion.ambient, value: levels)
    }
}
