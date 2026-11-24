import SwiftUI

/// Signed-in state and the learner's LMS data. One instance for the app.
@MainActor
final class LearnerStore: ObservableObject {
    @Published private(set) var learner: Learner?
    @Published private(set) var restoring = true
    @Published var classes: ClassesReply?
    /// Classes this account teaches; nil until loaded or when it is not a trainer.
    @Published var trainerClasses: ClassesReply?
    @Published var certificates: [CertificateInfo]?
    @Published var orders: [Order]?
    @Published var loadError: String?
    @Published private(set) var avatar: UIImage?
    private var avatarLoadedVersion: Int?

    var isSignedIn: Bool { learner != nil }
    // MARK: Roles
    //
    // The app shows one role at a time. Every account that holds more than one role
    // (trainer and learner, plus the staff roles the website gives it: Admin,
    // Marketing, Developer, Franchise Admin) can switch with "View as", in every
    // country's app. The choice changes what this device shows, never what the
    // server allows: each endpoint still checks the role.

    static let staffRoleNames: [String: String] = [
        "admin": "Admin", "marketing": "Marketing", "developer": "Developer", "franchise_admin": "Franchise Admin",
    ]
    static func roleName(_ role: String) -> String {
        staffRoleNames[role] ?? (role == "trainer" ? "Trainer" : "Learner")
    }

    @Published private(set) var viewRole = UserDefaults.standard.string(forKey: "viewRole") ?? ""
    /// The role picked on the sign-in screen: "learner" (default) or "trainer".
    /// A trainer who is taking courses signs in as a learner to see them.
    @Published var loginRole = UserDefaults.standard.string(forKey: "loginRole") ?? "learner" {
        didSet { UserDefaults.standard.set(loginRole, forKey: "loginRole") }
    }
    /// The selected bottom tab (the home header's My Profile link jumps to Account).
    /// Shown once after sign-in when the chosen role is not available.
    @Published var roleNotice: String?
    @Published var tab = ProcessInfo.processInfo.environment["START_TAB"].flatMap(Int.init) ?? 0
    static let accountTab = 4
    static let dashboardTab = 5

    var availableRoles: [String] {
        guard let l = learner else { return [] }
        var roles = l.isTrainer ? ["learner", "trainer"] : ["learner"]
        roles += ["developer", "marketing", "admin", "franchise_admin"].filter { (l.roles ?? []).contains($0) }
        return roles
    }
    var canSwitchRole: Bool { availableRoles.count > 1 }
    var activeRole: String {
        if availableRoles.contains(viewRole) { return viewRole }
        return availableRoles.contains(loginRole) ? loginRole : (availableRoles.first ?? "learner")
    }
    var isTrainer: Bool { activeRole == "trainer" }
    /// The staff role being viewed, or nil in the trainer and learner views.
    var staffRole: String? { Self.staffRoleNames[activeRole] != nil ? activeRole : nil }

