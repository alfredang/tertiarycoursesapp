import SwiftUI

// The class page in the website's layout (dashboard "View Course"): a summary card,
// then collapsible sections — E-Attendance, Announcements, Virtual Class Link,
// Courseware, Lesson, Practice Exam, Course Survey and the Course Feedback summary.
// Shapes come from /mobileapi/learner/class and /mobileapi/trainer/class (1.6).

// MARK: - Models

struct Announcement: Decodable, Hashable, Identifiable {
    let id: Int
    let message: String
    let fileName: String?
    let fileUrl: String?
    let postedBy: String?
    let postedAt: String?
}

struct AnnouncementsReply: Decodable {
    let announcements: [Announcement]
    let message: String?
}

struct LessonLink: Decodable, Hashable, Identifiable {
    let type: String
    let title: String
    let url: String
    let quizId: Int?
    let questions: Int?
    let previous: QuizScore?

    var id: String { "\(type)-\(quizId ?? 0)-\(url)-\(title)" }
    var isQuiz: Bool { type == "quiz" && (quizId ?? 0) > 0 }
    var symbol: String {
        switch type {
        case "video": "play.rectangle.fill"
        case "document": "doc.text.fill"
        case "activity": "flask.fill"
        case "quiz": "checklist"
        default: "link"
        }
    }
    var tag: String {
        switch type {
        case "video": "Video"
        case "document": "Document"
        case "activity": "Activity"
        case "quiz": "Quiz"
        default: "Link"
        }
    }
}

struct LessonSubtopic: Decodable, Hashable {
    let title: String
    let links: [LessonLink]
}

struct LessonTopic: Decodable, Hashable {
    let title: String
    let subtopics: [LessonSubtopic]
}

struct PracticeExam: Decodable, Hashable {
    let examCode: String
    let examUrl: String?
    /// The self-register form (pre-filled for a learner). The apps never show it as a QR code:
    /// the QR is on the web class page only.
    let selfRegisterUrl: String
    let open: Bool?
    /// The signed-in person is registered for this class's exam (a trainer is registered
    /// automatically); nil when the exams site could not be reached.
    let registered: Bool?
}

struct FeedbackQuestion: Decodable, Hashable {
    let label: String
    let average: Double?
}

struct FeedbackSummary: Decodable, Hashable {
    let count: Int
    let overall: Double?
    let questions: [FeedbackQuestion]
    let comments: [String]
}

struct SupportInfo: Decodable, Hashable {
    let email: String?
    let phone: String?
    let whatsapp: String?
    let address: String?
}

private struct SupportReply: Decodable { let support: SupportInfo }

/// One class in the Admin home and calendar (/mobileapi/staff/classes).
struct AdminClass: Decodable, Hashable, Identifiable {
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
    let trainer: String
    let learnerCount: Int

    var id: Int { runId }
}

struct AdminKpis: Decodable, Hashable {
    let runningToday: Int
    let next30Days: Int
    let learnersToday: Int
}

struct AdminClassesReply: Decodable {
    let today: String?
    let kpis: AdminKpis?
    let current: [AdminClass]?
    let upcoming: [AdminClass]?
    let classes: [AdminClass]?
}

/// One course in the Developer home (/mobileapi/staff/courses).
struct DevCourse: Decodable, Hashable, Identifiable {
    let id: Int
    let sku: String
    let title: String
    let enabled: Bool
    let upcomingClasses: Int
    let nextClass: String
}

struct DevKpis: Decodable, Hashable {
    let courses: Int
    let withClasses: Int
    let disabled: Int
}

struct DevCoursesReply: Decodable {
    let kpis: DevKpis
    let courses: [DevCourse]
}

// MARK: - API

extension LearnerStore {
    func postAnnouncement(runId: Int, message: String) async throws -> [Announcement] {
        let reply: AnnouncementsReply = try await API.shared.post("trainer/announcement", body: ["run_id": runId, "message": message])
        return reply.announcements
    }

    func deleteAnnouncement(runId: Int, id: Int) async throws -> [Announcement] {
        let reply: AnnouncementsReply = try await API.shared.post("trainer/announcement", body: ["run_id": runId, "delete_id": id])
        return reply.announcements
    }

    func loadSupport() async throws -> SupportInfo {
        let reply: SupportReply = try await API.shared.get("support")
        return reply.support
    }

    func sendSupport(subject: String, message: String) async throws -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let reply: MessageReply = try await API.shared.post("support", body: [
            "subject": subject, "message": message, "app_version": "iOS " + version,
        ])
        return reply.message ?? "Thank you. Your message has been sent."
    }

    func loadAdminClasses(from: String? = nil, to: String? = nil) async throws -> AdminClassesReply {
        var q = ["role": activeRole]
        if let from, let to { q["from"] = from; q["to"] = to }
        return try await API.shared.get("staff/classes", query: q)
    }

    func loadDevCourses() async throws -> DevCoursesReply {
        try await API.shared.get("staff/courses", query: ["role": activeRole])
    }
}

