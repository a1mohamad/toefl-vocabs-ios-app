import SwiftUI

struct RootView: View {

    @EnvironmentObject private var router: Router
    @Environment(\.strings) private var strings

    var body: some View {
        TabView(selection: $router.tab) {
            studyTab
            reportsTab
            settingsTab
        }
        .tint(Palette.accent)
        .fullScreenCover(item: $router.activePractice) { configuration in
            PracticeContainerView(configuration: configuration)
        }
    }

    private var studyTab: some View {
        NavigationStack(path: $router.studyPath) {
            LibraryView()
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .tabItem {
            Label(strings[.tabStudy], systemImage: "books.vertical.fill")
        }
        .tag(Router.Tab.study)
    }

    private var reportsTab: some View {
        NavigationStack {
            ReportsView()
        }
        .tabItem {
            Label(strings[.tabReports], systemImage: "chart.bar.xaxis")
        }
        .tag(Router.Tab.reports)
    }

    private var settingsTab: some View {
        NavigationStack {
            SettingsView()
                // Settings pushes `Route.about`, so this stack needs the same
                // destination table the study stack has.
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .tabItem {
            Label(strings[.tabSettings], systemImage: "gearshape.fill")
        }
        .tag(Router.Tab.settings)
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .book(let bookID):
            BookIntroView(bookID: bookID)
        case .section(let bookID, let sectionID):
            SectionIntroView(bookID: bookID, sectionID: sectionID)
        case .about:
            AboutView()
        }
    }
}
