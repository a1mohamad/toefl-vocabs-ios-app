import SwiftUI

struct AboutView: View {

    @EnvironmentObject private var content: ContentProvider
    @Environment(\.strings) private var strings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appCard
                block(title: strings[.aboutContentTitle], body: strings[.aboutContentBody])
                block(title: strings[.settingsPrivacy], body: strings[.settingsPrivacyBody])
                librarySummary
            }
            .padding(Metrics.screenPadding)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(strings[.aboutTitle])
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(BookTheme.indigo.gradient)
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("TOEFL Vocab")
                        .font(AppFont.title)
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(strings[.settingsVersion]) \(SettingsView.versionString)")
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }

            Text(strings[.aboutBody])
                .font(AppFont.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func block(title: String, body text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(AppFont.sectionHeader)
                .tracking(0.6)
                .foregroundStyle(Palette.textTertiary)
            Text(text)
                .font(AppFont.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var librarySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(content.catalog.books) { book in
                HStack(spacing: 10) {
                    Circle()
                        .fill(book.theme.gradient)
                        .frame(width: 10, height: 10)
                    Text(book.title)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 0)
                    Text(strings.format(.bookWordsCount, book.wordCount))
                        .font(AppFont.badge)
                        .foregroundStyle(Palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}
