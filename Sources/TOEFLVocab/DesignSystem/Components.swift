import SwiftUI

// MARK: - Checklist

/// The five-box accuracy strip under a word.
///
/// Correct/incorrect is carried by an icon as well as a colour, so it still
/// reads for a red-green colourblind user, and the whole strip collapses to one
/// VoiceOver element with a spoken summary instead of five anonymous shapes.
struct ChecklistView: View {
    let display: ChecklistDisplay
    var compact: Bool = false

    @Environment(\.strings) private var strings

    private var boxSize: CGFloat { compact ? 13 : 30 }
    private var spacing: CGFloat { compact ? 4 : 9 }
    private var radius: CGFloat { compact ? 4 : 9 }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<WordStats.cycleLength, id: \.self) { index in
                box(at: index)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            strings.format(
                .practiceChecklistLabel,
                display.filled,
                display.capacity,
                display.correctCount
            )
        )
    }

    @ViewBuilder
    private func box(at index: Int) -> some View {
        let mark: Bool? = index < display.marks.count ? display.marks[index] : nil

        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fillColor(for: mark))
            .frame(width: boxSize, height: boxSize)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(strokeColor(for: mark), lineWidth: mark == nil ? 1.5 : 0)
            )
            .overlay(glyph(for: mark))
            .opacity(display.isRecap ? 0.55 : 1)
    }

    private func fillColor(for mark: Bool?) -> Color {
        guard let mark else { return Palette.surfaceSunken }
        return mark ? Palette.success : Palette.danger
    }

    private func strokeColor(for mark: Bool?) -> Color {
        mark == nil ? Palette.separator : .clear
    }

    @ViewBuilder
    private func glyph(for mark: Bool?) -> some View {
        if let mark, !compact {
            Image(systemName: mark ? "checkmark" : "xmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10
    var gradient: LinearGradient = BookTheme.indigo.gradient
    var trackColor: Color = Palette.surfaceSunken

    private var clamped: Double { progress.clamped(to: 0...1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, clamped))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// Ring with a percentage in the middle.
struct ProgressRingLabelled: View {
    let progress: Double
    let caption: String
    var gradient: LinearGradient = BookTheme.indigo.gradient
    var diameter: CGFloat = 108

    var body: some View {
        ZStack {
            ProgressRing(progress: progress, lineWidth: 11, gradient: gradient)
            VStack(spacing: 0) {
                Text("\(Int((progress.clamped(to: 0...1) * 100).rounded()))%")
                    .font(AppFont.metricValueSmall)
                    .foregroundStyle(Palette.textPrimary)
                Text(caption)
                    .font(AppFont.badge)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(Int((progress.clamped(to: 0...1) * 100).rounded())) percent")
    }
}

// MARK: - Meter

/// Horizontal progress bar used in book and section rows.
struct MeterBar: View {
    let progress: Double
    var gradient: LinearGradient = BookTheme.indigo.gradient
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.surfaceSunken)
                Capsule()
                    .fill(gradient)
                    .frame(width: max(0, proxy.size.width * progress.clamped(to: 0...1)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Tiles and chips

struct StatTile: View {
    let value: String
    let label: String
    var symbol: String? = nil
    var tint: Color = Palette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(AppFont.badge)
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(value)
                .font(AppFont.metricValueSmall)
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct Chip: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = Palette.textSecondary
    var background: Color = Palette.surfaceSunken

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(AppFont.badge)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionTitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            // `.tracking` is applied while this is still a `Text`; once
            // `.foregroundStyle` erases it to `some View` the Text-returning
            // overload is gone.
            Text(title.uppercased())
                .font(AppFont.sectionHeader)
                .tracking(0.6)
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: 8)
            if let action, let actionTitle {
                Button(actionTitle, action: action)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.accent)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Button styles

struct PrimaryButtonStyle: ButtonStyle {
    var gradient: LinearGradient = BookTheme.indigo.gradient

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.cardTitle)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.cardTitle)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Palette.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(Palette.separator, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// The Right / Wrong pair on the practice screen. Large, high-contrast, and
/// icon-led so the two are never distinguished by colour alone.
struct AnswerButtonStyle: ButtonStyle {
    let tint: Color
    let soft: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.cardTitle)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(soft)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Pronunciation control

/// Speaker button plus the accent switch, kept together because they are one
/// idea to the user. Present on every word and never disappears when the
/// meaning is revealed.
struct PronunciationControl: View {
    let term: String
    let accent: SpeechAccent
    let isSpeaking: Bool
    let gradient: LinearGradient
    let onSpeak: () -> Void
    let onCycleAccent: () -> Void

    @Environment(\.strings) private var strings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            speakButton
            accentButton
        }
    }

    private var speakButton: some View {
        Button(action: onSpeak) {
            HStack(spacing: 9) {
                Image(systemName: isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text(strings[.practiceTapToHear])
                    .font(AppFont.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: Metrics.minimumTapTarget + 6)
            .background(gradient)
            .clipShape(Capsule())
            .scaleEffect(isSpeaking && !reduceMotion ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSpeaking)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(strings.format(.practiceSpeakLabel, term))
        .accessibilityAddTraits(.startsMediaSession)
    }

    private var accentButton: some View {
        Button(action: onCycleAccent) {
            Text(accent.badge)
                .font(AppFont.badge)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: Metrics.minimumTapTarget, height: Metrics.minimumTapTarget + 6)
                .background(Palette.surfaceRaised)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(strings[.settingsAccent])
        .accessibilityValue(strings[accent.titleKey])
    }
}

// MARK: - Meanings

/// The revealed definition.
///
/// The source data packs every sense of a word onto one `;`-separated line
/// ("keep; keep up; carry on; uphold; support"), which arrives as a single grey
/// paragraph where no individual meaning stands out. So one meaning stays a
/// centred line, exactly as before, and two or more become a numbered list —
/// the list is what tells the learner at a glance that this word has five
/// senses, not one long one.
///
/// Left-aligned inside a centred block on purpose: numbers that do not share a
/// left edge are much harder to scan down.
struct MeaningListView: View {
    let meanings: [String]

    var body: some View {
        if meanings.count <= 1 {
            Text(meanings.first ?? "")
                .font(AppFont.definition)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(meanings.enumerated()), id: \.offset) { index, meaning in
                    row(number: index + 1, meaning: meaning)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func row(number: Int, meaning: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(number).")
                .font(AppFont.definition.monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
            Text(meaning)
                .font(AppFont.definition)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Usage tips

/// The grammar notes that some words carry after the `---` markers in the
/// source data — "followed by 'in'", "usually comes before the noun it
/// describes".
///
/// Deliberately styled as an aside rather than as more definition text: it is
/// advice about *using* the word, and a learner who reads it as part of the
/// meaning is memorising the wrong thing. The lightbulb and the warm tint are
/// the conventional "tip" pairing, and the heading repeats what the icon says
/// so the emoji is never the only cue.
///
/// Several words carry two independent notes, so every note gets its own
/// lightbulb and its own line inside one card — one shared heading, because
/// repeating "TIP" three times is noise rather than structure.
///
/// Inside each note, the `'quoted'` words are coloured: those quotes are the
/// data's way of marking the word the note is really about, and a note with
/// three of them gets three different colours so they do not merge into one
/// long emphasis. See `TipMarkup` and `Palette.tipHighlights`.
struct UsageTipsView: View {
    let tips: [String]

    @Environment(\.strings) private var strings

    var body: some View {
        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(strings[tips.count > 1 ? .practiceTips : .practiceTip].uppercased())
                    .font(AppFont.badge)
                    .tracking(0.6)
                    .foregroundStyle(Palette.warning)

                ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                    row(tip, position: index + 1, total: tips.count)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(Palette.warningSoft)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(Palette.warning.opacity(0.28), lineWidth: 1)
            )
        }
    }

    private func row(_ tip: String, position: Int, total: Int) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(verbatim: "💡")
                .font(.system(size: 16))
                .accessibilityHidden(true)
            Text(highlighted(tip))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(tip, position: position, total: total))
    }

    /// The tip as coloured text. Highlights are bold as well as coloured, so a
    /// colourblind reader still sees which word is marked.
    private func highlighted(_ tip: String) -> AttributedString {
        var result = AttributedString()
        for segment in TipMarkup.segments(of: tip) {
            var run = AttributedString(segment.text)
            if let index = segment.highlightIndex, !Palette.tipHighlights.isEmpty {
                run.foregroundColor = Palette.tipHighlights[index % Palette.tipHighlights.count]
                run.font = AppFont.body.weight(.bold)
            } else {
                run.foregroundColor = Palette.textSecondary
                run.font = AppFont.body
            }
            result.append(run)
        }
        return result
    }

    /// Spoken without the quote marks, and numbered only when there is more
    /// than one note to tell apart.
    private func accessibilityLabel(_ tip: String, position: Int, total: Int) -> String {
        let spoken = TipMarkup.plainText(of: tip)
        guard total > 1 else { return "\(strings[.practiceTip]): \(spoken)" }
        return "\(strings.format(.practiceTipPosition, position, total)): \(spoken)"
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text(title)
                .font(AppFont.title)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AppFont.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, Metrics.screenPadding)
    }
}
