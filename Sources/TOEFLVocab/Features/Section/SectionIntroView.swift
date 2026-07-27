import SwiftUI

/// Section preview and list picker — the last stop before practice starts.
///
/// Shows which words are queued first, so the adaptive ordering is visible
/// rather than mysterious: after a bad run the user can see their worst words
/// waiting at the front before they tap Begin.
struct SectionIntroView: View {

    let bookID: String
    let sectionID: String

    @EnvironmentObject private var content: ContentProvider
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var router: Router
    @Environment(\.strings) private var strings

    @State private var selectedCategory: VocabCategory = .main

    private var book: Book? { content.catalog.book(bookID) }
    private var section: VocabSection? { book?.section(sectionID) }

    var body: some View {
        ScrollView {
            if let book, let section {
                VStack(alignment: .leading, spacing: 20) {
                    intro(section, theme: book.theme)
                    categoryPicker(section, theme: book.theme)
                    queuePreview(section, theme: book.theme)
                    beginButton(book: book, section: section)
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
        .navigationTitle(section?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: selectDefaultCategory)
    }

    // MARK: Pieces

    private func intro(_ section: VocabSection, theme: BookTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: section.kind.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.solid)
                Text(section.title)
                    .font(AppFont.title)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
            }

            if !section.intro.isEmpty {
                Text(section.intro)
                    .font(AppFont.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func categoryPicker(_ section: VocabSection, theme: BookTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: strings[.sectionChooseList])

            ForEach(VocabCategory.allCases) { category in
                let items = section.items(in: category)
                if items.isEmpty {
                    if category == .extra {
                        Text(strings[.sectionNoExtras])
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 4)
                    }
                } else {
                    CategoryCard(
                        category: category,
                        theme: theme,
                        summary: MetricSummary.make(items: items) { progress.stats(for: $0, mode: .main) },
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func queuePreview(_ section: VocabSection, theme: BookTheme) -> some View {
        let preview = orderedQueue(section).prefix(3)
        if !preview.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: strings[.sectionBegin])
                HStack(spacing: 6) {
                    ForEach(Array(preview), id: \.id) { item in
                        Text(item.term)
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Palette.surfaceSunken)
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }
                    Text("…")
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textTertiary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func beginButton(book: Book, section: VocabSection) -> some View {
        Button {
            let location = LastLocation(
                bookID: book.id,
                sectionID: section.id,
                category: selectedCategory
            )
            progress.rememberLocation(location)
            router.startPractice(
                .section(bookID: book.id, sectionID: section.id, category: selectedCategory)
            )
        } label: {
            Text(strings[.sectionBegin])
        }
        .buttonStyle(PrimaryButtonStyle(gradient: book.theme.gradient))
        .disabled(section.items(in: selectedCategory).isEmpty)
        .padding(.top, 4)
    }

    // MARK: Data

    private func orderedQueue(_ section: VocabSection) -> [VocabItem] {
        AdaptiveOrdering.order(section.items(in: selectedCategory)) {
            progress.stats(for: $0, mode: .main)
        }
    }

    /// `504/review_1` has no extras, so the default must be whatever the section
    /// actually has rather than a hard-coded `.main`.
    private func selectDefaultCategory() {
        guard let section else { return }
        let available = section.availableCategories
        guard !available.isEmpty, !available.contains(selectedCategory) else { return }
        selectedCategory = available[0]
    }
}

// MARK: - Category card

private struct CategoryCard: View {
    let category: VocabCategory
    let theme: BookTheme
    let summary: MetricSummary
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.strings) private var strings

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings[category.titleKey])
                        .font(AppFont.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Text(strings[category.subtitleKey])
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                    chips
                }
                Spacer(minLength: 0)
                selectionIndicator
            }
            .padding(14)
            .background(isSelected ? theme.wash : Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? theme.solid : Palette.separator, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var icon: some View {
        ZStack {
            Circle().fill(theme.wash)
            Image(systemName: category.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.solid)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            Chip(text: strings.format(.bookWordsCount, summary.total))
            if summary.needsWork > 0 {
                Chip(
                    text: strings.format(.sectionNeedWork, summary.needsWork),
                    symbol: "exclamationmark.circle.fill",
                    tint: Palette.warning,
                    background: Palette.dangerSoft
                )
            }
        }
        .padding(.top, 2)
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
            .font(.system(size: 20))
            .foregroundStyle(isSelected ? theme.solid : Palette.textTertiary)
            .accessibilityHidden(true)
    }
}
