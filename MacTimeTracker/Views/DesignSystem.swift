import SwiftUI
import AppKit
import CoreText

/// Force-hides the scrollers of the enclosing `NSScrollView`. Needed because
/// `.scrollIndicators(.hidden)` does NOT override the system "Show scroll bars:
/// Always" setting, which otherwise keeps legacy scrollers permanently visible.
struct ScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        apply(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(from: nsView)
    }

    private func apply(from view: NSView) {
        // Retry across a couple of runloop turns until the scroll view exists.
        for delay in [0.0, 0.05, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let scrollView = view.enclosingScrollView else { return }
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.verticalScroller?.isHidden = true
                scrollView.horizontalScroller?.isHidden = true
            }
        }
    }
}

extension View {
    /// Hide scrollers of the enclosing scroll view (system-setting-proof).
    func hideScrollers() -> some View {
        background(ScrollerHider().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}

/// Shared visual constants so related shapes stay in sync (e.g. a filled button
/// whose corners should match the card it sits in).
enum AppTheme {
    /// Corner radius of `cardSurface`. Reused by `FilledButtonStyle` so a
    /// prominent button's roundness matches the enclosing card's outer border.
    static let cardCornerRadius: CGFloat = 14

    /// Family name of the big timer numerals — SHIFTBRAIN's licensed Norms
    /// variable face (installed in ~/Library/Fonts). Falls back to the rounded
    /// system font automatically if the family isn't available.
    static let timerFontName = "SHIFTBRAIN Norms Variable"
    /// Value of the font's width (`wdth`) variation axis for the timer. The face
    /// varies width only (75 Narrow … 100 Regular … 200 Super-Wide); 125 sits
    /// just wider than Regular.
    static let timerWidth: CGFloat = 125
}

extension Font {
    /// The timer readout face at `size` (SHIFTBRAIN Norms Variable at the
    /// `AppTheme.timerWidth` width axis). Falls back to the rounded system font
    /// when the family isn't installed.
    static func timer(size: CGFloat) -> Font {
        guard let font = TimerMetrics.nsFont(size: size) else {
            return .system(size: size, weight: .semibold, design: .rounded)
        }
        return Font(font as CTFont)
    }
}

/// Text layout helpers.
enum TextMetrics {
    /// The whitespace between a text view's line-box top and the cap height of
    /// the system font at `size`/`weight`. Large numerals (like the timer) sit
    /// well below their line-box top; trimming this with a negative top padding
    /// lets them optically hug whatever is above them (e.g. a divider), so the
    /// space above and below reads as equal.
    static func capInset(size: CGFloat, fontName: String? = nil, weight: NSFont.Weight = .semibold) -> CGFloat {
        let font: NSFont
        if let fontName, let custom = NSFont(name: fontName, size: size) {
            font = custom
        } else {
            font = NSFont.systemFont(ofSize: size, weight: weight)
        }
        return max(0, font.ascender - font.capHeight)
    }
}

/// Metrics for the timer readout (monospaced fixed-slot layout).
enum TimerMetrics {
    /// Letter spacing (tracking) for the numerals, as a fraction of the size.
    /// Negative = tighter. Applied by shrinking each digit slot.
    static let tracking: CGFloat = -0.05
    /// Constant gap on each side of the colon, as a fraction of the size.
    static let colonGap: CGFloat = 0.04

    /// The timer face at `size` with its width axis (`wdth`) applied.
    static func nsFont(size: CGFloat) -> NSFont? {
        guard let base = NSFont(name: AppTheme.timerFontName, size: size) else { return nil }
        let key = NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        return NSFont(descriptor: base.fontDescriptor.addingAttributes([key: [0x77647468: AppTheme.timerWidth]]), size: size) ?? base
    }
    private static func advance(_ s: String, size: CGFloat) -> CGFloat {
        guard let font = nsFont(size: size) else { return size * 0.6 }
        return NSAttributedString(string: s, attributes: [.font: font]).size().width
    }

    /// Widest single-digit (0–9) advance at `size`.
    private static func maxDigitAdvance(size: CGFloat) -> CGFloat {
        var widest: CGFloat = 0
        for digit in "0123456789" { widest = max(widest, advance(String(digit), size: size)) }
        return widest
    }
    /// Fixed width of a `digits`-long numeral block: the widest digits plus the
    /// (negative, −5%) letter spacing between them. Framing a segment to this
    /// keeps the segment — and therefore the colon — from moving as digits change.
    static func blockWidth(digits: Int, size: CGFloat) -> CGFloat {
        guard digits > 0 else { return 0 }
        let innerSpacing = CGFloat(digits - 1) * size * tracking
        return max(1, ceil(maxDigitAdvance(size: size) * CGFloat(digits) + innerSpacing))
    }
    static func colonWidth(size: CGFloat) -> CGFloat { ceil(advance(":", size: size)) }
    static func gap(size: CGFloat) -> CGFloat { size * colonGap }

    /// SwiftUI y-offset (negative = up) that raises the ":" so its ink centre
    /// sits on the digits' cap-height centre. This is the visual result of the
    /// OpenType `case` feature (Case-Sensitive Forms), which SwiftUI's Text
    /// renderer won't apply from a font descriptor — so we place it by metrics.
    static func colonYOffset(size: CGFloat) -> CGFloat {
        guard let font = nsFont(size: size) else { return 0 }
        let ct = font as CTFont
        var codepoint: UniChar = 58   // ':'
        var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(ct, &codepoint, &glyph, 1) else { return 0 }
        var bounds = CGRect.zero
        var g = glyph
        CTFontGetBoundingRectsForGlyphs(ct, .horizontal, &g, &bounds, 1)
        return bounds.midY - CTFontGetCapHeight(ct) / 2   // < 0 → move up
    }

    /// Total laid-out width of `text` at `size` — matches `RollingTime` (fixed
    /// digit blocks split by the colon), so callers can size the font to fit.
    static func width(text: String, size: CGFloat) -> CGFloat {
        let g = gap(size: size), c = colonWidth(size: size)
        var total: CGFloat = 0
        for (index, segment) in text.split(separator: ":", omittingEmptySubsequences: false).enumerated() {
            if index > 0 { total += c + 2 * g }
            total += blockWidth(digits: segment.count, size: size)
        }
        return total
    }

    /// Largest size (capped at `maxSize`) whose laid-out `text` fits `available`.
    static func fittingSize(text: String, available: CGFloat, maxSize: CGFloat) -> CGFloat {
        let ref: CGFloat = 100
        let widthAtRef = max(width(text: text, size: ref), 1)
        return min(maxSize, max(1, available) * ref / widthAtRef)
    }
}

/// A full-width filled (accent) button whose corner radius we control, so it can
/// match the enclosing card's outer border radius. Works on macOS 13+, unlike
/// `.buttonBorderShape(.roundedRectangle(radius:))` (macOS 14+).
struct FilledButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = AppTheme.cardCornerRadius
    var tint: Color = .accentColor
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Shared visual language for a clean, modern macOS look (cards, tinted symbol
/// badges, section labels).
extension View {
    /// Standard card surface: rounded, subtle fill + hairline border.
    /// 16 pt inset follows the macOS HIG content-margin rhythm.
    func cardSurface(padding: CGFloat = 16, cornerRadius: CGFloat = AppTheme.cardCornerRadius) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }

    /// Primary full-width action button. On macOS 26+ it uses **Liquid Glass**
    /// (prominent, blue-tinted) whose corners match the enclosing card; on
    /// earlier systems it falls back to the filled accent `FilledButtonStyle`.
    /// Apply to a `Button` whose label is `.frame(maxWidth: .infinity)`.
    @ViewBuilder
    func cardActionButton() -> some View {
        if #available(macOS 26.0, *) {
            self
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.cardCornerRadius))
                .controlSize(.large)
                .tint(.blue)
        } else {
            self.buttonStyle(FilledButtonStyle())
        }
    }

    /// A compact, rounded **clear** Liquid Glass button (capsule, untinted) on
    /// macOS 26+; a borderless button on earlier systems. For secondary actions
    /// like "Sync".
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderless)
        }
    }
}

