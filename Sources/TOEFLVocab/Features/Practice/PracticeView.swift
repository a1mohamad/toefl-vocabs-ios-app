import SwiftUI

// MARK: - Container

/// Builds the view model from the environment. Split out because `@StateObject`
/// has to be constructed in `init`, which cannot see `@EnvironmentObject`.
///
/// The `.id(configuration.id)` is what makes "next section" work: changing the
/// configuration gives the child a new identity, so SwiftUI builds a fresh view
/// model instead of reusing the finished one.
struct PracticeContainerView: View {

    let configuration: PracticeConfiguration

    @EnvironmentObject private var content: ContentProvider
    @EnvironmentObject private var progress: ProgressStore

    var body: some View {
        PracticeView(
            configuration: configuration,
            catalog: content.catalog,
            progress: progress
        )
        .id(configuration.id)
    }
}

// MARK: - Practice

struct PracticeView: View {

    @StateObject private var viewModel: PracticeViewModel

    @EnvironmentObject private var speech: PronunciationService
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var router: Router
    @Environment(\.strings) private var strings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(configuration: PracticeConfiguration, catalog: VocabCatalog, progress: ProgressStore) {
        _viewModel = StateObject(
            wrappedValue: PracticeViewModel(
                configuration: configuration,
                catalog: catalog,
                progress: progress
            )
        )
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            if viewModel.phase == .finished {
                SessionSummaryView(viewModel: viewModel)
            } else {
                sessionBody
            }
        }
        .onAppear {
            #if DEBUG
            ScreenshotHarness.advance(viewModel)
            #endif
            autoSpeakIfEnabled()
        }
        .onChange(of: viewModel.index) { _ in autoSpeakIfEnabled() }
        .onChange(of: viewModel.dismissRequested) { requested in
            if requested {
                speech.stop()
                router.endPractice()
            }
        }
        .alert(strings[.practiceQuitTitle], isPresented: $viewModel.showQuitConfirmation) {
            Button(strings[.commonQuit], role: .destructive) { viewModel.confirmQuit() }
            Button(strings[.commonKeepGoing], role: .cancel) {}
        } message: {
            Text(strings[.practiceQuitMessage])
        }
    }

    // MARK: Layout

    private var sessionBody: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        wordCard
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.vertical, 18)
                    // Centres the card in the available space, but still
                    // scrolls once a long definition at a large Dynamic Type
                    // size makes it taller than the screen.
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
            }
            controls
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 12)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                quitButton
                titleBlock
                Spacer(minLength: 0)
                positionLabel
            }
            MeterBar(progress: viewModel.progressFraction, gradient: viewModel.theme.gradient, height: 5)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Palette.surface)
    }

    /// Always reachable, always in the same place — a practice session the user
    /// cannot leave is a trap.
    private var quitButton: some View {
        Button {
            viewModel.requestQuit()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: Metrics.minimumTapTarget, height: Metrics.minimumTapTarget)
                .background(Palette.surfaceSunken)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(strings[.commonQuit])
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(headerTitleText)
                .font(AppFont.caption)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            if let subtitleKey = viewModel.headerSubtitleKey {
                Text(strings[subtitleKey])
                    .font(AppFont.badge)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var positionLabel: some View {
        let position = viewModel.positionText
        return Text(strings.format(.practiceProgress, position.current, position.total))
            .font(AppFont.badge.monospacedDigit())
            .foregroundStyle(Palette.textSecondary)
    }

    private var headerTitleText: String {
        if let title = viewModel.headerTitle { return title }
        if let key = viewModel.headerTitleKey { return strings[key] }
        return ""
    }

    // MARK: Word card

    private var wordCard: some View {
        VStack(spacing: 20) {
            if let item = viewModel.currentItem {
                termBlock(item)
                PronunciationControl(
                    term: item.term,
                    accent: settings.settings.accent,
                    isSpeaking: speech.isSpeaking,
                    gradient: viewModel.theme.gradient,
                    onSpeak: speakCurrent,
                    onCycleAccent: cycleAccent
                )
                checklistBlock
                meaningBlock(item)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.separator, lineWidth: 1)
        )
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: viewModel.phase)
    }

    private func termBlock(_ item: VocabItem) -> some View {
        VStack(spacing: 8) {
            Text(item.term)
                .font(AppFont.word)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            tallyRow
        }
    }

    /// Right/wrong history for this word. Shown in the drill, where knowing you
    /// have missed something five times is the motivation to slow down.
    @ViewBuilder
    private var tallyRow: some View {
        let tallies = viewModel.currentTallies
        if viewModel.configuration.mode == .extra, tallies.correct + tallies.incorrect > 0 {
            HStack(spacing: 8) {
                Chip(
                    text: strings.format(.practiceCorrectTally, tallies.correct),
                    symbol: "checkmark",
                    tint: Palette.success,
                    background: Palette.successSoft
                )
                Chip(
                    text: strings.format(.practiceWrongTally, tallies.incorrect),
                    symbol: "xmark",
                    tint: Palette.danger,
                    background: Palette.dangerSoft
                )
            }
        } else if viewModel.currentStats == nil {
            Chip(text: strings[.practiceNewWord], symbol: "sparkle")
        }
    }

    private var checklistBlock: some View {
        VStack(spacing: 7) {
            ChecklistView(display: viewModel.checklist)
            Text(checklistCaption)
                .font(AppFont.badge)
                .foregroundStyle(viewModel.checklist.isRecap ? Palette.accent : Palette.textTertiary)
        }
    }

    private var checklistCaption: String {
        viewModel.checklist.isRecap
            ? strings[.practiceLastFive]
            : strings[.practiceThisCycle]
    }

    @ViewBuilder
    private func meaningBlock(_ item: VocabItem) -> some View {
        if let wasCorrect = viewModel.revealedAnswer {
            VStack(spacing: 12) {
                Divider().overlay(Palette.separator)

                HStack(spacing: 6) {
                    Image(systemName: wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(wasCorrect ? Palette.success : Palette.danger)
                    Text(strings[wasCorrect ? .practiceKnewIt : .practiceDidntKnow])
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }

                VStack(spacing: 6) {
                    Text(strings[.practiceMeaning].uppercased())
                        .font(AppFont.badge)
                        .tracking(0.6)
                        .foregroundStyle(Palette.textTertiary)
                    Text(item.definition)
                        .font(AppFont.definition)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let tip = item.usageTip {
                    UsageTipView(tip: tip)
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if viewModel.revealedAnswer == nil {
            HStack(spacing: 12) {
                answerButton(correct: false)
                answerButton(correct: true)
            }
        } else {
            Button {
                viewModel.advance()
            } label: {
                Text(viewModel.isOnLastItem ? strings[.practiceFinish] : strings[.practiceNextWord])
            }
            .buttonStyle(PrimaryButtonStyle(gradient: viewModel.theme.gradient))
        }
    }

    private func answerButton(correct: Bool) -> some View {
        Button {
            submit(correct: correct)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: correct ? "checkmark" : "xmark")
                    .font(.system(size: 17, weight: .bold))
                Text(strings[correct ? .practiceKnewIt : .practiceDidntKnow])
            }
        }
        .buttonStyle(
            AnswerButtonStyle(
                tint: correct ? Palette.success : Palette.danger,
                soft: correct ? Palette.successSoft : Palette.dangerSoft
            )
        )
    }

    // MARK: Actions

    private func submit(correct: Bool) {
        viewModel.answer(correct: correct)
        Haptics.answer(correct: correct, enabled: settings.settings.haptics)
    }

    private func speakCurrent() {
        guard let item = viewModel.currentItem else { return }
        speech.speak(
            item.term,
            accent: settings.settings.accent,
            rate: settings.settings.speechRate
        )
    }

    private func cycleAccent() {
        let accents = SpeechAccent.allCases
        if let current = accents.firstIndex(of: settings.settings.accent) {
            settings.settings.accent = accents[(current + 1) % accents.count]
        }
        Haptics.tap(enabled: settings.settings.haptics)
        speakCurrent()
    }

    private func autoSpeakIfEnabled() {
        guard settings.settings.autoSpeak, viewModel.phase == .question else { return }
        speakCurrent()
    }
}
