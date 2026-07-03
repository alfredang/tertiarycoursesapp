import SwiftUI

@main
struct TertiaryCoursesApp: App {
    init() {
        // Selected segment in segmented pickers: deep blue, semibold — more visible than default black.
        let accent = UIColor(red: 11 / 255, green: 61 / 255, blue: 142 / 255, alpha: 1)
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: accent, .font: UIFont.systemFont(ofSize: 14, weight: .semibold)],
            for: .selected
        )
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.light)   // white theme, matching tertiarycourses.com.sg
        }
    }
}

// White theme with the Tertiary Infotech deep-blue brand accent (sampled from the T logo).
enum Theme {
    static let accent = Color(red: 11 / 255, green: 61 / 255, blue: 142 / 255)   // deep blue #0B3D8E
    static let accentSoft = Color(red: 11 / 255, green: 61 / 255, blue: 142 / 255).opacity(0.10)
    static let page = Color.white
    static let card = Color.white
    static let cardBorder = Color(red: 0.88, green: 0.88, blue: 0.90)
}

struct MainTabView: View {
    @StateObject private var catalog = CourseCatalogStore()
    // START_TAB env var selects the initial tab (used by screenshot automation)
    @State private var selection = ProcessInfo.processInfo.environment["START_TAB"].flatMap(Int.init) ?? 0

    var body: some View {
        TabView(selection: $selection) {
            CatalogView(catalog: catalog)
                .tabItem { Label("Catalog", systemImage: "books.vertical.fill") }
                .tag(0)

            GrantCalculatorView(catalog: catalog)
                .tabItem { Label("Grant Calculator", systemImage: "dollarsign.circle.fill") }
                .tag(1)

            FeedbackView()
                .tabItem { Label("Feedback", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(2)

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle.fill") }
                .tag(3)
        }
        .tint(Theme.accent)
        .task {
            await catalog.loadCourseRuns()
        }
    }
}

#Preview {
    MainTabView()
}
