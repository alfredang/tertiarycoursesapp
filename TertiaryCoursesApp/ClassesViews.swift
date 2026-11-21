import SwiftUI

/// My Classes: current, upcoming and past classes.
struct ClassesView: View {
    @EnvironmentObject private var store: LearnerStore

    enum Bucket: String, CaseIterable, Identifiable {
        case current = "Current"
        case upcoming = "Upcoming"
        case past = "Past"
        var id: String { rawValue }
    }

    @State private var bucket: Bucket = .current
    @State private var chosenDefault = false
    @State private var path: [ClassItem] = []

    private func items(_ b: Bucket) -> [ClassItem] {
        store.items(in: b.rawValue.lowercased())
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let name = store.learner?.firstName, !name.isEmpty {
                        Text("Hi \(name) 👋")
                            .font(.title2.bold())
                    }
                    Picker("Classes", selection: $bucket) {
                        ForEach(Bucket.allCases) { b in
                            Text("\(b.rawValue) (\(items(b).count))").tag(b)
                        }
                    }
                    .pickerStyle(.segmented)

                    if store.classes == nil && store.trainerClasses == nil {
                        if let err = store.loadError {
                            ErrorCard(message: err) { Task { await store.refreshClasses() } }
                        } else {
                            ProgressView("Loading your classes…")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                    } else if items(bucket).isEmpty {
                        ContentUnavailableView {
                            Label(emptyTitle, systemImage: "calendar.badge.clock")
                        } description: {
                            Text(emptyText)
                        }
                        .padding(.top, 30)
                    } else {
                        ForEach(items(bucket)) { item in
                            if item.runId > 0 {
                                NavigationLink(value: item) {
                                    ClassCard(item: item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                ClassCard(item: item)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.page)
            .refreshable { await store.refreshClasses() }
            .navigationTitle("My Classes")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ClassItem.self) { ClassDestination(item: $0) }
            .brandToolbar()
            .onChange(of: store.classes?.today) { _, _ in pickDefaultBucket() }
            .onChange(of: store.trainerClasses?.today) { _, _ in pickDefaultBucket() }
            .onAppear { pickDefaultBucket() }
        }
    }

    /// Open on the most useful tab: today's class, else the next one, else history.
    private func pickDefaultBucket() {
        // A trainer's list is complete only once the classes they teach have loaded too.
        guard !chosenDefault, store.classes != nil, !store.isTrainer || store.trainerClasses != nil else { return }
        chosenDefault = true
        bucket = Bucket.allCases.first { !items($0).isEmpty } ?? .current
        #if DEBUG
        // Screenshot automation: OPEN_BUCKET=current|upcoming|past, OPEN_RUN_ID=<run_id>.
        let env = ProcessInfo.processInfo.environment
        if let b = env["OPEN_BUCKET"], let chosen = Bucket.allCases.first(where: { $0.rawValue.lowercased() == b }) {
            bucket = chosen
        }
        if let id = env["OPEN_RUN_ID"].flatMap(Int.init), let item = store.allClasses.first(where: { $0.runId == id }) {
            path = [item]
        }
        #endif
    }

    private var emptyTitle: String {
        switch bucket {
        case .current: "No class today"
        case .upcoming: "No upcoming classes"
        case .past: "No past classes yet"
        }
    }

    private var emptyText: String {
        switch bucket {
        case .current:
            store.isTrainer
                ? "Classes running now appear here, with attendance and the class materials."
                : "Classes that are running now appear here, with check-in and your materials."
        case .upcoming:
            store.isTrainer
                ? "Classes you are scheduled to teach or attend appear here."
                : "Register for a course on \(Site.websiteLabel) and it will appear here."
        case .past:
            store.isTrainer
                ? "Completed classes you taught or attended appear here."
                : "Completed classes, your feedback and certificates appear here."
        }
    }
}

/// A class opens as the trainer's view or the learner's, by the role it was listed under.
struct ClassDestination: View {
    let item: ClassItem

    var body: some View {
        if item.isTeaching {
            TrainerClassView(runId: item.runId, title: item.title)
        } else {
            ClassDetailView(runId: item.runId, title: item.title)
        }
    }
}

struct ClassCard: View {
    let item: ClassItem
    @EnvironmentObject private var store: LearnerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CourseThumb(url: item.image)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.classId.isEmpty ? item.sku : item.classId)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        if store.isTrainer {
                            StatusChip(text: item.isTeaching ? "Teaching" : "Attending",
                                       color: item.isTeaching ? Theme.accent : .secondary)
                        }
                        if item.isPendingPayment {
                            StatusChip(text: "Pending payment", color: Theme.warning)
                        } else if item.bucket == "current" {
                            StatusChip(text: "In progress", color: Theme.success)
                        }
                    }
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if item.runId > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Label(Fmt.range(item.startDate, item.endDate), systemImage: "calendar")
                if !item.startTime.isEmpty {
                    Label(Fmt.times(item.startTime, item.endTime), systemImage: "clock")
                }
                if !item.mode.isEmpty {
                    Label(item.mode, systemImage: item.mode == "Live Online" ? "video.fill" : "building.2.fill")
                }
                if item.isTeaching {
                    if let n = item.learnerCount {
                        Label("\(n) learner\(n == 1 ? "" : "s")", systemImage: "person.2.fill")
                    }
                } else if !item.trainer.isEmpty {
                    Label(item.trainer, systemImage: "person.fill")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if item.certificate != nil || item.surveySubmitted == true {
                HStack(spacing: 6) {
                    if item.certificate != nil { StatusChip(text: "Certificate issued", color: Theme.accent) }
                    if item.surveySubmitted == true { StatusChip(text: "Feedback done", color: Theme.success) }
                }
            }
            if item.isPendingPayment {
                Text("Your seat is confirmed once payment for order #\(item.orderNo ?? "") is received.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

struct CourseThumb: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.accentSoft)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct StatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct ErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.subheadline)
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Class detail

struct ClassDetailView: View {
    let runId: Int
    let title: String

    @EnvironmentObject private var store: LearnerStore
    @Environment(\.openURL) private var openURL
    @State private var detail: ClassDetail?
    @State private var error: String?
    @State private var checkingIn = false
    @State private var notice: String?
    @State private var doc: DocLink?
    @State private var quiz: QuizSummary?
    @State private var openedQuiz = false
    @State private var showSurvey = ProcessInfo.processInfo.environment["OPEN_SURVEY"] == "1" && Self.debugBuild
    private static var debugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let d = detail {
                    overview(d)
                    attendanceCard(d)
                    materialsCard(d)
                    quizCard(d)
                    surveyCard(d)
                    certificateCard(d)
                    sessionsCard(d)
                } else if let error {
                    ErrorCard(message: error) { Task { await load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(20)
        }
        .background(Theme.page)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .alert("Attendance", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
        .sheet(isPresented: $showSurvey, onDismiss: { Task { await load() } }) {
            SurveyView(runId: runId)
        }
        .sheet(item: $quiz, onDismiss: { Task { await load() } }) { q in
            QuizView(runId: runId, summary: q)
        }
        .documentViewer($doc)
    }

    private func load() async {
        do {
            detail = try await store.classDetail(runId: runId)
            error = nil
            #if DEBUG
            // Screenshot automation: OPEN_DOC=1 opens the first material in the viewer.
            if ProcessInfo.processInfo.environment["OPEN_DOC"] == "1", doc == nil,
               let m = detail?.materials.first, let url = URL(string: m.url) {
                doc = DocLink(title: m.title, url: url)
            }
            // Screenshot automation: OPEN_QUIZ=1 opens the first quiz.
            if ProcessInfo.processInfo.environment["OPEN_QUIZ"] == "1", quiz == nil, !openedQuiz {
                openedQuiz = true
                quiz = detail?.quizzes?.first
            }
            #endif
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func overview(_ d: ClassDetail) -> some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(d.title).font(.title3.bold())
                Text("\(d.classId) · \(d.sku)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Divider()
                Label(Fmt.range(d.startDate, d.endDate), systemImage: "calendar")
                if !d.startTime.isEmpty {
                    Label(Fmt.times(d.startTime, d.endTime), systemImage: "clock")
                }
                Label(d.mode, systemImage: d.mode == "Live Online" ? "video.fill" : "building.2.fill")
                if !d.venue.isEmpty || !d.room.isEmpty {
                    Label([d.room, d.venue].filter { !$0.isEmpty }.joined(separator: "\n"), systemImage: "mappin.and.ellipse")
                        .textSelection(.enabled)
                }
                if !d.trainer.isEmpty {
                    Label("Trainer: \(d.trainer)", systemImage: "person.fill")
                }
                if let url = URL(string: d.virtualLink), !d.virtualLink.isEmpty {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Join Online Class", systemImage: "video.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .padding(.top, 4)
                }
            }
            .font(.subheadline)
        }
    }

    private func attendanceCard(_ d: ClassDetail) -> some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Digital attendance")
                if d.attendance.markedPresent {
                    Label("You're checked in for \(d.attendance.currentSessionLabel).", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                        .font(.subheadline.weight(.semibold))
                } else if d.attendance.open {
                    Text("Check in for \(d.attendance.currentSessionLabel) when you arrive.")
                        .font(.subheadline)
                    Button {
                        Task { await checkIn() }
                    } label: {
                        HStack {
                            if checkingIn { ProgressView().tint(.white) }
                            Label("Check In Now", systemImage: "hand.raised.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .controlSize(.large)
                    .disabled(checkingIn)
                    .accessibilityIdentifier("checkIn")
                } else {
                    Text(d.bucket == "upcoming" ? "Check-in opens on the first day of class." : "Check-in is closed for this class.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Attended \(d.attendance.sessionsPresent) of \(d.attendance.sessionsTotal) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func materialsCard(_ d: ClassDetail) -> some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Class materials")
                    .padding(.bottom, 6)
                if d.materials.isEmpty && d.documents.isEmpty {
                    Text("Your trainer will share the materials for this class here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
                ForEach(d.materials + d.documents) { m in
                    if let url = URL(string: m.url) {
                        MaterialRow(material: m) { openDocument(url, title: m.title, in: $doc) }
                        if m != (d.materials + d.documents).last { Divider() }
                    }
                }
            }
        }
    }

    /// Quizzes the course developer added to the Lesson; hidden when the course has none.
    @ViewBuilder
    private func quizCard(_ d: ClassDetail) -> some View {
        let quizzes = d.quizzes ?? []
        if !quizzes.isEmpty {
            InfoCard {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Quizzes")
                        .padding(.bottom, 6)
                    ForEach(quizzes) { q in
                        Button {
                            quiz = q
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: q.previous == nil ? "checklist" : "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(q.previous == nil ? Theme.brand : Theme.success)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(q.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text(quizSubtitle(q))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(q.previous == nil ? "Start" : "Retake")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.brand)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("quiz-\(q.quizId)")
                        if q != quizzes.last { Divider() }
                    }
                }
            }
        }
    }

    private func quizSubtitle(_ q: QuizSummary) -> String {
        let count = "\(q.questions) question\(q.questions == 1 ? "" : "s")"
        guard let p = q.previous else { return count }
        return "\(count) · your score \(p.score) / \(p.total)"
    }

    private func surveyCard(_ d: ClassDetail) -> some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Course feedback")
                if d.survey.submitted {
                    Label(d.survey.message, systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.success)
                        .font(.subheadline.weight(.semibold))
                } else if let url = URL(string: d.survey.externalUrl), !d.survey.externalUrl.isEmpty {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open Feedback Form", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                } else if d.survey.available {
                    Text("Tell us how the class went — it takes about a minute.")
                        .font(.subheadline)
                    Button {
                        showSurvey = true
                    } label: {
                        Label("Give Feedback", systemImage: "star.bubble.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .controlSize(.large)
                    .accessibilityIdentifier("giveFeedback")
                } else {
                    Text(d.survey.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func certificateCard(_ d: ClassDetail) -> some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Certificate")
                if let cert = d.certificate, let url = URL(string: cert.url) {
                    Label("\(cert.name) · \(cert.certNo)", systemImage: "rosette")
                        .font(.subheadline.weight(.semibold))
                    Button {
                        openDocument(url, title: "Certificate", in: $doc)
                    } label: {
                        Label("View Certificate", systemImage: "doc.richtext").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text(certificateHint(d))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func certificateHint(_ d: ClassDetail) -> String {
        let rule = d.certificateRule.map { " (attendance \($0))" } ?? ""
        return d.bucket == "past"
            ? "Your certificate will appear here once it is issued\(rule)."
            : "Your certificate is issued after the class when attendance requirements are met\(rule)."
    }

    private func sessionsCard(_ d: ClassDetail) -> some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Sessions")
                ForEach(d.sessions) { s in
                    HStack {
                        Text(s.label).font(.subheadline)
                        Spacer()
                        switch s.present {
                        case .some(true):
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                                .accessibilityLabel("Present")
                        case .some(false):
                            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                                .accessibilityLabel("Absent")
                        case .none:
                            Image(systemName: "circle").foregroundStyle(.tertiary)
                                .accessibilityLabel("Not recorded")
                        }
                    }
                }
            }
        }
    }

    private func checkIn() async {
        checkingIn = true
        defer { checkingIn = false }
        do {
            notice = try await store.markAttendance(runId: runId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
        } catch {
            notice = error.localizedDescription
        }
    }
}

// MARK: - Survey

/// The site's in-house course feedback survey, rendered from its live template.
struct SurveyView: View {
    let runId: Int

    @EnvironmentObject private var store: LearnerStore
    @Environment(\.dismiss) private var dismiss
    @State private var survey: Survey?
    @State private var answers: [String: String] = [:]
    @State private var error: String?
    @State private var submitting = false
    @State private var done: String?

    private var missing: [SurveyField] {
        guard let survey else { return [] }
        return survey.sections.flatMap(\.fields).filter {
            $0.required && !$0.readonly && (answers[$0.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let survey {
                    ForEach(survey.sections) { section in
                        Section(section.title) {
                            ForEach(section.fields) { field in
                                fieldView(field)
                            }
                        }
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(.red).font(.footnote) }
                    }
                } else if let error {
                    Section { ErrorCard(message: error) { Task { await load() } } }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(survey?.title ?? "Course Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await submit() } }
                        .disabled(survey == nil || !missing.isEmpty || submitting)
                        .accessibilityIdentifier("submitSurvey")
                }
            }
            .task { await load() }
            .alert("Thank you!", isPresented: Binding(get: { done != nil }, set: { if !$0 { done = nil; dismiss() } })) {
                Button("Done") { dismiss() }
            } message: {
                Text(done ?? "")
            }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func fieldView(_ f: SurveyField) -> some View {
        let binding = Binding(get: { answers[f.id] ?? "" }, set: { answers[f.id] = $0 })
        let label = f.label + (f.required ? " *" : "")
        if f.readonly {
            LabeledContent(f.label, value: f.type == "date" ? Fmt.longDate(f.value) : f.value)
        } else {
            switch f.type {
            case "rating1to5":
                VStack(alignment: .leading, spacing: 8) {
                    Text(label).font(.subheadline)
                    StarRating(value: Binding(get: { Int(answers[f.id] ?? "") ?? 0 }, set: { answers[f.id] = String($0) }))
                }
                .padding(.vertical, 4)
            case "textarea":
                VStack(alignment: .leading, spacing: 6) {
                    Text(label).font(.subheadline)
                    TextField("Your answer", text: binding, axis: .vertical)
                        .lineLimit(3...8)
                }
            case "select":
                Picker(label, selection: binding) {
                    Text("Select…").tag("")
                    ForEach(f.options, id: \.self) { Text($0).tag($0) }
                }
            case "email":
                VStack(alignment: .leading, spacing: 6) {
                    Text(label).font(.subheadline)
                    TextField("you@example.com", text: binding)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text(label).font(.subheadline)
                    TextField("Your answer", text: binding)
                }
            }
        }
    }

    private func load() async {
        do {
            let s = try await store.survey(runId: runId)
            survey = s
            for f in s.sections.flatMap(\.fields) where !f.readonly && answers[f.id] == nil {
                answers[f.id] = f.value
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        do {
            done = try await store.submitSurvey(runId: runId, answers: answers)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Quiz

/// A lesson quiz: pick one option per question, submit, see the score. The site
/// scores the answers and records the attempt against the learner and the class.
struct QuizView: View {
    let runId: Int
    let summary: QuizSummary

    @EnvironmentObject private var store: LearnerStore
    @Environment(\.dismiss) private var dismiss
    @State private var quiz: Quiz?
    @State private var answers: [String: Int] = [:]
    @State private var result: QuizResult?
    @State private var error: String?
    @State private var submitting = false

    private var unanswered: Int {
        guard let quiz else { return 0 }
        return quiz.questions.filter { answers[$0.id] == nil }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                if let quiz {
                    if let result {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your score").font(.subheadline).foregroundStyle(.secondary)
                                Text("\(result.score) / \(result.total)").font(.largeTitle.bold())
                                Text("Your score has been recorded.").font(.footnote).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("quizScore")
                        }
                    }
                    ForEach(Array(quiz.questions.enumerated()), id: \.element.id) { index, q in
                        Section {
                            ForEach(Array(q.options.enumerated()), id: \.offset) { optionIndex, option in
                                optionRow(q, optionIndex, option)
                            }
                        } header: {
                            Text("\(index + 1). \(q.question)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .textCase(nil)
                        }
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(.red).font(.footnote) }
                    }
                    if result != nil {
                        Section {
                            Button("Take the Quiz Again") {
                                answers = [:]
                                result = nil
                            }
                        }
                    } else if unanswered > 0 {
                        Section {
                            Text("Answer every question to submit (\(unanswered) left).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let error {
                    Section { ErrorCard(message: error) { Task { await load() } } }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(quiz?.title ?? summary.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Cancel" : "Done") { dismiss() }
                }
                if result == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(submitting ? "Submitting…" : "Submit") { Task { await submit() } }
                            .disabled(quiz == nil || unanswered > 0 || submitting)
                            .accessibilityIdentifier("submitQuiz")
                    }
                }
            }
            .task { await load() }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func optionRow(_ q: QuizQuestion, _ index: Int, _ option: String) -> some View {
        let chosen = answers[q.id] == index
        let marked = result?.breakdown.first { $0.id == q.id }
        let isCorrect = marked?.correctIndex == index
        let isWrongPick = marked != nil && chosen && !isCorrect
        Button {
            answers[q.id] = index
        } label: {
            HStack(spacing: 12) {
                Image(systemName: marked == nil
                      ? (chosen ? "largecircle.fill.circle" : "circle")
                      : (isCorrect ? "checkmark.circle.fill" : (isWrongPick ? "xmark.circle.fill" : "circle")))
                    .foregroundStyle(marked == nil
                                     ? (chosen ? Theme.brand : Color.secondary)
                                     : (isCorrect ? Theme.success : (isWrongPick ? Color.red : Color.secondary)))
                    .accessibilityHidden(true)
                Text(option)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(result != nil)
        .accessibilityLabel(option)
        .accessibilityValue(marked == nil
                            ? (chosen ? "Selected" : "")
                            : (isCorrect ? "Correct answer" : (isWrongPick ? "Your answer, incorrect" : "")))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func load() async {
        do {
            quiz = try await store.quiz(runId: runId, quizId: summary.quizId)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func submit() async {
        guard let quiz else { return }
        submitting = true
        defer { submitting = false }
        do {
            result = try await store.submitQuiz(runId: runId, quizId: quiz.quizId, answers: answers)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct StarRating: View {
    @Binding var value: Int
    private let labels = ["", "Poor", "Fair", "Good", "Very Good", "Excellent"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    value = i
                } label: {
                    Image(systemName: i <= value ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(i <= value ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i) star\(i == 1 ? "" : "s"), \(labels[i])")
            }
            Text(labels[value]).font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
        }
    }
}
