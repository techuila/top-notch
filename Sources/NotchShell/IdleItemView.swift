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

        case .ring(let progress, let label, let span):
            RingSlot(
                progress: progress,
                label: label,
                span: span,
                tint: Style.accent(for: entry.pane)
            )

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

/// A progress ring and its label, the pomodoro's permanent slot.
///
/// Given a `span` the arc and the digits are both derived from the clock here, so a running
/// countdown advances without the pane republishing every second. The redraw is the shell's
/// and it exists only while a session is genuinely running: a paused or stopped one carries
/// no span, falls back to the published values, and nothing ticks. That is the whole reason
/// the item carries a date range rather than a formatted string.
private struct RingSlot: View {
    let progress: Double
    let label: String
    let span: ClosedRange<Date>?
    let tint: Color

    var body: some View {
        if let span, span.upperBound > span.lowerBound {
            // Phased from the span's start so the tick lands on the second boundary the
            // user is actually counting, not on whenever this view happened to appear.
            TimelineView(.periodic(from: span.lowerBound, by: 1)) { context in
                let now = min(max(context.date, span.lowerBound), span.upperBound)
                let total = span.upperBound.timeIntervalSince(span.lowerBound)
                row(
                    progress: now.timeIntervalSince(span.lowerBound) / total,
                    label: notchTime(span.upperBound.timeIntervalSince(now))
                )
            }
        } else {
            row(progress: progress, label: label)
        }
    }

    private func row(progress: Double, label: String) -> some View {
        HStack(spacing: ShellMetrics.itemSpacing) {
            NotchRing(
                value: progress,
                size: Metrics.ringIdleSize,
                lineWidth: Metrics.idleProgressHeight,
                tint: tint
            )
            if !label.isEmpty {
                Text(label)
                    .font(Style.numeric)
                    .foregroundStyle(Style.ink)
                    .lineLimit(1)
            }
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

