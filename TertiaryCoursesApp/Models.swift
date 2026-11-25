import Foundation

// Shapes of the site's learner API (MMD_MobileApi). JSON keys are snake_case;
// the decoder converts them, so `image_url` arrives as `imageUrl`.

struct Learner: Decodable, Hashable {
    let email: String
    let firstName: String
    let lastName: String
    let fullName: String
    // Added in 1.4; absent on an older site.
    let phone: String?
    let theme: String?
    let roles: [String]?
    /// Unix time the profile picture was last set; nil when there is none.
    let avatarVersion: Int?
    /// Trainers and staff only; empty when not set.
    let linkedinUrl: String?
    /// "", Employed, Unemployed or Looking for Job.
    let employmentStatus: String?

    var isTrainer: Bool { roles?.contains("trainer") ?? false }
    var themeChoice: ThemeChoice { ThemeChoice(rawValue: theme ?? "") ?? .system }
}

/// The account's saved appearance; the app follows it.
enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

struct ProfileReply: Decodable {
    let learner: Learner
    let message: String?
}

struct SiteInfo: Decodable, Hashable {
    let country: String
    let name: String
    let websiteUrl: String
    let currency: String
    let phone: String
    let email: String
    let academy: String
    let priceNote: String
}

struct AuthReply: Decodable {
    let token: String
    let learner: Learner
    let site: SiteInfo?
}

struct MeReply: Decodable {
    let learner: Learner
    let site: SiteInfo?
}

struct MessageReply: Decodable {
    let message: String?
}

// MARK: Catalog

/// A public non-WSQ course from `/mobileapi/catalog`.
struct Course: Identifiable, Hashable, Codable {
    let id: Int
    let sku: String
    let title: String
    let summary: String
    let category: String
    let duration: String
    let price: Double
    let currency: String
    let url: String
    let imageUrl: String

    var pageURL: URL? { URL(string: url) }
    var image: URL? { imageUrl.isEmpty ? nil : URL(string: imageUrl) }

    var searchIndex: String { [sku, title, category, summary].joined(separator: " ") }
}

struct CatalogReply: Codable {
    let courses: [Course]
}

// MARK: Classes

struct CertificateInfo: Decodable, Hashable, Identifiable {
    let runId: Int
    let classId: String
    let sku: String
    let title: String
    let startDate: String
    let endDate: String
    let certNo: String
    let issuedOn: String
    let name: String
    let url: String

    var id: String { certNo.isEmpty ? "\(runId)" : certNo }
}

/// A class in My Classes. `runId` is 0 for a registration still awaiting payment.
struct ClassItem: Decodable, Hashable, Identifiable {
    let runId: Int
    let classId: String
    let productId: Int
    let sku: String
    let title: String
    let startDate: String
    let endDate: String
    let startTime: String
    let endTime: String
    let mode: String
    let venue: String
    let room: String
    let virtualLink: String
    let trainer: String
    let status: String
    let orderNo: String?
    let bucket: String
    let days: [String]?
    let imageUrl: String?
    let certificate: CertificateInfo?
    let surveySubmitted: Bool?
    /// "learner" or "trainer"; absent on an older site (= learner).
    let role: String?
    let learnerCount: Int?

    var isTeaching: Bool { role == "trainer" }
    var id: String { runId > 0 ? "run-\(runId)-\(role ?? "learner")" : "order-\(orderNo ?? "")-\(sku)-\(startDate)" }
    var isPendingPayment: Bool { status == "pending_payment" }
    var image: URL? { (imageUrl ?? "").isEmpty ? nil : URL(string: imageUrl ?? "") }
    /// Actual class dates; falls back to the start…end span when the site doesn't list them.
    var classDays: [String] {
        if let days, !days.isEmpty { return days }
        guard let s = Fmt.date(startDate) else { return [] }
        let e = Fmt.date(endDate) ?? s
        var out: [String] = []
        var d = s
        while d <= e && out.count < 14 {
            out.append(Fmt.ymd(d))
            d = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }
}

struct ClassesReply: Decodable {
    let today: String
    let current: [ClassItem]
    let upcoming: [ClassItem]
    let past: [ClassItem]
}

struct ClassSession: Decodable, Hashable, Identifiable {
    let key: String
    let day: Int
    let part: String
    let date: String
    let label: String
    let present: Bool?

