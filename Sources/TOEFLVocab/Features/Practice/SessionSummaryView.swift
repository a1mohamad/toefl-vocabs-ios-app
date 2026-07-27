import SwiftUI

/// End-of-epoch screen: what just happened, and the three ways forward.
///
/// Also the place the two loop rules surface:
/// * finishing a drill pass shows the "full pass complete, starting again from
///   the weakest" notice;
/// * finishing anything at a moment when *every* word in the library has banked
///   a five-answer cycle offers the full restart.
struct SessionSummaryView: View {

    @ObservedObject var viewModel: PracticeViewModel

    @EnvironmentObject private var content: ContentProvider
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.strings) private var strings

    @State private var showRestartConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headline
                statsCard
                if viewModel.configuration.mode == .extra {
                    noticeCard(
                        title: strings[.extraLoopTitle],
                        message: strings[.extraLoopMessage],
                        symbol: "arrow.triangle.2.circlepath"
                    )
                }
                if allWordsCompleted {
                    restartCard
                }
                actions
            }
            .padding(Metrics.screenPadding)
            .padding(.top, 30)
            .padding(.bottom, 30)
        }
        .screenBackground()
        .onAppear {
            Haptics.milestone(enabled: settings.settings.haptics)
        }
        .alert(strings[.restartTitle], isPresented: $showRestartConfirmation) {
            Button(strings[.restartAction]) {
                progress.beginNewRun()
                router.returnToLibrary()
            }
            Button(strings[.restartLater], role: .cancel) {}
        } message: {
            Text(strings[.restartMessage])
        }
    }

    // MARK: Header

    private var headline: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(viewModel.theme.gradient)
                    .frame(width: 76, height: 76)
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            Text(strings[.summaryHeadline])
                .font(AppFont.screenTitle)
                .foregroundStyle(Palette.textPrimary)

            Text(subtitleText)
                .font(AppFont.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var subtitleText: String {
        if viewModel.configuration.mode == .extra {
            return strings[.reportsExtraPractice]
        }
        if let title = viewModel.headerTitle {
            return "\(strings[.summaryTitle]) · \(title)"
        }
        return strings[.summaryTitle]
    }

    // MARK: Stats

    private var statsCard: some View {
        let outcome = viewModel.outcome
        return HStack(spacing: 14) {
            ProgressRingLabelled(
                progress: outcome.accuracy,
                caption: strings[.summaryAccuracy],
                gradient: viewModel.theme.gradient,
                diameter: 100
            )
            VStack(spacing: 10) {
                StatTile(
                    value: "\(outcome.correct)/\(outcome.answered)",
                    label: strings[.summaryAnswered],
                    symbol: "checkmark.circle.fill",
                    tint: Palette.success
                )
                StatTile(
                    value: "\(outcome.cyclesCompleted)",
                    label: strings[.practiceCycleComplete],
                    symbol: "square.grid.3x1.below.line.grid.1x2",
                    tint: viewModel.theme.solid
                )
            }
        }
        .card()
    }

    private func noticeCard(title: String, message: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(viewModel.theme.solid)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFont.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(message)
                    .font(AppFont.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card(background: Palette.surfaceRaised)
        .accessibilityElement(children: .combine)
    }

    private var restartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            noticeCard(
                title: strings[.restartTitle],
                message: strings[.restartMessage],
                symbol: "flag.checkered"
            )
            Button(strings[.restartAction]) {
                showRestartConfirmation = true
            }
            .buttonStyle(SecondaryButtonStyle(tint: viewModel.theme.solid))
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            if let next = nextSection {
                Button(strings[.summaryNextSection]) {
                    startNextSection(book: next.book, section: next.section)
                }
                .buttonStyle(PrimaryButtonStyle(gradient: viewModel.theme.gradient))
            } else if viewModel.configuration.mode == .main {
                Text(strings[.summaryBookComplete])
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 2)
            }

            Button(strings[.summaryPracticeAgain]) {
                viewModel.restart()
            }
            .buttonStyle(SecondaryButtonStyle())

            Button(strings[.summaryBackToMenu]) {
                router.returnToLibrary()
            }
            .buttonStyle(SecondaryButtonStyle(tint: Palette.textSecondary))
        }
    }

    // MARK: Navigation targets

    private var nextSection: (book: Book, section: VocabSection)? {
        guard viewModel.configuration.mode == .main,
              let bookID = viewModel.configuration.bookID,
              let sectionID = viewModel.configuration.sectionID,
              let book = content.catalog.book(bookID),
              let next = book.sectionAfter(sectionID)
        else { return nil }
        return (book, next)
    }

    private func startNextSection(book: Book, section: VocabSection) {
        // Keep the same list where the next section has one — `504/review_1`
        // has no extras, so fall back to whatever it does have.
        let requested = viewModel.configuration.category ?? .main
        let category = section.availableCategories.contains(requested)
            ? requested
            : (section.availableCategories.first ?? .main)

        progress.rememberLocation(
            LastLocation(bookID: book.id, sectionID: section.id, category: category)
        )
        router.replacePractice(
            with: .section(bookID: book.id, sectionID: section.id, category: category)
        )
    }

    private var allWordsCompleted: Bool {
        StatsAggregator.allWordsCompleted(catalog: content.catalog, progress: progress.state)
    }
}
