import Charts
import SwiftUI

/// Analytics without a wall of rows.
///
/// The shape of the screen is deliberate: one number that matters at the top,
/// then a per-book breakdown where each section is a single coloured cell in a
/// grid rather than its own row, then only the handful of words actually worth
/// acting on. Seventeen sections across two books would be an unreadable list;
/// as a heat grid it is one glance.
struct ReportsView: View {

    @EnvironmentObject private var content: ContentProvider
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.strings) private var strings

    var body: some View {
        let data = StatsAggregator.build(catalog: content.catalog, progress: progress.state)

        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if data.hasData {
                    OverviewCard(data: data)
                    DrillCard(
                        scope: $settings.settings.extraPracticeScope,
                        weakCount: data.overall.needsWork
                    ) {
                        router.startPractice(.drill(scope: settings.settings.extraPracticeScope))
                    }
                    booksSection(data)
                    weakestSection(data)
                    trendSection(data)
                    splitSection(data)
                } else {
                    DrillCard(
                        scope: $settings.settings.extraPracticeScope,
                        weakCount: 0
                    ) {
                        router.startPractice(.drill(scope: settings.settings.extraPracticeScope))
                    }
                    .disabled(content.catalog.isEmpty)

                    EmptyStateView(
                        symbol: "chart.bar.doc.horizontal",
                        title: strings[.reportsEmpty],
                        message: strings[.reportsEmptyHint]
                    )
                }
            }
            .padding(Metrics.screenPadding)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(strings[.reportsTitle])
    }

    // MARK: Sections

    private func booksSection(_ data: ReportData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: strings[.reportsByBook])
            ForEach(data.books) { book in
                BookReportCard(report: book)
            }
        }
    }

    @ViewBuilder
    private func weakestSection(_ data: ReportData) -> some View {
        if !data.weakest.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: strings[.reportsWeakest])
                VStack(spacing: 0) {
                    ForEach(Array(data.weakest.enumerated()), id: \.element.id) { pair in
                        WeakWordRow(word: pair.element)
                        if pair.offset < data.weakest.count - 1 {
                            Divider().overlay(Palette.separator).padding(.leading, 14)
                        }
                    }
                }
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(Palette.separator, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func trendSection(_ data: ReportData) -> some View {
        if data.recentSessions.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: strings[.reportsRecent])
                SessionTrendChart(sessions: data.recentSessions)
                    .card()
            }
        }
    }

    private func splitSection(_ data: ReportData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: strings[.reportsMainVsExtra])
            HStack(spacing: 10) {
                StatTile(
                    value: "\(data.mainSummary.attempts)",
                    label: strings[.categoryMain],
                    symbol: VocabCategory.main.symbolName,
                    tint: Palette.accent
                )
                StatTile(
                    value: "\(data.extraSummary.attempts)",
                    label: strings[.categoryExtra],
                    symbol: VocabCategory.extra.symbolName,
                    tint: Palette.accent
                )
                StatTile(
                    value: "\(data.extraAttempts)",
                    label: strings[.reportsExtraPractice],
                    symbol: "bolt.fill",
                    tint: Palette.warning
                )
            }
            Text(strings.format(.reportsRun, data.runNumber))
                .font(AppFont.badge)
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

// MARK: - Overview

private struct OverviewCard: View {
    let data: ReportData

    @Environment(\.strings) private var strings

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ProgressRingLabelled(
                    progress: data.overall.masteredFraction,
                    caption: strings[.reportsMastered],
                    diameter: 108
                )
                VStack(alignment: .leading, spacing: 8) {
                    metric(
                        value: "\(Int((data.overall.accuracy * 100).rounded()))%",
                        label: strings[.reportsAccuracy]
                    )
                    metric(
                        value: "\(data.overall.seen)/\(data.overall.total)",
                        label: strings[.reportsSeen]
                    )
                    metric(
                        value: "\(data.overall.needsWork)",
                        label: strings[.reportsWeakest]
                    )
                }
                Spacer(minLength: 0)
            }
        }
        .card()
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(AppFont.metricValueSmall)
                .foregroundStyle(Palette.textPrimary)
            Text(label)
                .font(AppFont.badge)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Drill entry point

private struct DrillCard: View {
    @Binding var scope: ExtraPracticeScope
    let weakCount: Int
    let onStart: () -> Void

    @Environment(\.strings) private var strings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.warning)
                Text(strings[.reportsExtraPractice])
                    .font(AppFont.title)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                if weakCount > 0 {
                    Chip(
                        text: strings.format(.sectionNeedWork, weakCount),
                        tint: Palette.warning,
                        background: Palette.dangerSoft
                    )
                }
            }

            Text(strings[.reportsExtraSubtitle])
                .font(AppFont.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(strings[.reportsScope].uppercased())
                    .font(AppFont.badge)
                    .foregroundStyle(Palette.textTertiary)
                Picker(strings[.reportsScope], selection: $scope) {
                    ForEach(ExtraPracticeScope.allCases) { option in
                        Text(strings[option.titleKey]).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Button(strings[.reportsStartDrill], action: onStart)
                .buttonStyle(PrimaryButtonStyle(gradient: BookTheme.amber.gradient))
        }
        .card()
    }
}

