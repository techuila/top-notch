import AppKit
import NotchCore

/// Live markdown, the Obsidian way: the note is plain markdown on disk and in the text
/// storage, and the view dresses it. The line the caret is on shows its syntax, every
/// other line shows the result.
///
/// Nothing is ever inserted into or removed from the text to do this. The styler writes
/// fonts, colours and two private attributes into the storage, and the layout manager
/// turns marker characters into null glyphs (no width, not drawn) on inactive lines and
/// swaps a list dash for a bullet glyph. Character offsets therefore stay identical to
/// the markdown, which is what keeps selection, undo and autosave honest.
@MainActor
final class MarkdownStyler: NSObject, @preconcurrency NSTextStorageDelegate, @preconcurrency NSLayoutManagerDelegate {

    /// On a syntax character. Hidden unless its line is being edited.
    static let marker = NSAttributedString.Key("topnotch.markdown.marker")
    /// On a list dash. Drawn as a bullet unless its line is being edited.
    static let bullet = NSAttributedString.Key("topnotch.markdown.bullet")

    private let storage: NSTextStorage
    private let layout: NSLayoutManager

    /// The paragraph or paragraphs holding the selection. Markers here stay visible.
    private(set) var activeRange = NSRange(location: 0, length: 0)

    init(storage: NSTextStorage, layout: NSLayoutManager) {
        self.storage = storage
        self.layout = layout
        super.init()
        storage.delegate = self
        layout.delegate = self
    }

    // MARK: Storage delegate

    /// Restyles the paragraphs an edit touched. Attributes only: the delegate contract
    /// forbids changing characters here, and the styler never needs to.
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        let paragraphs = (textStorage.string as NSString).paragraphRange(for: editedRange)
        restyle(paragraphs)
    }

    /// Restyles everything. Used when a note is loaded into the view.
    func restyleAll() {
        storage.beginEditing()
        restyle(NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }

    // MARK: Active line

    /// Moves the visible-syntax window to the paragraphs under `selection`, regenerating
    /// glyphs for whatever left it and whatever entered it.
    func updateActive(for selection: NSRange) {
        let next = (storage.string as NSString).paragraphRange(for: selection)
        guard next != activeRange else { return }
        let previous = activeRange
        activeRange = next
        for range in [previous, next] where range.length > 0 {
            let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
            guard clamped.length > 0 else { continue }
            layout.invalidateGlyphs(forCharacterRange: clamped, changeInLength: 0, actualCharacterRange: nil)
            layout.invalidateLayout(forCharacterRange: clamped, actualCharacterRange: nil)
        }
    }

    // MARK: Layout manager delegate

    /// Where the preview happens. Marker glyphs outside the active paragraph become null
    /// glyphs, and a list dash becomes a bullet, without the characters changing.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        do {
            let count = glyphRange.length
            guard count > 0, let attributed = layoutManager.textStorage else { return 0 }
            let active = activeRange

            var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count))
            var newProperties = Array(UnsafeBufferPointer(start: properties, count: count))
            var touched = false

            // Attribute runs are long compared with glyph runs, so one lookup usually
            // covers many glyphs.
            var run = NSRange(location: NSNotFound, length: 0)
            var isMarker = false
            var isBullet = false
            for glyph in 0..<count {
                let charIndex = characterIndexes[glyph]
                guard !NSLocationInRange(charIndex, active) else { continue }
                if !NSLocationInRange(charIndex, run) {
                    let attributes = attributed.attributes(at: charIndex, effectiveRange: &run)
                    isMarker = attributes[Self.marker] != nil
                    isBullet = attributes[Self.bullet] != nil
                }
                if isMarker {
                    newProperties[glyph] = .null
                    touched = true
                } else if isBullet, let bullet = Self.bulletGlyph(in: font) {
                    newGlyphs[glyph] = bullet
                    touched = true
                }
            }

            guard touched else { return 0 }
            layoutManager.setGlyphs(
                newGlyphs, properties: newProperties, characterIndexes: characterIndexes,
                font: font, forGlyphRange: glyphRange
            )
            return count
        }
    }

    private static func bulletGlyph(in font: NSFont) -> CGGlyph? {
        var characters: [UniChar] = [0x2022]
        var glyphs: [CGGlyph] = [0]
        let found = CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 1)
        return found && glyphs[0] != 0 ? glyphs[0] : nil
    }

    // MARK: Styling

    private func restyle(_ range: NSRange) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        let paragraphs = text.paragraphRange(for: range)
        var location = paragraphs.location
        let end = paragraphs.location + paragraphs.length
        repeat {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            guard paragraph.length > 0 else { break }
            style(paragraph, in: text)
            location = paragraph.location + paragraph.length
        } while location < end
    }

    private func style(_ range: NSRange, in text: NSString) {
        guard range.length > 0 else { return }
        let line = text.substring(with: range)
        storage.setAttributes(Self.base, range: range)

        let block = BlockParse(line: line)
        var inlineStart = 0

        if let heading = block.heading {
            storage.addAttribute(.font, value: Style.Hosted.heading(heading.level), range: range)
            mark(heading.markerRange, offset: range.location)
            inlineStart = heading.markerRange.upperBound
        } else if let list = block.list {
            let style = NSMutableParagraphStyle()
            style.headIndent = list.indentWidth
            style.firstLineHeadIndent = 0
            storage.addAttribute(.paragraphStyle, value: style, range: range)
            let markerRange = NSRange(location: range.location + list.markerRange.location, length: list.markerRange.length)
            storage.addAttribute(.foregroundColor, value: Style.Hosted.notesAccent, range: markerRange)
            if list.isBullet {
                storage.addAttribute(Self.bullet, value: true, range: markerRange)
            }
            inlineStart = list.markerRange.upperBound
        } else if let quote = block.quote {
            storage.addAttribute(.foregroundColor, value: Style.Hosted.inkMuted, range: range)
            storage.addAttribute(.font, value: Self.italic(Style.Hosted.body), range: range)
            mark(quote.markerRange, offset: range.location)
            inlineStart = quote.markerRange.upperBound
        }

        let inline = InlineParse(line: line, from: inlineStart)
        for span in inline.spans {
            let absolute = NSRange(location: range.location + span.range.location, length: span.range.length)
            var font = storage.attribute(.font, at: absolute.location, effectiveRange: nil) as? NSFont ?? Style.Hosted.body
            switch span.kind {
            case .bold:
                font = Self.bold(font)
            case .italic:
                font = Self.italic(font)
            case .boldItalic:
                font = Self.italic(Self.bold(font))
            case .strike:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: absolute)
                storage.addAttribute(.foregroundColor, value: Style.Hosted.inkMuted, range: absolute)
            case .code:
                font = Style.Hosted.code
                storage.addAttribute(.backgroundColor, value: Style.Hosted.fill, range: absolute)
            }
            storage.addAttribute(.font, value: font, range: absolute)
        }
        for marker in inline.markers {
            mark(marker, offset: range.location)
        }
    }

    private func mark(_ local: NSRange, offset: Int) {
        let absolute = NSRange(location: offset + local.location, length: local.length)
        storage.addAttribute(Self.marker, value: true, range: absolute)
        storage.addAttribute(.foregroundColor, value: Style.Hosted.inkFaint, range: absolute)
    }

    private static let base: [NSAttributedString.Key: Any] = [
        .font: Style.Hosted.body,
        .foregroundColor: Style.Hosted.ink,
        .paragraphStyle: NSParagraphStyle.default,
    ]

    private static func bold(_ font: NSFont) -> NSFont {
        let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.bold))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    private static func italic(_ font: NSFont) -> NSFont {
        let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.italic))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}