// MARK: - Collapsible section card

/// A website-style section card: a tappable title row with a chevron; the body shows only when open.
struct FoldSection<Content: View>: View {
    let title: String
    let icon: String
    var badge: String? = nil
    @Binding var open: Set<String>
    @ViewBuilder let content: Content

    private var isOpen: Bool { open.contains(title) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    if isOpen { open.remove(title) } else { open.insert(title) }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 26)
                    Text(title).font(.headline).foregroundStyle(.primary)
                    if let badge, !badge.isEmpty {
                        Text(badge)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.accentSoft, in: Capsule())
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("section-\(title)")
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            if isOpen {
                Divider()
                VStack(alignment: .leading, spacing: 10) { content }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

/// A website-style tile inside a section: icon, title, subtitle, optional trailing icon.
struct SectionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    var muted = false
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(muted ? Color.secondary : Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(muted ? Color.secondary : Color.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let trailing {
                Image(systemName: trailing).font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.page, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

// MARK: - Venue

/// The class address; tap to open it in Maps.
struct VenueLink: View {
    let address: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            var c = URLComponents(string: "https://maps.apple.com/")!
            c.queryItems = [URLQueryItem(name: "q", value: address)]
            if let url = c.url { openURL(url) }
        } label: {
            Label {
                Text(address).multilineTextAlignment(.leading).foregroundStyle(.primary)
            } icon: {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.accent)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens in Maps")
    }
}

// MARK: - Sections shared by learner and trainer

struct VirtualClassSection: View {
    let mode: String
    let link: String
    @Binding var open: Set<String>
    @Environment(\.openURL) private var openURL

    var body: some View {
        FoldSection(title: "Virtual Class Link", icon: "video", open: $open) {
            if mode == "Classroom" {
                SectionTile(icon: "video.slash", title: "N/A", subtitle: "This is a physical class — no virtual meeting link.", muted: true)
            } else if let url = URL(string: link), !link.isEmpty {
                Button { openURL(url) } label: {
                    SectionTile(icon: "video.fill", title: "Join Virtual Class", subtitle: link, trailing: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
            } else {
                SectionTile(icon: "video", title: "Not yet configured", subtitle: "No virtual class link has been added for this class yet.", muted: true)
            }
        }
    }
}

struct AnnouncementsSection: View {
    let runId: Int
    @Binding var items: [Announcement]
    let canPost: Bool
    @Binding var open: Set<String>

    @EnvironmentObject private var store: LearnerStore
    @State private var draft = ""
    @State private var posting = false
    @State private var problem: String?
    @State private var confirmDelete: Announcement?

    var body: some View {
        FoldSection(title: "Announcements", icon: "megaphone", badge: items.isEmpty ? nil : "\(items.count)", open: $open) {
            if canPost {
                Text("Post to this class. Every learner sees it on their class page.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Type an announcement, instructions or a list of references…", text: $draft, axis: .vertical)
                    .lineLimit(3...8)
                    .padding(10)
                    .background(Theme.page, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
                    .accessibilityIdentifier("announcementText")
                HStack {
                    if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
                    Spacer()
                    Button {
                        Task { await post() }
                    } label: {
                        HStack(spacing: 6) {
                            if posting { ProgressView().tint(.white) }
                            Text("Post")
                        }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .disabled(posting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !items.isEmpty { Divider() }
            }
            if items.isEmpty {
                Text("No announcements yet.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                AnnouncementRow(item: item, canDelete: canPost) { confirmDelete = item }
                if item != items.last { Divider() }
            }
        }
        .confirmationDialog("Delete this announcement?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let a = confirmDelete { Task { await delete(a) } }
            }
        }
    }

    private func post() async {
        posting = true
        defer { posting = false }
        do {
            items = try await store.postAnnouncement(runId: runId, message: draft)
            draft = ""
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func delete(_ a: Announcement) async {
        do {
            items = try await store.deleteAnnouncement(runId: runId, id: a.id)
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}

struct AnnouncementRow: View {
    let item: Announcement
    let canDelete: Bool
    let onDelete: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text([item.postedBy, item.postedAt].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash").font(.footnote)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete announcement")
                }
            }
            if !item.message.isEmpty {
                Text(LocalizedStringKey(Self.linkified(item.message)))
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let file = item.fileUrl, let url = URL(string: file), !file.isEmpty {
                Button { openURL(url) } label: {
                    Label(item.fileName?.isEmpty == false ? item.fileName! : "Attachment", systemImage: "paperclip")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }

    /// http(s) links become tappable (Markdown), everything else stays plain text.
    static func linkified(_ text: String) -> String {
        var out = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "`", with: "\\`")
        guard let re = try? NSRegularExpression(pattern: #"https?://[^\s<>"')\]]+"#) else { return out }
        let ns = out as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let link = ns.substring(with: m.range).replacingOccurrences(of: "\\_", with: "_").replacingOccurrences(of: "\\*", with: "*")
            result += "[\(link)](\(link))"
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        out = result
        return out
    }
}

/// The course Lesson: topics > sub topics > links, videos and quizzes.
struct LessonSection: View {
    let topics: [LessonTopic]
    let trainer: Bool
    let title: String
    @Binding var open: Set<String>
    /// Learner: open a quiz. Trainer: show its QR code.
    let onQuiz: (LessonLink) -> Void

    @State private var openTopics: Set<Int> = []
    @Environment(\.openURL) private var openURL

    var body: some View {
        FoldSection(title: "Lesson", icon: "book", open: $open) {
            if topics.isEmpty {
                Text("No lesson topics available for this course yet.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(topics.enumerated()), id: \.offset) { i, topic in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.snappy) {
                            if openTopics.contains(i) { openTopics.remove(i) } else { openTopics.insert(i) }
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(topic.title.isEmpty ? "Topic \(i + 1)" : topic.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .rotationEffect(.degrees(openTopics.contains(i) ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if openTopics.contains(i) {
                        ForEach(Array(topic.subtopics.enumerated()), id: \.offset) { _, sub in
                            VStack(alignment: .leading, spacing: 6) {
                                if !sub.title.isEmpty {
                                    Label(sub.title, systemImage: "circle.fill")
                                        .labelStyle(DotLabel())
                                        .font(.subheadline)
                                }
                                ForEach(sub.links) { link in linkRow(link) }
                            }
                            .padding(.leading, 6)
                        }
                    }
                }
                .padding(.vertical, 4)
                if i < topics.count - 1 { Divider() }
            }
        }
    }

    @ViewBuilder private func linkRow(_ link: LessonLink) -> some View {
        Button {
            if link.isQuiz {
                onQuiz(link)
            } else if let url = URL(string: link.url) {
                openURL(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: link.isQuiz && link.previous != nil && !trainer ? "checkmark.circle.fill" : link.symbol)
                    .foregroundStyle(link.isQuiz && link.previous != nil && !trainer ? Theme.success : Theme.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.title).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Text(subtitle(link)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text(action(link)).font(.caption.weight(.semibold)).foregroundStyle(Theme.brand)
            }
            .padding(10)
            .background(Theme.page, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 18)
        .accessibilityIdentifier(link.isQuiz ? "lesson-quiz-\(link.quizId ?? 0)" : "lesson-link")
    }

    private func subtitle(_ l: LessonLink) -> String {
        guard l.isQuiz else { return l.tag }
        let n = l.questions ?? 0
        var s = "Quiz · \(n) question\(n == 1 ? "" : "s")"
        if !trainer, let p = l.previous { s += " · your score \(p.score) / \(p.total)" }
        return s
    }

    private func action(_ l: LessonLink) -> String {
        if l.isQuiz { return trainer ? "Show QR" : (l.previous == nil ? "Start" : "Retake") }
        return l.type == "video" ? "Watch" : "Open"
    }
}

struct DotLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(Theme.accent)
            configuration.title
        }
    }
}

/// Post Course Feedback summary: overall score, a bar per question, then the comments.
struct FeedbackSummaryView: View {
    let summary: FeedbackSummary
    @State private var allComments = false

    private static func score(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v.formatted(.number.precision(.fractionLength(v.rounded() == v ? 0 : 1)))
    }
    private static func tint(_ v: Double?) -> Color {
        guard let v else { return .secondary }
        return v >= 4 ? Theme.success : v >= 3 ? Theme.warning : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 0) {
                    Text(Self.score(summary.overall)).font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.tint(summary.overall))
                    Text("out of 5").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            let v = summary.overall ?? 0
                            Image(systemName: v >= Double(i) ? "star.fill" : v >= Double(i) - 0.5 ? "star.leadinghalf.filled" : "star")
                                .foregroundStyle(.yellow)
                        }
                    }
                    .font(.subheadline)
                    Text("Overall average").font(.subheadline.weight(.semibold))
                    Text("\(summary.count) \(summary.count == 1 ? "response" : "responses")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            ForEach(Array(summary.questions.enumerated()), id: \.offset) { i, q in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(i + 1). \(q.label)").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text("\(Self.score(q.average))/5").font(.subheadline.weight(.bold).monospacedDigit())
                    }
                    ProgressView(value: min(max(q.average ?? 0, 0), 5), total: 5).tint(Self.tint(q.average))
                }
                .accessibilityElement(children: .combine)
            }

            if !summary.comments.isEmpty {
                Text("Comments").font(.subheadline.weight(.semibold)).padding(.top, 4)
                ForEach(Array((allComments ? summary.comments : Array(summary.comments.prefix(3))).enumerated()), id: \.offset) { _, c in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "quote.opening").font(.caption).foregroundStyle(Theme.accent)
                        Text(c).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.page, in: RoundedRectangle(cornerRadius: 10))
                }
                if summary.comments.count > 3 {
                    Button(allComments ? "Show fewer" : "Show all \(summary.comments.count) comments") {
                        withAnimation { allComments.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

// MARK: - Support tab

/// Support: a feedback form emailed to the academy, then the ways to reach it directly.
struct SupportView: View {
    @EnvironmentObject private var store: LearnerStore
    @State private var info: SupportInfo?
    @State private var subject = ""
    @State private var message = ""
    @State private var sending = false
    @State private var notice: String?
    @State private var problem: String?

    private static let fallback = SupportInfo(email: Site.email, phone: Site.phone, whatsapp: Site.whatsAppLabel, address: nil)

    private static func digits(_ s: String) -> String { s.filter(\.isNumber) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Subject", text: $subject).accessibilityIdentifier("supportSubject")
                    TextField("How can we help? Tell us what happened.", text: $message, axis: .vertical)
                        .lineLimit(4...10)
                        .accessibilityIdentifier("supportMessage")
                    Button {
                        Task { await send() }
                    } label: {
                        Text(sending ? "Sending…" : "Send feedback")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .disabled(sending || subject.trimmingCharacters(in: .whitespaces).isEmpty
                              || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("supportSend")
                    if let notice {
                        Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success).font(.subheadline)
                    }
                    if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Your message is emailed to the academy with your name and email, so we can reply.")
                }

                let c = info ?? Self.fallback
                Section("Contact us") {
                    if let email = c.email, !email.isEmpty {
                        ContactRow(icon: "envelope.fill", title: "Email", value: email, url: URL(string: "mailto:" + email))
                    }
                    if let phone = c.phone, !phone.isEmpty {
                        ContactRow(icon: "phone.fill", title: "Tel", value: phone, url: URL(string: "tel:+" + Self.digits(phone)))
                    }
                    if let wa = c.whatsapp, !wa.isEmpty {
                        ContactRow(icon: "message.fill", title: "WhatsApp", value: wa, url: URL(string: "https://wa.me/" + Self.digits(wa)))
                    }
                }
                if let address = c.address, !address.isEmpty {
                    Section("Address") { VenueLink(address: address).font(.subheadline) }
                }
            }
            .navigationTitle("Support")
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
            .scrollDismissesKeyboard(.interactively)
            .task { if info == nil { info = try? await store.loadSupport() } }
        }
    }

    private func send() async {
        notice = nil
        problem = nil
        sending = true
        defer { sending = false }
        do {
            notice = try await store.sendSupport(subject: subject, message: message)
            subject = ""
            message = ""
        } catch {
            problem = error.localizedDescription
        }
    }
}


// MARK: - Practice Exam

/// The Practice Exam section of the class page. No QR code in the apps: the learner (or the
/// trainer, for someone without the app) fills in the self-register form inside the app.
struct PracticeExamBody: View {
    let exam: PracticeExam
    let trainer: Bool
    let openForm: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if exam.registered == true {
                Label(trainer ? "You are registered for the \(exam.examCode) practice exam."
                              : "You are registered for the \(exam.examCode) practice exam. Sign in with your email to start it.",
                      systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.success)
            } else if trainer {
                Text("You are registered for the \(exam.examCode) practice exam automatically. Learners register with the self-register form; the QR code for the class to scan is on the web class page.")
                    .font(.subheadline)
            } else {
                Text("Register for the \(exam.examCode) practice exam on Tertiary Exams. We email you the exam link.")
                    .font(.subheadline)
            }
            if exam.open == false && exam.registered != true {
                Text("Registration opens the day before the class and closes 7 days after it ends.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if exam.registered != true || trainer, exam.open != false, let url = URL(string: exam.selfRegisterUrl) {
                Button { openForm(url) } label: {
                    Label(trainer ? "Open Self-Register Form" : "Register for the Practice Exam",
                          systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .accessibilityIdentifier("practiceExamForm")
            }
            if let site = exam.examUrl, !site.isEmpty, let url = URL(string: site.hasSuffix("/login") ? site : site + "/login") {
                Link(destination: url) {
                    Label("Open Tertiary Exams", systemImage: "arrow.up.right.square")
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }
}