    var id: String { key }
}

struct AttendanceState: Decodable, Hashable {
    let open: Bool
    let currentSession: String
    let currentSessionLabel: String
    let markedPresent: Bool
    /// The learner has signed (finger signature) for the current session; nil before app 1.5's API.
    let signed: Bool?
    let sessionsPresent: Int
    let sessionsTotal: Int
}

struct Material: Decodable, Hashable, Identifiable {
    let key: String?
    let title: String
    let url: String

    var id: String { (key ?? "") + url }
}

struct SurveyState: Decodable, Hashable {
    let available: Bool
    let submitted: Bool
    let externalUrl: String
    let message: String
}

struct ClassDetail: Decodable, Hashable {
    let runId: Int
    let classId: String
    let sku: String
    let title: String
    let startDate: String
    let endDate: String
    let startTime: String
    let endTime: String
    let mode: String
    let venue: String
    let room: String
    let virtualLink: String
    let trainer: String
    let bucket: String
    let imageUrl: String?
    let sessions: [ClassSession]
    let attendance: AttendanceState
    let materials: [Material]
    let documents: [Material]
    let survey: SurveyState
    let certificate: CertificateInfo?
    let certificateRule: String?
    /// Lesson quizzes of the class's course (absent on a site that predates them).
    let quizzes: [QuizSummary]?
    // 1.6: the website's class page sections.
    let announcements: [Announcement]?
    let lesson: [LessonTopic]?
    /// The course's practice exam, opened with the self-register form (absent before 1.6.1).
    let practiceExam: PracticeExam?
}

struct ClassDetailReply: Decodable {
    let `class`: ClassDetail
}

// MARK: Trainer

struct TrainerSession: Decodable, Hashable, Identifiable {
    let key: String
    let day: Int?
    let part: String?
    let date: String?
    let label: String

    var id: String { key }
}

struct RosterEntry: Decodable, Hashable, Identifiable {
    let name: String
    let email: String
    let phone: String?
    let walkin: Bool?
    let present: [String]?
    /// Session keys this learner has signed with a finger.
    let signed: [String]?

    var id: String { email }
}

/// One class the signed-in trainer teaches, from `/mobileapi/trainer/class`.
struct TrainerClassDetail: Decodable, Hashable {
    let runId: Int
    let classId: String
    let sku: String
    let title: String
    let startDate: String
    let endDate: String
    let startTime: String
    let endTime: String
    let mode: String
    let venue: String
    let room: String
    let virtualLink: String
    let trainer: String
    let bucket: String
    let imageUrl: String?
    let sessions: [TrainerSession]
    let currentSession: String?
    let currentSessionLabel: String?
    let attendanceOpen: Bool?
    let checkinUrl: String?
    let roster: [RosterEntry]
    /// Session keys the trainer has signed for.
    let trainerSigned: [String]?
    let materials: [Material]
    let documents: [Material]?
    let surveyResponses: Int?
    /// The course survey link the trainer shows the class.
    let feedbackUrl: String?
    // 1.6: the website's class page sections.
    let announcements: [Announcement]?
    let lesson: [LessonTopic]?
    let practiceExam: PracticeExam?
    let feedbackSummary: FeedbackSummary?
}

struct TrainerClassReply: Decodable {
    let `class`: TrainerClassDetail
}

// MARK: Survey

struct SurveyField: Decodable, Hashable, Identifiable {
    let id: String
    let label: String
    let type: String
    let required: Bool
    let readonly: Bool
    let options: [String]
    let value: String
}

struct SurveySection: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let fields: [SurveyField]
}

struct Survey: Decodable, Hashable {
    let title: String
    let state: SurveyState
    let sections: [SurveySection]
}

struct SurveyReply: Decodable {
    let survey: Survey
}

// MARK: Lesson quizzes

struct QuizScore: Decodable, Hashable {
    let score: Int
    let total: Int
}

/// A quiz listed on the class page, with the learner's latest score.
struct QuizSummary: Decodable, Hashable, Identifiable {
    let quizId: Int
    let title: String
    let questions: Int
    let previous: QuizScore?

    var id: Int { quizId }
}

struct QuizQuestion: Decodable, Hashable, Identifiable {
    let id: String
    let question: String
    let options: [String]
}

/// The questions of one quiz. The correct answers stay on the server until it is submitted.
struct Quiz: Decodable, Hashable {
    let quizId: Int
    let title: String
    let questions: [QuizQuestion]
}

struct QuizReply: Decodable {
    let quiz: Quiz
    let previous: QuizScore?
}

