import SwiftUI
import UserNotifications

@main
struct TertiaryCoursesApp: App {
    @StateObject private var store = LearnerStore()
    @StateObject private var catalog = CatalogStore()

    init() {
        // Selected segment in segmented pickers: brand blue, semibold — more visible than the default.
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: Theme.accentUI, .font: UIFont.systemFont(ofSize: 14, weight: .semibold)],
            for: .selected
        )
        UNUserNotificationCenter.current().delegate = ReminderDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(catalog)
        }
    }
}

/// Tertiary Courses palette: white + deep blue in light, and a dark counterpart.
/// Every colour adapts, so screens only ever use these and the semantic styles.
enum Theme {
    private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    /// Brand blue for text, icons and tinted controls: deep blue #0B3D8E on light,
    /// a lighter tint on dark so it stays readable.
    static let accentUI = dynamic(light: rgb(11, 61, 142), dark: rgb(92, 153, 250))
    static let accent = Color(uiColor: accentUI)
    static let accentSoft = Color(uiColor: dynamic(light: rgb(11, 61, 142).withAlphaComponent(0.10),
                                                   dark: rgb(92, 153, 250).withAlphaComponent(0.18)))
    /// Solid brand fills that carry white text (badge, selected day, primary buttons).
    static let brand = Color(uiColor: dynamic(light: rgb(11, 61, 142), dark: rgb(31, 94, 199)))
    static let accentDark = Color(red: 10 / 255, green: 45 / 255, blue: 111 / 255)  // gradient bottom #0A2D6F
    static let brandTop = Color(red: 11 / 255, green: 61 / 255, blue: 142 / 255)    // #0B3D8E, both themes
    static let success = Color(uiColor: dynamic(light: UIColor(red: 0.11, green: 0.55, blue: 0.29, alpha: 1),
                                                dark: UIColor(red: 0.30, green: 0.80, blue: 0.47, alpha: 1)))
    static let warning = Color(uiColor: dynamic(light: UIColor(red: 0.80, green: 0.45, blue: 0.0, alpha: 1),
                                                dark: UIColor(red: 1.0, green: 0.70, blue: 0.25, alpha: 1)))
    static let page = Color(uiColor: dynamic(light: UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1),
                                             dark: .systemGroupedBackground))
    static let card = Color(uiColor: dynamic(light: .white, dark: .secondarySystemGroupedBackground))
    static let cardBorder = Color(uiColor: dynamic(light: UIColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1),
                                                   dark: UIColor(white: 1, alpha: 0.14)))
}

/// The appearance the app is showing. Signed in, it follows the account's saved
/// theme; signed out, the device setting. The last value is cached so launch
/// does not flash.
enum Appearance {
    private static let key = "appearance.theme"

    static var cached: ThemeChoice {
        ThemeChoice(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    static func apply(_ choice: ThemeChoice, remember: Bool = true) {
        if remember { UserDefaults.standard.set(choice.rawValue, forKey: key) }
        let style: UIUserInterfaceStyle = switch choice {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        apply(.system, remember: false)
    }
}

/// Brand mark at the top of every tab: the TC LMS badge + the site name.
struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: -2) {
                Text("TC")
                    .font(.system(size: 11, weight: .heavy))
                Text(Site.code)
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                LinearGradient(colors: [Theme.brandTop, Theme.accentDark], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            Text(Site.siteName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Site.siteName)
    }
}

extension View {
    /// Places the brand mark in the top navigation bar. Apply inside each tab's NavigationStack.
    func brandToolbar() -> some View {
        toolbar { ToolbarItem(placement: .principal) { BrandHeader() } }
    }
}

/// Signed out: browse courses + sign in. Signed in: the learner's LMS.
struct RootView: View {
    @EnvironmentObject private var store: LearnerStore
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.restoring {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.page)
            } else if store.isSignedIn {
                LearnerTabs()
            } else {
                GuestTabs()
            }
        }
        .tint(Theme.accent)
        .onAppear { Appearance.apply(Appearance.cached, remember: false) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshIfStale() } }
        }
        .task {
            async let r: Void = store.restore()
            async let c: Void = catalog.refresh()
            _ = await (r, c)
        }
    }
}

/// `START_TAB` selects the first tab (used by screenshot automation).
private let startTab = ProcessInfo.processInfo.environment["START_TAB"].flatMap(Int.init) ?? 0

struct GuestTabs: View {
    @State private var selection = startTab

    var body: some View {
        TabView(selection: $selection) {
            SignInView()
                .tabItem { Label("Sign In", systemImage: "person.crop.circle") }
                .tag(0)
            CatalogView()
                .tabItem { Label("Courses", systemImage: "books.vertical.fill") }
                .tag(1)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle.fill") }
                .tag(2)
        }
    }
}

struct LearnerTabs: View {
    @EnvironmentObject private var store: LearnerStore

    // The tabs follow the role being viewed, as in the TIA TMS app:
    //   Learner:   My Classes, Calendar, Certificates, Support, Account
    //   Trainer:   My Classes, Calendar, Payout, Hours, Account
    //   Admin:     Home, Calendar, Courses, Account
    //   Developer, Marketing, Franchise Admin: Home, Courses, Account
    var body: some View {
        TabView(selection: $store.tab) {
            if let role = store.staffRole {
                staffHome(role)
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(LearnerStore.dashboardTab)
                if role == "admin" {
                    AdminCalendarView()
                        .tabItem { Label("Calendar", systemImage: "calendar") }
                        .tag(1)
                }
                CatalogView()
                    .tabItem { Label("Courses", systemImage: "books.vertical.fill") }
                    .tag(2)
            } else {
                ClassesView()
                    .tabItem { Label("My Classes", systemImage: "graduationcap.fill") }
                    .tag(0)
                CalendarView()
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                    .tag(1)
                if store.isTrainer {
                    PayoutView()
                        .tabItem { Label("Payout", systemImage: "banknote.fill") }
                        .tag(2)
                    TrainingHoursView()
                        .tabItem { Label("Hours", systemImage: "clock.fill") }
                        .tag(3)
                } else {
                    CertificatesView()
                        .tabItem { Label("Certificates", systemImage: "rosette") }
                        .tag(2)
                    SupportView()
                        .tabItem { Label("Support", systemImage: "lifepreserver") }
                        .tag(3)
                }
            }
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle.fill") }
                .tag(4)
        }
        // A staff view opens on its dashboard.
        .onAppear { if store.staffRole != nil, store.tab == 0 { store.tab = LearnerStore.dashboardTab } }
        .alert("Signed in", isPresented: Binding(get: { store.roleNotice != nil }, set: { if !$0 { store.roleNotice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.roleNotice ?? "") }
    }

    @ViewBuilder private func staffHome(_ role: String) -> some View {
        switch role {
        case "admin": AdminHomeView()
        case "developer": DeveloperHomeView()
        default: StaffDashboardView(role: role)
        }
    }
}