/// A rounded, tinted SF Symbol badge — like a System Settings row icon.
struct SymbolBadge: View {
    let system: String
    var tint: Color = .blue
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(tint)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: system)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// A small uppercase section label.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.4)
    }
}

/// Blur + fade + vertical offset — the building block of the rolling timer.
struct RollModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let dy: CGFloat
    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .offset(y: dy)
    }
}

extension AnyTransition {
    /// Fade + blur: content blurs and fades as it appears, and again as it
    /// disappears (symmetric in/out).
    static var blurFade: AnyTransition {
        .modifier(
            active: RollModifier(blur: 8, opacity: 0, dy: 0),
            identity: RollModifier(blur: 0, opacity: 1, dy: 0)
        )
    }

    /// Odometer-style roll: the old value blurs + fades while drifting up; the
    /// new value rises from below, sharpening and fading in.
    static var timerRoll: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: RollModifier(blur: 6, opacity: 0, dy: 14),
                identity: RollModifier(blur: 0, opacity: 1, dy: 0)
            ),
            removal: .modifier(
                active: RollModifier(blur: 6, opacity: 0, dy: -14),
                identity: RollModifier(blur: 0, opacity: 1, dy: 0)
            )
        )
    }
}

/// A time readout laid out as fixed-width numeral blocks split by the colon:
/// the minutes block is right-aligned toward the colon, the seconds block is
/// left-aligned, and the ":" is cap-height-centred (OpenType `case`). Each block
/// is framed to its widest possible width, so the colon stays put and the whole
/// readout keeps a constant width as the digits change. Digits carry −5% letter
/// spacing and roll on change (numericText).
struct RollingTime: View {
    let text: String
    /// Point size of the numerals (the `SHIFTBRAIN Norms Variable` timer face).
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        let segments = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let digitFont = Font.timer(size: size)
        let gap = TimerMetrics.gap(size: size)
        let kerning = size * TimerMetrics.tracking      // −5% letter spacing
        let colonOffset = TimerMetrics.colonYOffset(size: size)
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Text(":")
                        .font(digitFont)
                        .foregroundStyle(color)
                        .fixedSize()
                        .offset(y: colonOffset)         // raise to cap-height centre
                        .padding(.horizontal, gap)      // constant gap; colon never moves
                }
                Text(segment)
                    .font(digitFont)
                    .kerning(kerning)
                    .foregroundStyle(color)
                    .fixedSize()
                    .frame(width: TimerMetrics.blockWidth(digits: segment.count, size: size),
                           alignment: blockAlignment(index: index, count: segments.count))
                    .contentTransition(.numericText())
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: text)
    }

    /// First block (minutes) hugs the colon from the left → trailing; the last
    /// block (seconds) hugs it from the right → leading; any middle block (the
    /// minutes of H:MM:SS) is centred.
    private func blockAlignment(index: Int, count: Int) -> Alignment {
        if index == 0 { return .trailing }
        if index == count - 1 { return .leading }
        return .center
    }
}