struct QuizAnswerResult: Decodable, Hashable {
    let id: String
    let correct: Bool
    let correctIndex: Int
    let selectedIndex: Int?
}

struct QuizResult: Decodable, Hashable {
    let score: Int
    let total: Int
    let breakdown: [QuizAnswerResult]
}

// MARK: Certificates & billing

struct CertificatesReply: Decodable {
    let certificates: [CertificateInfo]
}

struct OrderLine: Decodable, Hashable {
    let title: String
    let sku: String
    let qty: Double
    let amount: Double
    let classDate: String
    let classTime: String
}

struct Order: Decodable, Hashable, Identifiable {
    let orderNo: String
    let date: String
    let status: String
    let statusLabel: String
    let total: Double
    let paid: Double
    let refunded: Double
    let currency: String
    let paymentMethod: String
    let invoices: [String]
    let items: [OrderLine]

    var id: String { orderNo }
}

struct BillingReply: Decodable {
    let orders: [Order]
}

// MARK: Formatting

enum Fmt {
    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ ymd: String) -> Date? { Self.ymd.date(from: ymd) }
    static func ymd(_ date: Date) -> String { Self.ymd.string(from: date) }

    /// "Tue 4 Nov 2026"
    static func longDate(_ ymd: String) -> String {
        guard let d = date(ymd) else { return "Date to be confirmed" }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    /// "4 Nov" / "4 – 6 Nov 2026"
    static func range(_ start: String, _ end: String) -> String {
        guard let s = date(start) else { return "Date to be confirmed" }
        guard let e = date(end), end != start else { return longDate(start) }
        return s.formatted(.dateTime.day().month(.abbreviated)) + " – " + e.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "09:30" → "9:30 am"
    static func time(_ hm: String) -> String {
        let parts = hm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return hm }
        let h12 = parts[0] % 12 == 0 ? 12 : parts[0] % 12
        return String(format: "%d:%02d %@", h12, parts[1], parts[0] < 12 ? "am" : "pm")
    }

    static func times(_ start: String, _ end: String) -> String {
        if start.isEmpty { return "" }
        return end.isEmpty ? time(start) : "\(time(start)) – \(time(end))"
    }

    static func money(_ amount: Double, _ code: String) -> String {
        amount.formatted(.currency(code: code.isEmpty ? Site.currency : code).precision(.fractionLength(amount.rounded() == amount ? 0 : 2)))
    }
}


// MARK: - Trainer payout and training hours

struct Payout: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let courseCode: String
    let learners: Int?
    let amount: Double
    let paymentDate: String
    let startDate: String
    let endDate: String
}

struct PayoutsReply: Decodable {
    /// False when this site has no payout records to show (or they cannot be reached).
    let available: Bool
    let payouts: [Payout]
    let total: Double
    let currency: String
}

struct HoursMonth: Decodable, Hashable, Identifiable {
    let month: String   // "2026-11"
    let hours: Double
    var id: String { month }
}

struct HoursClass: Decodable, Hashable, Identifiable {
    let runId: Int
    let title: String
    let sku: String
    let startDate: String
    let endDate: String
    let days: Int
    let hours: Double
    var id: Int { runId }
}

struct TrainingHoursReply: Decodable {
    let totalHours: Double
    let months: [HoursMonth]
    let classes: [HoursClass]
}

extension Fmt {
    /// "2026-11" → "November 2026"
    static func month(_ ym: String) -> String {
        guard let d = date(ym + "-01") else { return ym }
        return d.formatted(.dateTime.month(.wide).year())
    }

    /// 16.0 → "16 h", 7.5 → "7.5 h"
    static func hours(_ h: Double) -> String {
        (h == h.rounded() ? String(Int(h)) : String(format: "%.1f", h)) + " h"
    }
}


// MARK: - Staff dashboard (cards and lists decided by the server)

struct StaffCard: Decodable, Hashable, Identifiable {
    let title: String
    let value: String
    let icon: String
    let tone: String
    var id: String { title }
}

struct StaffRow: Decodable, Hashable {
    let title: String
    let subtitle: String
    let value: String
}

struct StaffList: Decodable, Hashable, Identifiable {
    let title: String
    let rows: [StaffRow]
    var id: String { title }
}

struct StaffDashboard: Decodable {
    let role: String
    let title: String
    let cards: [StaffCard]
    let lists: [StaffList]
    let updatedAt: String
}