// MARK: - Block syntax

/// What a line is: heading, list item, quote, or plain. Ranges are UTF-16 offsets into
/// the line.
@MainActor
struct BlockParse {
    struct Heading {
        let level: Int
        let markerRange: NSRange
    }

    struct List {
        /// The dash, asterisk, plus or number, without the trailing space.
        let markerRange: NSRange
        let isBullet: Bool
        /// Where the item's text starts, so wrapped lines align under it.
        let indentWidth: CGFloat
        /// The marker and its spacing, exactly as typed, for continuing the list.
        let prefix: String
        /// True when there is nothing after the marker.
        let isEmpty: Bool
        /// The number, for ordered lists.
        let number: Int?
    }

    struct Quote {
        let markerRange: NSRange
    }

    let heading: Heading?
    let list: List?
    let quote: Quote?

    private static let headingPattern = try! NSRegularExpression(pattern: #"^(#{1,3})[ \t]+"#)
    private static let bulletPattern = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+])[ \t]+"#)
    private static let orderedPattern = try! NSRegularExpression(pattern: #"^([ \t]*)(\d{1,3})[.)][ \t]+"#)
    private static let quotePattern = try! NSRegularExpression(pattern: #"^>[ \t]?"#)

    init(line: String) {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)

        if let match = Self.headingPattern.firstMatch(in: line, range: whole) {
            heading = Heading(level: match.range(at: 1).length, markerRange: match.range)
            list = nil
            quote = nil
            return
        }
        if let match = Self.bulletPattern.firstMatch(in: line, range: whole) {
            let rest = ns.substring(from: match.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
            list = List(
                markerRange: match.range(at: 2),
                isBullet: true,
                indentWidth: Self.width(of: ns.substring(with: match.range)),
                prefix: ns.substring(with: match.range),
                isEmpty: rest.isEmpty,
                number: nil
            )
            heading = nil
            quote = nil
            return
        }
        if let match = Self.orderedPattern.firstMatch(in: line, range: whole) {
            let rest = ns.substring(from: match.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
            list = List(
                markerRange: match.range(at: 2),
                isBullet: false,
                indentWidth: Self.width(of: ns.substring(with: match.range)),
                prefix: ns.substring(with: match.range),
                isEmpty: rest.isEmpty,
                number: Int(ns.substring(with: match.range(at: 2)))
            )
            heading = nil
            quote = nil
            return
        }
        if let match = Self.quotePattern.firstMatch(in: line, range: whole) {
            quote = Quote(markerRange: match.range)
            heading = nil
            list = nil
            return
        }
        heading = nil
        list = nil
        quote = nil
    }

    /// The hanging indent for a list prefix: the width of a bullet plus its spacing,
    /// measured in the body font so wrapped text lines up under the item's first word.
    private static func width(of prefix: String) -> CGFloat {
        let sample = String(repeating: "\u{2022}", count: max(prefix.count - 1, 1)) + " "
        return (sample as NSString).size(withAttributes: [.font: Style.Hosted.body]).width
    }
}

// MARK: - Inline syntax

/// Emphasis, strikethrough and code inside a line. Ranges are UTF-16 offsets into the
/// line. Code wins: nothing inside a code span is emphasis.
@MainActor
struct InlineParse {
    enum Kind {
        case bold, italic, boldItalic, strike, code
    }

    struct Span {
        let kind: Kind
        /// The text between the markers.
        let range: NSRange
    }

    private(set) var spans: [Span] = []
    private(set) var markers: [NSRange] = []

    private struct Rule {
        let kind: Kind
        let pattern: NSRegularExpression
        let markerLength: Int
    }

    private static let rules: [Rule] = [
        Rule(kind: .code, pattern: try! NSRegularExpression(pattern: #"`([^`\n]+)`"#), markerLength: 1),
        Rule(kind: .boldItalic, pattern: try! NSRegularExpression(pattern: #"\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*"#), markerLength: 3),
        Rule(kind: .bold, pattern: try! NSRegularExpression(pattern: #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#), markerLength: 2),
        Rule(kind: .bold, pattern: try! NSRegularExpression(pattern: #"__(?=\S)(.+?)(?<=\S)__"#), markerLength: 2),
        Rule(kind: .strike, pattern: try! NSRegularExpression(pattern: #"~~(?=\S)(.+?)(?<=\S)~~"#), markerLength: 2),
        Rule(kind: .italic, pattern: try! NSRegularExpression(pattern: #"(?<![*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)"#), markerLength: 1),
        Rule(kind: .italic, pattern: try! NSRegularExpression(pattern: #"(?<![_\w])_(?=[^\s_])(.+?)(?<=[^\s_])_(?!\w)"#), markerLength: 1),
    ]

    init(line: String, from start: Int) {
        let ns = line as NSString
        guard start < ns.length else { return }
        let searchRange = NSRange(location: start, length: ns.length - start)
        var claimed: [NSRange] = []

        for rule in Self.rules {
            for match in rule.pattern.matches(in: line, range: searchRange) {
                let whole = match.range
                guard !claimed.contains(where: { NSIntersectionRange($0, whole).length > 0 }) else { continue }
                claimed.append(whole)
                let inner = match.range(at: 1)
                spans.append(Span(kind: rule.kind, range: inner))
                markers.append(NSRange(location: whole.location, length: rule.markerLength))
                markers.append(NSRange(location: whole.location + whole.length - rule.markerLength, length: rule.markerLength))
            }
        }
    }
}

// MARK: - Plain text

extension BlockParse {
    /// The markdown with its syntax removed, for titles and card previews. Approximate
    /// on purpose: it strips what the styler would hide, and nothing more.
    private static let stripPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"^(#{1,3})[ \t]+"#),
        try! NSRegularExpression(pattern: #"^[ \t]*[-*+][ \t]+(\[[ xX]\][ \t]+)?"#),
        try! NSRegularExpression(pattern: #"^[ \t]*\d{1,3}[.)][ \t]+"#),
        try! NSRegularExpression(pattern: #"^>[ \t]?"#),
        try! NSRegularExpression(pattern: #"(\*{1,3}|_{1,2}|~~|`)(?=\S)(.+?)(?<=\S)\1"#),
    ]

    static func plainText(of line: String) -> String {
        var text = line
        for pattern in stripPatterns {
            let range = NSRange(location: 0, length: (text as NSString).length)
            let template = pattern.numberOfCaptureGroups >= 2 ? "$2" : ""
            text = pattern.stringByReplacingMatches(in: text, range: range, withTemplate: template)
        }
        return text
    }
}