// MARK: - Book report

private struct BookReportCard: View {
    let report: BookReport

    @Environment(\.strings) private var strings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            MeterBar(progress: report.summary.completedFraction, gradient: report.theme.gradient)
            SectionHeatGrid(sections: report.sections, theme: report.theme)
            legend
        }
        .card()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(report.shortTitle)
                .font(AppFont.cardTitle)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
            Text("\(Int((report.summary.accuracy * 100).rounded()))%")
                .font(AppFont.metricValueSmall)
                .foregroundStyle(report.theme.solid)
            Text(strings[.reportsAccuracy])
                .font(AppFont.badge)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Chip(text: strings.format(.bookWordsCount, report.summary.total))
            Chip(
                text: "\(report.summary.mastered) \(strings[.reportsMastered])",
                symbol: "checkmark.seal.fill",
                tint: Palette.success,
                background: Palette.successSoft
            )
            Spacer(minLength: 0)
        }
    }
}

/// Every section as one cell, shaded by accuracy. Turns seventeen rows into a
/// single glanceable block.
private struct SectionHeatGrid: View {
    let sections: [SectionReport]
    let theme: BookTheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(sections) { section in
                cell(for: section)
            }
        }
    }

    private func cell(for section: SectionReport) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill(for: section))
            .frame(height: 38)
            .overlay(
                Text(shortLabel(for: section))
                    .font(AppFont.badge)
                    .foregroundStyle(textColor(for: section))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(2)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(section.title): \(Int((section.summary.accuracy * 100).rounded())) percent accuracy, "
                + "\(section.summary.seen) of \(section.summary.total) seen"
            )
    }

    /// Untouched sections stay neutral; touched ones fade in with accuracy, so
    /// "not started" never looks like "doing badly".
    private func fill(for section: SectionReport) -> Color {
        guard !section.summary.isUntouched else { return Palette.surfaceSunken }
        let intensity = 0.25 + 0.75 * section.summary.accuracy
        return theme.solid.opacity(intensity)
    }

    private func textColor(for section: SectionReport) -> Color {
        section.summary.isUntouched ? Palette.textTertiary : .white
    }

    /// "Day 3" -> "3", "Review 1" -> "R1" so the cell stays readable.
    private func shortLabel(for section: SectionReport) -> String {
        let digits = section.title.filter { $0.isNumber }
        if section.kind == .review { return digits.isEmpty ? "R" : "R\(digits)" }
        return digits.isEmpty ? section.title : digits
    }
}

// MARK: - Weak word row

private struct WeakWordRow: View {
    let word: WeakWord

    @Environment(\.strings) private var strings

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(word.item.term)
                    .font(AppFont.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text("\(word.bookShortTitle) · \(word.sectionTitle)")
                    .font(AppFont.badge)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                tallies
                if let stats = word.mainStats {
                    ChecklistView(display: stats.checklist, compact: true)
                }
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    private var tallies: some View {
        HStack(spacing: 6) {
            Label("\(word.mainStats?.correct ?? 0)", systemImage: "checkmark")
                .font(AppFont.badge)
                .foregroundStyle(Palette.success)
            Label("\(word.mainStats?.incorrect ?? 0)", systemImage: "xmark")
                .font(AppFont.badge)
                .foregroundStyle(Palette.danger)
        }
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - Trend

private struct SessionTrendChart: View {
    let sessions: [SessionRecord]

    @Environment(\.strings) private var strings

    private struct Point: Identifiable {
        let id: Int
        let accuracy: Double
        let isDrill: Bool
    }

    /// Reversed because `recentSessions` arrives newest-first for the list, and
    /// a chart reads oldest-to-newest.
    private var points: [Point] {
        sessions
            .reversed()
            .enumerated()
            .map { Point(id: $0.offset, accuracy: $0.element.accuracy, isDrill: $0.element.mode == .extra) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(points) { point in
                BarMark(
                    x: .value("Session", point.id),
                    y: .value("Accuracy", point.accuracy)
                )
                .foregroundStyle(point.isDrill ? Palette.warning : Palette.accent)
                .cornerRadius(3)
            }
            .chartYScale(domain: 0...1)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 120)
            .accessibilityLabel(strings[.reportsRecent])

            HStack(spacing: 12) {
                legendDot(color: Palette.accent, label: strings[.tabStudy])
                legendDot(color: Palette.warning, label: strings[.reportsExtraPractice])
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(AppFont.badge)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}