    func setViewRole(_ role: String) async {
        viewRole = role
        UserDefaults.standard.set(role, forKey: "viewRole")
        tab = staffRole != nil ? Self.dashboardTab : 0
        await refreshClasses()
    }
    private var lastClassRefresh: Date?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    init() {
        NotificationCenter.default.addObserver(forName: .sessionExpired, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.clear() }
        }
    }

    // MARK: Sign-in

    /// Resume a saved session on launch.
    func restore() async {
        defer { restoring = false }
        #if DEBUG
        // Screenshot automation: UITEST_SIGNIN="email|password" signs in on launch.
        if let creds = ProcessInfo.processInfo.environment["UITEST_SIGNIN"], let bar = creds.firstIndex(of: "|") {
            do {
                try await signIn(email: String(creds[..<bar]), password: String(creds[creds.index(after: bar)...]))
            } catch {
                print("UITEST_SIGNIN failed: \(error.localizedDescription)")
            }
            if isSignedIn { await refreshAll() }
            return
        }
        #endif
        guard Keychain.read() != nil else { return }
        do {
            let me: MeReply = try await API.shared.get("auth/me")
            setLearner(me.learner)
            await refreshAll()
        } catch let error as APIError where error.status == 401 {
            clear()
        } catch {
            // Offline: keep the token and retry on the next refresh.
            loadError = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async throws {
        let reply: AuthReply = try await API.shared.post("auth/password", body: [
            "email": email.trimmingCharacters(in: .whitespaces), "password": password,
            "platform": "ios", "app_version": appVersion,
        ])
        try finishSignIn(reply)
    }

    func sendCode(email: String) async throws -> String {
        let reply: MessageReply = try await API.shared.post("auth/otpsend", body: ["email": email.trimmingCharacters(in: .whitespaces)])
        return reply.message ?? "Check your email for a 6-digit code."
    }

    func verifyCode(email: String, code: String) async throws {
        let reply: AuthReply = try await API.shared.post("auth/otpverify", body: [
            "email": email.trimmingCharacters(in: .whitespaces), "code": code,
            "platform": "ios", "app_version": appVersion,
        ])
        try finishSignIn(reply)
    }

    /// Admin sign-in: swaps the single-use code from Google sign-in for a session.
    /// The owner account then opens on its Admin view where that is available.
    func signInWithGoogle(code: String, verifier: String) async throws {
        let reply: AuthReply = try await API.shared.post("auth/googleexchange", body: [
            "code": code, "verifier": verifier, "platform": "ios", "app_version": appVersion,
        ])
        try finishSignIn(reply)
        if availableRoles.contains("admin") { await setViewRole("admin") }
    }

    private func finishSignIn(_ reply: AuthReply) throws {
        try Keychain.save(reply.token)
        // Record the role picked on the sign-in screen (the default, Learner, included).
        UserDefaults.standard.set(loginRole, forKey: "loginRole")
        viewRole = ""
        UserDefaults.standard.removeObject(forKey: "viewRole")
        setLearner(reply.learner)
        if loginRole == "trainer", !reply.learner.isTrainer {
            roleNotice = "This account does not teach any classes, so you are signed in as a learner."
        }
        Task { await refreshAll() }
    }

    func signOut() async {
        let _: MessageReply? = try? await API.shared.post("auth/logout")
        clear()
    }

    /// Permanently deletes the learner's login account on the site.
    func deleteAccount() async throws -> String {
        let reply: MessageReply = try await API.shared.post("auth/delete", body: ["confirm": "DELETE"])
        clear()
        return reply.message ?? "Your account has been deleted."
    }

    func clear() {
        Keychain.clear()
        learner = nil
        classes = nil
        trainerClasses = nil
        lastClassRefresh = nil
        Appearance.reset()
        avatar = nil
        avatarLoadedVersion = nil
        viewRole = ""
        UserDefaults.standard.removeObject(forKey: "viewRole")
        tab = 0
        loginRole = "learner"
        Reminders.cancelAll()
        certificates = nil
        orders = nil
        loadError = nil
    }

    // MARK: Data

    func refreshAll() async {
        async let c: Void = refreshClasses()
        async let e: Void = refreshCertificates()
        async let b: Void = refreshBilling()
        _ = await (c, e, b)
    }

    /// Pull-to-refresh cancels its task when the list redraws mid-refresh, and the learner list
    /// lands (and redraws) before the teaching list, so the teaching request was cancelled and a
    /// trainer's Current/Upcoming list never refreshed. An unstructured task cannot be cancelled that way.
    func refreshClasses() async {
        await Task { await self.loadClasses() }.value
    }

    private func loadClasses() async {
        let teaches = isTrainer
        async let teaching: ClassesReply? = teaches ? (try? await API.shared.get("trainer/classes")) : nil
        do {
            classes = try await API.shared.get("learner/classes")
            loadError = nil
            lastClassRefresh = Date()
        } catch { loadError = error.localizedDescription }
        // A failed trainer refresh keeps the last list rather than emptying the screen.
        if let t = await teaching { trainerClasses = t } else if !isTrainer { trainerClasses = nil }
        if classes != nil { await Reminders.sync(with: self) }
    }

    /// Called when the app comes back to the foreground: at most once every 5 minutes.
    func refreshIfStale() async {
        guard isSignedIn, !restoring else { return }
        if let last = lastClassRefresh, Date().timeIntervalSince(last) < 300 { return }
        if let me: MeReply = try? await API.shared.get("auth/me") { setLearner(me.learner) }
        guard isSignedIn else { return }
        await refreshClasses()
    }

    // MARK: Profile

    private func setLearner(_ value: Learner) {
        // Signed in before the sign-in screen asked for a role: keep trainers in the trainer view.
        if UserDefaults.standard.object(forKey: "loginRole") == nil {
            loginRole = value.isTrainer ? "trainer" : "learner"
        }
        learner = value
        // An older site sends no theme; keep the choice made on this device.
        if value.theme != nil { Appearance.apply(value.themeChoice) }
        syncAvatar(value.avatarVersion)
    }

    // MARK: Profile picture

    /// Downloads the picture when the site has a newer one than this device shows.
    private func syncAvatar(_ version: Int?) {
        guard let version else { avatar = nil; avatarLoadedVersion = nil; return }
        guard version != avatarLoadedVersion else { return }
        avatarLoadedVersion = version
        Task {
            if let data = try? await API.shared.getData("profile/avatar"), let image = UIImage(data: data) {
                avatar = image
            }
        }
    }

    /// Shrinks the picture to a 512px square JPEG, shows it at once and uploads it.
    func setAvatar(_ image: UIImage) async throws {
        let side: CGFloat = 512
        let crop = min(image.size.width, image.size.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let scale = side / crop
            image.draw(in: CGRect(x: (side - image.size.width * scale) / 2, y: (side - image.size.height * scale) / 2,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
        guard let jpeg = square.jpegData(compressionQuality: 0.85) else {
            throw APIError(message: "That picture could not be used.")
        }
        let reply: ProfileReply = try await API.shared.post("profile/avatar", body: ["image": jpeg.base64EncodedString()])
        avatar = square
        learner = reply.learner
        avatarLoadedVersion = reply.learner.avatarVersion
    }

    func removeAvatar() async throws {
        let reply: ProfileReply = try await API.shared.post("profile/avatar", body: ["remove": 1])
        avatar = nil
        learner = reply.learner
        avatarLoadedVersion = nil
    }

    /// Saves the profile on the site. The appearance is applied at once, and kept
    /// on this device even when the site cannot store it yet.
    func updateProfile(firstName: String, lastName: String, phone: String, linkedin: String?, employment: String? = nil, theme: ThemeChoice) async throws -> String {
        Appearance.apply(theme)
        do {
            var body: [String: Any] = ["first_name": firstName, "last_name": lastName, "phone": phone, "theme": theme.rawValue]
            if let linkedin { body["linkedin_url"] = linkedin }
            if let employment { body["employment_status"] = employment }
            let reply: ProfileReply = try await API.shared.post("profile", body: body)
            learner = reply.learner
            if reply.learner.theme != nil { Appearance.apply(reply.learner.themeChoice) }
            return reply.message ?? "Profile updated."
        } catch let error as APIError where error.status == 404 {
            throw APIError(message: "Your appearance is saved on this device. Editing your name and phone will be available shortly.", status: 404)
        }
    }

    // MARK: Staff dashboard

    func loadStaffDashboard(_ role: String) async throws -> StaffDashboard {
        try await API.shared.get("staff/dashboard", query: ["role": role])
    }

    // MARK: Trainer payout and training hours

    func loadPayouts() async throws -> PayoutsReply { try await API.shared.get("trainer/payouts") }
    func loadTrainingHours() async throws -> TrainingHoursReply { try await API.shared.get("trainer/hours") }

    // MARK: Trainer certifications

    private struct CertsReply: Decodable { let certifications: [CertItem] }
    private struct CertItem: Decodable { let name: String; let issuer: String; let year: Int? }

    func loadCertifications() async throws -> [CertDraft] {
        let reply: CertsReply = try await API.shared.get("trainer/certifications")
        return reply.certifications.map { CertDraft(name: $0.name, issuer: $0.issuer, year: $0.year.map(String.init) ?? "") }
    }

    func saveCertifications(_ list: [CertDraft]) async throws {
        let items: [[String: Any]] = list.map { ["name": $0.name, "issuer": $0.issuer, "year": $0.year] }
        let _: CertsReply = try await API.shared.post("trainer/certifications", body: ["items": items])
    }

    // MARK: Trainer

    func trainerClass(runId: Int) async throws -> TrainerClassDetail {
        let reply: TrainerClassReply = try await API.shared.get("trainer/class", query: ["run_id": String(runId)])
        return reply.class
    }

    func saveAttendance(runId: Int, sessionKey: String, records: [[String: Any]]) async throws -> String {
        let reply: MessageReply = try await API.shared.post("trainer/attendance", body: [
            "run_id": runId, "session_key": sessionKey, "records": records,
        ])
        return reply.message ?? "Attendance saved."
    }

    func refreshCertificates() async {
        do {
            let reply: CertificatesReply = try await API.shared.get("learner/certificates")
            certificates = reply.certificates
        } catch { loadError = error.localizedDescription }
    }

    func refreshBilling() async {
        do {
            let reply: BillingReply = try await API.shared.get("learner/billing")
            orders = reply.orders
        } catch { loadError = error.localizedDescription }
    }

    func classDetail(runId: Int) async throws -> ClassDetail {
        let reply: ClassDetailReply = try await API.shared.get("learner/class", query: ["run_id": String(runId)])
        return reply.class
    }

    func markAttendance(runId: Int) async throws -> String {
        let reply: MessageReply = try await API.shared.post("learner/attendance", body: ["run_id": runId])
        return reply.message ?? "You have been marked present."
    }

    func survey(runId: Int) async throws -> Survey {
        let reply: SurveyReply = try await API.shared.get("learner/survey", query: ["run_id": String(runId)])
        return reply.survey
    }

    func submitSurvey(runId: Int, answers: [String: String]) async throws -> String {
        let reply: MessageReply = try await API.shared.post("learner/survey", body: ["run_id": runId, "answers": answers])
        await refreshClasses()
        return reply.message ?? "Thank you for your feedback!"
    }

    func quiz(runId: Int, quizId: Int) async throws -> Quiz {
        let reply: QuizReply = try await API.shared.get("learner/quiz", query: ["run_id": String(runId), "quiz_id": String(quizId)])
        return reply.quiz
    }

    /// `answers` maps a question id to the chosen option index. The site scores and records the attempt.
    func submitQuiz(runId: Int, quizId: Int, answers: [String: Int]) async throws -> QuizResult {
        try await API.shared.post("learner/quiz", body: ["run_id": runId, "quiz_id": quizId, "answers": answers])
    }

    /// Learner and trainer classes of one bucket, soonest first (most recent first for past).
    func items(in bucket: String) -> [ClassItem] {
        func pick(_ r: ClassesReply?) -> [ClassItem] {
            guard let r else { return [] }
            switch bucket {
            case "current": return r.current
            case "upcoming": return r.upcoming
            default: return r.past
            }
        }
        let all = pick(trainerClasses) + pick(classes)
        return bucket == "past"
            ? all.sorted { $0.endDate > $1.endDate }
            : all.sorted { ($0.startDate, $0.startTime) < ($1.startDate, $1.startTime) }
    }

    /// Every class across buckets and roles, for the calendar and reminders.
    var allClasses: [ClassItem] {
        items(in: "current") + items(in: "upcoming") + items(in: "past")
    }
}

/// Public course catalog of this site: fetched feed > on-device cache > bundled snapshot.
@MainActor
final class CatalogStore: ObservableObject {
    @Published private(set) var courses: [Course] = CatalogStore.cached() ?? CatalogStore.bundled()

    var categories: [String] {
        var seen = Set<String>()
        return courses.map(\.category).filter { seen.insert($0).inserted }.sorted { a, b in
            // "Other Courses" always last; the rest alphabetical.
            if a == "Other Courses" { return false }
            if b == "Other Courses" { return true }
            return a < b
        }
    }

    func refresh() async {
        guard let reply: CatalogReply = try? await API.shared.get("catalog"), !reply.courses.isEmpty else { return }
        courses = reply.courses
        if let data = try? JSONEncoder().encode(reply) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("catalog.json")
    }

    private static func decode(_ data: Data) -> [Course]? {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        if let reply = try? d.decode(CatalogReply.self, from: data), !reply.courses.isEmpty { return reply.courses }
        // The cache is written with the default (camelCase) encoder.
        if let reply = try? JSONDecoder().decode(CatalogReply.self, from: data), !reply.courses.isEmpty { return reply.courses }
        return nil
    }

    private static func cached() -> [Course]? {
        (try? Data(contentsOf: cacheURL)).flatMap(decode)
    }

    private static func bundled() -> [Course] {
        guard let url = Bundle.main.url(forResource: "Catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return decode(data) ?? []
    }
}
