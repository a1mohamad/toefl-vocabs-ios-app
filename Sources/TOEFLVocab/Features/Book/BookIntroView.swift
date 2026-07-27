import SwiftUI

/// Book preview: what this book is, how far through it you are, and the list of
/// sections. The intro is deliberately shown before the section list rather than
/// buried behind a disclosure — the preview is part of the flow, not a footnote.
struct BookIntroView: View {

    let bookID: String

    @EnvironmentObject private var content: ContentProvider
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var router: Router
    @Environment(\.strings) private var strings

    private var book: Book? { content.catalog.book(bookID) }

    var body: some View {
        ScrollView {
            if let book {
                VStack(alignment: .leading, spacing: 22) {
                    BookHero(book: book, summary: summary(for: book.allItems))
                    introCard(book)
                    sectionsList(book)
                }
                .padding(Metrics.screenPadding)
                .padding(.bottom, 24)
            } else {
                EmptyStateView(
                    symbol: "questionmark.folder",
                    title: strings[.libraryEmpty],
                    message: strings[.libraryEmptyHint]
                )
            }
        }
        .screenBackground()
        .navigationTitle(book?.shortTitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Pieces

    private func introCard(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings[.bookAbout].uppercased())
                .font(AppFont.sectionHeader)
                .tracking(0.6)
                .foregroundStyle(Palette.textTertiary)
            Text(book.intro)
                .font(AppFont.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func sectionsList(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: strings.format(.bookSectionsCount, book.sections.count))

            ForEach(book.sections) { section in
                Button {
                    router.open(.section(bookID: book.id, sectionID: section.id))
                } label: {
                    SectionRow(
                        section: section,
                        theme: book.theme,
                        summary: summary(for: section.allItems)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func summary(for items: [VocabItem]) -> MetricSummary {
        MetricSummary.make(items: items) { progress.stats(for: $0, mode: .main) }
    }
}

// MARK: - Hero

private struct BookHero: View {
    let book: Book
    let summary: MetricSummary

    @Environment(\.strings) private var strings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(AppFont.title)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !book.author.isEmpty {
                        Text(book.author)
                            .font(AppFont.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer(minLength: 0)
                ProgressRingLabelled(
                    progress: summary.completedFraction,
                    caption: strings[.bookProgress],
                    gradient: LinearGradient(colors: [.white, .white], startPoint: .top, endPoint: .bottom),
                    diameter: 84
                )
                // The ring sits on the book's colour gradient, so its labels
                // need the dark-mode (light text) palette in both appearances.
                .environment(\.colorScheme, .dark)
            }

            HStack(spacing: 10) {
                heroStat(value: "\(summary.total)", label: strings[.statWords])
                heroStat(value: "\(summary.seen)", label: strings[.reportsSeen])
                heroStat(value: "\(summary.mastered)", label: strings[.reportsMastered])
            }
        }
        .padding(Metrics.cardPadding)
        .background(book.theme.gradient)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppFont.metricValueSmall)
                .foregroundStyle(.white)
            Text(label)
                .font(AppFont.badge)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section row

private struct SectionRow: View {
    let section: VocabSection
    let theme: BookTheme
    let summary: MetricSummary

    @Environment(\.strings) private var strings

    var body: some View {
        HStack(spacing: 14) {
            iconBadge
            VStack(alignment: .leading, spacing: 7) {
                titleLine
                MeterBar(progress: summary.completedFraction, gradient: theme.gradient, height: 6)
                chips
            }
            Image(systemName: "chevron.forward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.wash)
            Image(systemName: section.kind.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.solid)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(section.title)
                .font(AppFont.cardTitle)
                .foregroundStyle(Palette.textPrimary)
            if summary.total > 0, summary.completed == summary.total {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.success)
            }
            Spacer(minLength: 0)
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            Chip(text: strings.format(.bookWordsCount, section.wordCount))
            if summary.needsWork > 0 {
                Chip(
                    text: strings.format(.sectionNeedWork, summary.needsWork),
                    symbol: "exclamationmark.circle.fill",
                    tint: Palette.warning,
                    background: Palette.dangerSoft
                )
            } else if summary.isUntouched {
                Chip(text: strings[.sectionNotStarted])
            }
            Spacer(minLength: 0)
        }
    }
}
