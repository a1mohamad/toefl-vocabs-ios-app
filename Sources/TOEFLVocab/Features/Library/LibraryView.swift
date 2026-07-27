import SwiftUI

struct LibraryView: View {

    @EnvironmentObject private var content: ContentProvider
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var router: Router
    @Environment(\.strings) private var strings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let error = content.loadError {
                    contentErrorCard(error)
                } else if content.catalog.isEmpty {
                    EmptyStateView(
                        symbol: "books.vertical",
                        title: strings[.libraryEmpty],
                        message: strings[.libraryEmptyHint]
                    )
                } else {
                    if let resume = resumeTarget {
                        ContinueCard(target: resume) { router.open(.section(bookID: resume.bookID, sectionID: resume.sectionID)) }
                    }
                    booksSection
                }
            }
            .padding(Metrics.screenPadding)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(strings[.libraryTitle])
                .font(AppFont.screenTitle)
                .foregroundStyle(Palette.textPrimary)
            Text(strings.format(.librarySubtitle, content.catalog.totalWordCount))
                .font(AppFont.body)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var booksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(content.catalog.books) { book in
                Button {
                    router.open(.book(bookID: book.id))
                } label: {
                    BookCard(book: book, summary: summary(for: book))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func contentErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(strings[.libraryEmpty], systemImage: "exclamationmark.triangle.fill")
                .font(AppFont.cardTitle)
                .foregroundStyle(Palette.warning)
            Text(message)
                .font(AppFont.body)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Data

    private func summary(for book: Book) -> MetricSummary {
        MetricSummary.make(items: book.allItems) { progress.stats(for: $0, mode: .main) }
    }

    /// Last place the user practised, resolved against the current catalog so a
    /// removed section cannot produce a dead card.
    private var resumeTarget: ResumeTarget? {
        guard let location = progress.lastLocation,
              let book = content.catalog.book(location.bookID),
              let section = book.section(location.sectionID)
        else { return nil }

        return ResumeTarget(
            bookID: book.id,
            sectionID: section.id,
            bookTitle: book.shortTitle,
            sectionTitle: section.title,
            category: location.category,
            theme: book.theme
        )
    }
}

// MARK: - Resume

struct ResumeTarget {
    let bookID: String
    let sectionID: String
    let bookTitle: String
    let sectionTitle: String
    let category: VocabCategory
    let theme: BookTheme
}

private struct ContinueCard: View {
    let target: ResumeTarget
    let action: () -> Void

    @Environment(\.strings) private var strings

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(target.theme.solid)

                VStack(alignment: .leading, spacing: 3) {
                    Text(strings[.libraryContinue])
                        .font(AppFont.badge)
                        .foregroundStyle(Palette.textTertiary)
                    Text("\(target.bookTitle) · \(target.sectionTitle)")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(strings[target.category.titleKey])
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .card(background: Palette.surfaceRaised)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Book card

private struct BookCard: View {
    let book: Book
    let summary: MetricSummary

    @Environment(\.strings) private var strings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topRow
            Text(book.intro)
                .font(AppFont.body)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            footer
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: 14) {
            coverBadge
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(AppFont.title)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Stylised "spine" standing in for cover art — no image assets to ship.
    private var coverBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(book.theme.gradient)
            Text(book.id)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .padding(4)
        }
        .frame(width: 58, height: 74)
        .accessibilityHidden(true)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            MeterBar(progress: summary.completedFraction, gradient: book.theme.gradient)
            HStack(spacing: 8) {
                Chip(
                    text: strings.format(.bookSectionsCount, book.sections.count),
                    symbol: "square.stack.3d.up.fill"
                )
                Chip(
                    text: strings.format(.bookWordsCount, book.wordCount),
                    symbol: "textformat.abc"
                )
                Spacer(minLength: 0)
                Text("\(Int((summary.completedFraction * 100).rounded()))%")
                    .font(AppFont.caption)
                    .foregroundStyle(book.theme.solid)
            }
        }
    }
}