/// Keeps a large hit area but only reports the press state (via a binding), so
/// the caller can animate just part of the label — e.g. the icon, not the text.
struct PressReportingButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { pressed in
                isPressed = pressed
            }
    }
}

/// A round icon control used by the timer (start / pause / stop).
struct CircleControl: View {
    let system: String
    let tint: Color
    let label: String
    var enabled: Bool = true
    var filledWhenEnabled: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        // The whole stack (icon + label + surrounding padding) is the button, so
        // the tap target is much larger than the 50 pt disc. Only the icon
        // animates on press; the label stays put.
        Button(action: action) {
            VStack(spacing: 5) {
                circle
                    .scaleEffect(isPressed ? 0.86 : 1)
                    .opacity(isPressed ? 0.85 : 1)
                    .animation(.spring(response: 0.28, dampingFraction: 0.55), value: isPressed)
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(enabled ? .secondary : Color.secondary.opacity(0.5))
            }
            .frame(minWidth: 56)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .contentShape(Rectangle())   // entire padded area is clickable
        }
        .buttonStyle(PressReportingButtonStyle(isPressed: $isPressed))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// The circular control surface: **Liquid Glass** on macOS 26+ (tinted +
    /// interactive for the primary action), a flat tinted disc on earlier OSes.
    @ViewBuilder
    private var circle: some View {
        if #available(macOS 26.0, *) {
            Image(systemName: system)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 50, height: 50)
                .glassEffect(glass, in: Circle())
        } else {
            ZStack {
                Circle().fill(background)
                Image(systemName: system)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(foreground)
            }
            .frame(width: 50, height: 50)
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        guard enabled else { return .regular }
        // Primary action gets a solid tinted glass + white glyph; the secondary
        // actions get clear glass with a tinted glyph so contrast stays high.
        return filledWhenEnabled
            ? .regular.tint(tint).interactive()
            : .regular.interactive()
    }

    private var background: Color {
        guard enabled else { return Color.primary.opacity(0.06) }
        return filledWhenEnabled ? tint : tint.opacity(0.16)
    }

    private var foreground: Color {
        guard enabled else { return Color.secondary.opacity(0.5) }
        return filledWhenEnabled ? .white : tint
    }
}
