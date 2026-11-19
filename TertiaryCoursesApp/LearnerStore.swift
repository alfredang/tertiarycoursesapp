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

    var isSignedIn: Bool { learner != nil }
    var isTrainer: Bool { learner?.isTrainer ?? false }
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

    private func finishSignIn(_ reply: AuthReply) throws {
        try Keychain.save(reply.token)
        setLearner(reply.learner)
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

    func refreshClasses() async {
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
        learner = value
        // An older site sends no theme; keep the choice made on this device.
        if value.theme != nil { Appearance.apply(value.themeChoice) }
    }

    /// Saves the profile on the site. The appearance is applied at once, and kept
    /// on this device even when the site cannot store it yet.
    func updateProfile(firstName: String, lastName: String, phone: String, theme: ThemeChoice) async throws -> String {
        Appearance.apply(theme)
        do {
            let reply: ProfileReply = try await API.shared.post("profile", body: [
                "first_name": firstName, "last_name": lastName, "phone": phone, "theme": theme.rawValue,
            ])
            learner = reply.learner
            if reply.learner.theme != nil { Appearance.apply(reply.learner.themeChoice) }
            return reply.message ?? "Profile updated."
        } catch let error as APIError where error.status == 404 {
            throw APIError(message: "Your appearance is saved on this device. Editing your name and phone will be available shortly.", status: 404)
        }
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
