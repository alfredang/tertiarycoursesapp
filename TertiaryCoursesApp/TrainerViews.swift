import CoreImage.CIFilterBuiltins
import SwiftUI
import PhotosUI
#if canImport(ImagePlayground)
import ImagePlayground
#endif

/// A class the signed-in trainer teaches: overview, materials and attendance.
struct TrainerClassView: View {
    let runId: Int
    let title: String

    @EnvironmentObject private var store: LearnerStore
    @State private var detail: TrainerClassDetail?
    @State private var error: String?
    @State private var session = ""
    /// Emails marked present for the chosen session, as edited on screen.
    @State private var present: Set<String> = []
    @State private var dirty = false
    @State private var saving = false
    @State private var notice: String?
    @State private var showSign = false
    @State private var doc: DocLink?

    /// Sections the trainer has opened; every section starts collapsed, like the website's cards.
    @State private var open: Set<String> = []
    @State private var announcements: [Announcement] = []
    @State private var quizQR: SurveyLink?

    // Same sections, names and order as the class page on the website (trainer view).
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let d = detail {
                    overview(d)
                    FoldSection(title: "E-Attendance", icon: "checklist.checked", open: $open) { attendanceBody(d) }
                    AnnouncementsSection(runId: runId, items: $announcements, canPost: true, open: $open)
                    VirtualClassSection(mode: d.mode, link: d.virtualLink, open: $open)
                    FoldSection(title: "Courseware", icon: "folder", open: $open) { materialsBody(d) }
                    LessonSection(topics: d.lesson ?? [], trainer: true, title: d.title, open: $open) { link in
                        if !link.url.isEmpty {
                            quizQR = SurveyLink(title: link.title, url: link.url,
                                                hint: "Learners scan this to take the quiz. Their scores are saved to this class.")
                        }
                    }
                    if let pe = d.practiceExam {
                        FoldSection(title: "Practice Exam", icon: "graduationcap", badge: pe.examCode, open: $open) { practiceExamBody(pe) }
                    }
                    FoldSection(title: "Course Feedback", icon: "checklist", open: $open) { feedbackLinkBody(d) }
                    FoldSection(title: "Course Feedback Summary", icon: "chart.bar", open: $open) { feedbackBody(d) }
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
        .pullToRefresh { await load() }
        .task { await load() }
        .documentViewer($doc)
        .sheet(isPresented: $showSign, onDismiss: { Task { await load() } }) {
            if let d = detail { signSheet(d) }
        }
        .sheet(item: $quizQR) { s in
            CheckInQRView(link: s.url, title: detail?.title ?? "", sessionLabel: s.title,
                          heading: s.heading, hint: s.hint, shareLabel: s.shareLabel)
        }
        .alert("Attendance", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private func load() async {
        do {
            let d = try await store.trainerClass(runId: runId)
            if detail == nil, d.bucket == "current" { open.insert("E-Attendance") }
            detail = d
            announcements = d.announcements ?? []
            error = nil
            if session.isEmpty || !d.sessions.contains(where: { $0.key == session }) {
                session = (d.currentSession ?? "").isEmpty ? (d.sessions.first?.key ?? "") : (d.currentSession ?? "")
            }
            resetMarks(d)
            #if DEBUG
            // Screenshot automation: OPEN_DOC=1 opens the first material, OPEN_SIGN=1 the signature dialog.
            let env = ProcessInfo.processInfo.environment
            if env["OPEN_DOC"] == "1", doc == nil, let m = d.materials.first, let url = URL(string: m.url) {
                doc = DocLink(title: m.title, url: url)
            }
            if env["OPEN_SIGN"] == "1" { showSign = true }
            if env["OPEN_SECTIONS"] == "1" {
                open = ["E-Attendance", "Announcements", "Virtual Class Link", "Courseware", "Lesson", "Practice Exam", "Course Feedback", "Course Feedback Summary"]
            }
            if let one = env["OPEN_SECTION"] { open = [one] }
            if env["OPEN_FEEDBACK_QR"] == "1", let link = d.feedbackUrl, !link.isEmpty {
                quizQR = feedbackQR(d, link)
            }
            #endif
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resetMarks(_ d: TrainerClassDetail) {
        present = Set(d.roster.filter { ($0.present ?? []).contains(session) }.map(\.email))
        dirty = false
    }

    private func overview(_ d: TrainerClassDetail) -> some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(d.title).font(.title3.bold())
                Text([d.sku, d.classId].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    StatusChip(text: d.mode == "Classroom" || d.mode.isEmpty ? "Physical" : d.mode, color: Theme.accent)
                    StatusChip(text: "Teaching", color: Theme.accent)
                    if d.bucket == "current" { StatusChip(text: "In progress", color: Theme.success) }
                }
                Label(Fmt.range(d.startDate, d.endDate), systemImage: "calendar")
                if !d.startTime.isEmpty {
                    Label(Fmt.times(d.startTime, d.endTime), systemImage: "clock")
                }
                if !d.venue.isEmpty { VenueLink(address: d.venue) }
                Label("\(d.roster.count) learner\(d.roster.count == 1 ? "" : "s")", systemImage: "person.2.fill")
                if let url = URL(string: d.virtualLink), !d.virtualLink.isEmpty {
                    Button {
                        UIApplication.shared.open(url)
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

    private func attendanceBody(_ d: TrainerClassDetail) -> some View {
        let open = d.attendanceOpen ?? false
        return Group {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Take attendance").font(.subheadline.weight(.semibold))
                    Spacer()
                    if !d.roster.isEmpty {
                        Text("\(present.count) of \(d.roster.count) present")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.success)
                    }
                }
                if d.sessions.count > 1 {
                    Picker("Session", selection: $session) {
                        ForEach(d.sessions) { s in
                            Text(s.label + (s.key == d.currentSession ? " (now)" : "")).tag(s.key)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: session) { _, _ in resetMarks(d) }
                } else if let only = d.sessions.first {
                    Text(only.label).font(.subheadline.weight(.semibold))
                }

                if !open {
                    Text(d.bucket == "upcoming"
                         ? "Attendance opens on the first day of class."
                         : "Attendance is closed for this class. Use \(Site.websiteLabel) to correct a finished class.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if d.roster.isEmpty {
                    Text("No learners are on this class roster yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(d.roster) { r in
                            Toggle(isOn: Binding(
                                get: { present.contains(r.email) },
                                set: { on in
                                    if on { present.insert(r.email) } else { present.remove(r.email) }
                                    dirty = true
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(r.name.isEmpty ? r.email : r.name)
                                            .font(.subheadline.weight(.medium))
                                        if (r.signed ?? []).contains(session) {
                                            Image(systemName: "signature")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(Theme.success)
                                                .accessibilityLabel("Signed")
                                        }
                                    }
                                    Text(r.email + ((r.walkin ?? false) ? " · walk-in" : ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .tint(Theme.success)
                            .disabled(!open || saving)
                            .padding(.vertical, 8)
                            if r != d.roster.last { Divider() }
                        }
                    }
                }

                if open {
                    if !d.roster.isEmpty {
                        HStack {
                            Button("Mark all present") {
                                present = Set(d.roster.map(\.email))
                                dirty = true
                            }
                            .font(.footnote.weight(.semibold))
                            Spacer()
                        }
                        Button {
                            Task { await save(d) }
                        } label: {
                            HStack {
                                if saving { ProgressView().tint(.white) }
                                Label("Save Attendance", systemImage: "checkmark.circle.fill")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brand)
                        .controlSize(.large)
                        .disabled(saving || !dirty || session.isEmpty)
                        .accessibilityIdentifier("saveAttendance")
                    }
                    if !session.isEmpty {
                        if (d.trainerSigned ?? []).contains(session) {
                            Label("You have signed for this session.", systemImage: "signature")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.success)
                        }
                        Button {
                            showSign = true
                        } label: {
                            Label("Sign Attendance", systemImage: "signature").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("signAttendance")
                        Text("You sign for the session, or hand your phone to a learner to sign. A learner who signs is marked present.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The signature dialog for the chosen session: the trainer, then every learner on the roster.
    private func signSheet(_ d: TrainerClassDetail) -> some View {
        let key = session
        let label = d.sessions.first { $0.key == key }?.label ?? ""
        var signers = [Signer(id: "trainer", name: "You (trainer)", signed: (d.trainerSigned ?? []).contains(key))]
        signers += d.roster.map { Signer(id: $0.email, name: $0.name.isEmpty ? $0.email : $0.name, signed: ($0.signed ?? []).contains(key)) }
        return SignatureSheet(title: d.title, sessionLabel: label, signers: signers,
                              hint: "Choose who is signing, then sign with a finger in the box.",
                              closeOnSuccess: false) { signer, png in
            try await store.signAttendance(runId: runId, sessionKey: key, signer: signer.id, signature: png)
        }
    }

    @ViewBuilder
    private func materialsBody(_ d: TrainerClassDetail) -> some View {
        let all = d.materials + (d.documents ?? [])
        if all.isEmpty {
            Text("No materials are linked to this course yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        VStack(spacing: 0) {
            ForEach(all) { m in
                if let url = URL(string: m.url) {
                    MaterialRow(material: m) { openDocument(url, title: m.title, in: $doc) }
                    if m != all.last { Divider() }
                }
            }
        }
    }

    private func practiceExamBody(_ pe: PracticeExam) -> some View {
        PracticeExamBody(exam: pe, trainer: true) { doc = DocLink(title: "\(pe.examCode) Practice Exam", url: $0) }
    }

    /// Course Feedback, as on the website's class page: the QR of the class's feedback form
    /// (the TMS form for a class run from the TMS), its link, and the course code and run id.
    @ViewBuilder
    private func feedbackLinkBody(_ d: TrainerClassDetail) -> some View {
        if let link = d.feedbackUrl, !link.isEmpty {
            Button {
                quizQR = feedbackQR(d, link)
            } label: {
                SectionTile(icon: "qrcode", title: "Show Course Feedback QR", subtitle: link, trailing: "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("showFeedbackQR")
            if let url = URL(string: link) {
                Button { UIApplication.shared.open(url) } label: {
                    Label("Open Link", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Text("Course Code: \(d.sku)   ·   Course Run ID: \(d.classId)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else {
            SectionTile(icon: "qrcode", title: "Not available yet",
                        subtitle: "The feedback form has not been set up for this class yet.", muted: true)
        }
    }

    private func feedbackQR(_ d: TrainerClassDetail, _ link: String) -> SurveyLink {
        SurveyLink(title: "Course Code: \(d.sku) · Course Run ID: \(d.classId)", url: link,
                   hint: "Learners scan this to share their feedback on the class.",
                   heading: "Course Feedback", shareLabel: "Share Feedback Link")
    }

    @ViewBuilder
    private func feedbackBody(_ d: TrainerClassDetail) -> some View {
        if let summary = d.feedbackSummary, summary.count > 0 {
            FeedbackSummaryView(summary: summary)
        } else {
            let n = d.surveyResponses ?? 0
            Text(n > 0 ? "\(n) response\(n == 1 ? "" : "s") received." : "No feedback yet for this class.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Learners fill in the course survey in this app from the first day of class.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func save(_ d: TrainerClassDetail) async {
        saving = true
        defer { saving = false }
        let records: [[String: Any]] = d.roster.map {
            ["email": $0.email, "name": $0.name, "present": present.contains($0.email)]
        }
        do {
            notice = try await store.saveAttendance(runId: runId, sessionKey: session, records: records)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
        } catch {
            notice = error.localizedDescription
        }
    }
}

/// A survey the trainer shows the class as a QR code.
struct SurveyLink: Identifiable {
    let title: String
    let url: String
    let hint: String
    var heading = "Quiz QR"
    var shareLabel = "Share Quiz Link"
    var id: String { url }
}

/// One material or document row; opens in the in-app viewer.
struct MaterialRow: View {
    let material: Material
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack {
                Label(material.title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch material.key {
        case "learner_slides_url", "trainer_slides_url": "rectangle.on.rectangle.angled"
        case "learner_guide_url": "book.fill"
        case "lesson_plan_url": "list.bullet.rectangle"
        case "lab_url", "lab_simulator_url": "flask.fill"
        case "practice_exam_url": "checklist"
        case "facilitator_guide_url": "person.crop.rectangle.fill"
        case "assessment_plan_url": "doc.text.magnifyingglass"
        default: "doc.fill"
        }
    }
}

/// The current session's check-in link as a QR code for learners to scan.
struct CheckInQRView: View {
    let link: String
    let title: String
    let sessionLabel: String
    var heading = "Check-in QR"
    var hint = "Learners scan this with their phone camera to check in to this session."
    var shareLabel = "Share Check-in Link"

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if !sessionLabel.isEmpty {
                    Text(sessionLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let image = Self.qr(link) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                        // A QR code must stay dark-on-white to scan, in either theme.
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(maxWidth: 320)
                        .accessibilityLabel("\(heading) code")
                }
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let url = URL(string: link) {
                    ShareLink(item: url) {
                        Label(shareLabel, systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Theme.page)
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Theme.accent)
    }

    static func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Profile sections (the top of the Account page)

/// A trainer's certification as edited in the form.
struct CertDraft: Identifiable {
    let id = UUID()
    var name = ""
    var issuer = ""
    var year = ""
}

struct ProfileSections: View {
    @EnvironmentObject private var store: LearnerStore
    @State private var fullName = ""
    @State private var phone = ""
    @State private var linkedin = ""
    @State private var employment = ""
    @State private var theme: ThemeChoice = Appearance.cached
    @State private var loaded = false
    @State private var saving = false
    @State private var message: String?
    @State private var saved = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPlayground = false
    @State private var avatarBusy = false
    @State private var avatarError: String?
    @State private var certs: [CertDraft] = []
    @State private var certsLoaded = false

    private var playgroundAvailable: Bool {
        #if canImport(ImagePlayground)
        if #available(iOS 18.2, *) { return ProfileSections.supportsPlayground }
        #endif
        return false
    }

    #if canImport(ImagePlayground)
    @available(iOS 18.2, *)
    private static var supportsPlayground: Bool { ImagePlaygroundViewController.isAvailable }
    #else
    private static var supportsPlayground: Bool { false }
    #endif

    @State private var showPhotoPicker = false

    /// Trainer on the website, whatever view is showing.
    private var isRealTrainer: Bool { store.learner?.isTrainer ?? false }
    private var isStaffOrTrainer: Bool { isRealTrainer || store.availableRoles.contains { LearnerStore.staffRoleNames[$0] != nil } }

    /// Short codes of the trainer qualifications on the certifications list.
    private var badges: [String] {
        TrainerBadge.all.filter { b in certs.contains { b.matches($0.name) } }.map(\.code)
    }

    private static func digits(_ phone: String, plus: Bool = false) -> String {
        let d = phone.filter(\.isNumber)
        return (plus && phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : "") + d
    }

    /// wa.me needs the country code: a bare 8-digit Singapore number gets 65.
    private static func whatsApp(_ phone: String) -> String {
        let d = digits(phone)
        return (d.count == 8 && Site.code == "SG") ? "65" + d : d
    }

    private func upload(_ image: UIImage) {
        avatarBusy = true
        Task {
            do { try await store.setAvatar(image) } catch { avatarError = error.localizedDescription }
            avatarBusy = false
        }
    }

    var body: some View {
        Group {
            // Who you are: picture, name, roles, trainer badges and contact details.
            Section {
                VStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(image: store.avatar, name: store.learner?.fullName ?? "", size: 104)
                            .overlay { if avatarBusy { ProgressView().padding(30).background(.ultraThinMaterial, in: Circle()) } }
                        Menu {
                            Button { showPhotoPicker = true } label: { Label("Choose Photo", systemImage: "photo") }
                            if playgroundAvailable {
                                Button { showPlayground = true } label: { Label("Create with Apple Intelligence", systemImage: "apple.intelligence") }
                            }
                            if store.avatar != nil {
                                Button(role: .destructive) { Task { try? await store.removeAvatar() } } label: {
                                    Label("Remove Picture", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Theme.brand, in: Circle())
                                .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                        }
                        .accessibilityLabel("Change picture")
                        .accessibilityIdentifier("changePicture")
                    }
                    Text(store.learner?.fullName.isEmpty == false ? store.learner!.fullName : "My account")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    StatusChip(text: LearnerStore.roleName(store.activeRole), color: Theme.accent)
                    if !badges.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(badges, id: \.self) { badge in
                                Label(badge, systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(Theme.success)
                                    .background(Theme.success.opacity(0.12), in: Capsule())
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Qualifications: " + badges.joined(separator: ", "))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section("Contact") {
                ContactRow(icon: "envelope.fill", title: "Email", value: store.learner?.email ?? "",
                           url: URL(string: "mailto:" + (store.learner?.email ?? "")))
                if let p = store.learner?.phone, !p.isEmpty {
                    ContactRow(icon: "phone.fill", title: "Phone", value: p, url: URL(string: "tel:" + Self.digits(p, plus: true)))
                    ContactRow(icon: "message.fill", title: "WhatsApp", value: p, url: URL(string: "https://wa.me/" + Self.whatsApp(p)))
                }
                if let link = store.learner?.linkedinUrl, !link.isEmpty, let url = URL(string: link) {
                    ContactRow(icon: "link", title: "LinkedIn", value: link.replacingOccurrences(of: "https://", with: ""), url: url)
                }
            }
            Section("Name") {
                TextField("Name", text: $fullName)
                    .textContentType(.name)
            }
            Section("Employment status") {
                Picker("Employment status", selection: $employment) {
                    Text("Not set").tag("")
                    Text("Employed").tag("Employed")
                    Text("Unemployed").tag("Unemployed")
                    Text("Looking for Job").tag("Looking for Job")
                }
            }
            Section {
                TextField("Phone", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                if isStaffOrTrainer {
                    TextField("LinkedIn profile link", text: $linkedin)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("linkedinField")
                }
            } header: {
                Text("Edit contact")
            } footer: {
                Text("Your phone number is also used for WhatsApp. Your sign-in email is \(store.learner?.email ?? ""); contact us to change it.")
            }
            if isRealTrainer {
                Section {
                    ForEach($certs) { $c in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Certification", text: $c.name)
                            HStack {
                                TextField("Issuer", text: $c.issuer)
                                TextField("Year", text: $c.year)
                                    .keyboardType(.numberPad)
                                    .frame(width: 64)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { certs.remove(atOffsets: $0) }
                    Button { certs.append(CertDraft()) } label: {
                        Label("Add Certification", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("addCertification")
                    // One-tap trainer qualifications that are not on the list yet.
                    let missing = TrainerBadge.all.filter { b in !badges.contains(b.code) }
                    if !missing.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick add")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(missing, id: \.code) { b in
                                        Button {
                                            certs.append(CertDraft(name: b.name, issuer: b.issuer))
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "plus")
                                                Text(b.code)
                                            }
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                            .fixedSize()
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(Theme.accentSoft, in: Capsule())
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundStyle(Theme.accent)
                                        .accessibilityLabel("Add \(b.name)")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Certifications")
                } footer: {
                    Text("Trainer qualifications such as ACLP and DDDLP show as badges under your name. Saved with Save Changes and shared with the web app.")
                }
            }
            Section {
                Picker("Appearance", selection: $theme) {
                    ForEach(ThemeChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("themePicker")
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your iPhone's light or dark setting. Your choice is saved to your account.")
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if saving { ProgressView() }
                        Text("Save Changes").fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(saving || fullName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("saveProfile")
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    upload(image)
                } else {
                    avatarError = "That picture could not be opened."
                }
                photoItem = nil
            }
        }
        .modifier(PlaygroundSheet(isPresented: $showPlayground, name: store.learner?.firstName ?? "") { upload($0) })
        .alert("Picture", isPresented: Binding(get: { avatarError != nil }, set: { if !$0 { avatarError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(avatarError ?? "") }
        .onAppear {
            guard !loaded, let l = store.learner else { return }
            loaded = true
            fullName = [l.firstName, l.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            phone = l.phone ?? ""
            linkedin = l.linkedinUrl ?? ""
            employment = l.employmentStatus ?? ""
            theme = l.theme == nil ? Appearance.cached : l.themeChoice
        }
        .task(id: isRealTrainer) {
            guard isRealTrainer, !certsLoaded else { return }
            if let list = try? await store.loadCertifications() {
                certsLoaded = true
                certs = list
            }
        }
        // Show the chosen appearance straight away; Save stores it on the account.
        .onChange(of: theme) { _, t in Appearance.apply(t) }
        .alert("Profile", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            // One Name row; the site keeps first and last name apart, so split at the last space.
            let parts = fullName.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            let first = parts.count > 1 ? parts.dropLast().joined(separator: " ") : (parts.first ?? "")
            let last = parts.count > 1 ? (parts.last ?? "") : ""
            var notice = try await store.updateProfile(
                firstName: first,
                lastName: last,
                phone: phone.trimmingCharacters(in: .whitespaces),
                linkedin: isStaffOrTrainer ? linkedin.trimmingCharacters(in: .whitespaces) : nil,
                employment: employment,
                theme: theme
            )
            if isRealTrainer, certsLoaded {
                try await store.saveCertifications(certs)
                notice = "Profile and certifications saved."
            }
            message = notice
            saved = true
        } catch {
            message = error.localizedDescription
        }
    }
}


/// Apple Intelligence picture creation (Image Playground). Does nothing on devices
/// or iOS versions that do not have it; the button is hidden there.
struct PlaygroundSheet: ViewModifier {
    @Binding var isPresented: Bool
    let name: String
    let onPicked: (UIImage) -> Void

    func body(content: Content) -> some View {
        #if canImport(ImagePlayground)
        if #available(iOS 18.2, *) {
            content.imagePlaygroundSheet(
                isPresented: $isPresented,
                concept: "a friendly profile picture portrait"
            ) { url in
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) { onPicked(image) }
            }
        } else { content }
        #else
        content
        #endif
    }
}


// MARK: - Payout (trainer tab)

struct PayoutView: View {
    @EnvironmentObject private var store: LearnerStore
    @State private var reply: PayoutsReply?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let reply {
                        if !reply.available {
                            ContentUnavailableView {
                                Label("Payouts not available", systemImage: "banknote")
                            } description: {
                                Text("Your payout history cannot be shown here right now. Please try again later.")
                            }
                            .padding(.top, 40)
                        } else if reply.payouts.isEmpty {
                            ContentUnavailableView {
                                Label("No payouts yet", systemImage: "banknote")
                            } description: {
                                Text("Payouts for the classes you teach appear here once they are paid.")
                            }
                            .padding(.top, 40)
                        } else {
                            SummaryCard(title: "Total paid", value: Fmt.money(reply.total, reply.currency),
                                        caption: "\(reply.payouts.count) payout\(reply.payouts.count == 1 ? "" : "s")")
                            ForEach(reply.payouts) { PayoutCard(payout: $0, currency: reply.currency) }
                        }
                    } else if let error {
                        ErrorCard(message: error) { Task { await load() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(20)
            }
            .background(Theme.page)
            .pullToRefresh { await load() }
            .task { if reply == nil { await load() } }
            .navigationTitle("Payout")
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
        }
    }

    private func load() async {
        do { reply = try await store.loadPayouts(); error = nil } catch { self.error = error.localizedDescription }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.white.opacity(0.85))
            Text(value).font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
            Text(caption).font(.footnote).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct PayoutCard: View {
    let payout: Payout
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(payout.title.isEmpty ? "Class" : payout.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Text(Fmt.money(payout.amount, currency))
                    .font(.headline)
                    .foregroundStyle(Theme.success)
            }
            Group {
                if !payout.startDate.isEmpty {
                    LabeledContent("Class", value: Fmt.range(payout.startDate, payout.endDate))
                }
                if !payout.paymentDate.isEmpty {
                    LabeledContent("Paid", value: Fmt.longDate(payout.paymentDate))
                }
                if let n = payout.learners, n > 0 {
                    LabeledContent("Learners", value: String(n))
                }
                if !payout.courseCode.isEmpty {
                    LabeledContent("Course", value: payout.courseCode)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
    }
}

// MARK: - Training hours (trainer tab)

struct TrainingHoursView: View {
    @EnvironmentObject private var store: LearnerStore
    @State private var reply: TrainingHoursReply?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let reply {
                        if reply.classes.isEmpty {
                            ContentUnavailableView {
                                Label("No training hours yet", systemImage: "clock")
                            } description: {
                                Text("Hours for the classes you teach appear here after each class day.")
                            }
                            .padding(.top, 40)
                        } else {
                            SummaryCard(title: "Total training hours", value: Fmt.hours(reply.totalHours),
                                        caption: "\(reply.classes.count) class\(reply.classes.count == 1 ? "" : "es") in the last 3 years")
                            Text("By month").font(.headline).padding(.top, 4)
                            VStack(spacing: 0) {
                                ForEach(reply.months) { m in
                                    HStack {
                                        Text(Fmt.month(m.month))
                                        Spacer()
                                        Text(Fmt.hours(m.hours)).fontWeight(.semibold)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    if m.id != reply.months.last?.id { Divider().padding(.leading, 16) }
                                }
                            }
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
                            Text("By class").font(.headline).padding(.top, 4)
                            ForEach(reply.classes) { c in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top) {
                                        Text(c.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 12)
                                        Text(Fmt.hours(c.hours)).font(.headline).foregroundStyle(Theme.accent)
                                    }
                                    Text("\(Fmt.range(c.startDate, c.endDate)) · \(c.days) day\(c.days == 1 ? "" : "s")")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
                            }
                            Text("Each class day counts its class time, less a one-hour lunch on days longer than five hours.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if let error {
                        ErrorCard(message: error) { Task { await load() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(20)
            }
            .background(Theme.page)
            .pullToRefresh { await load() }
            .task { if reply == nil { await load() } }
            .navigationTitle("Training Hours")
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
        }
    }

    private func load() async {
        do { reply = try await store.loadTrainingHours(); error = nil } catch { self.error = error.localizedDescription }
    }
}


// MARK: - Profile helpers

/// Trainer qualifications shown as badges under the name.
struct TrainerBadge {
    let code: String
    let name: String
    let issuer: String

    func matches(_ certName: String) -> Bool {
        let n = certName.lowercased()
        return n.contains(code.lowercased()) || n.contains(name.lowercased())
    }

    static let all: [TrainerBadge] = [
        TrainerBadge(code: "ACLP", name: "WSQ Advanced Certificate in Learning and Performance (ACLP)", issuer: "Institute for Adult Learning"),
        TrainerBadge(code: "ACTA", name: "WSQ Advanced Certificate in Training and Assessment (ACTA)", issuer: "Institute for Adult Learning"),
        TrainerBadge(code: "DDDLP", name: "WSQ Diploma in Design and Development of Learning for Performance (DDDLP)", issuer: "Institute for Adult Learning"),
        TrainerBadge(code: "DACE", name: "WSQ Diploma in Adult and Continuing Education (DACE)", issuer: "Institute for Adult Learning"),
    ]
}

/// One contact detail; tapping it calls, emails, opens WhatsApp or the LinkedIn profile.
struct ContactRow: View {
    let icon: String
    let title: String
    let value: String
    let url: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { if let url { openURL(url) } } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.subheadline).foregroundStyle(.primary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// Lays chips out left to right, wrapping to new centred rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > width, !(rows.last?.isEmpty ?? true) { rows.append([]); x = 0 }
            rows[rows.count - 1].append((i, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let r = rows(subviews, width: width)
        let height = r.reduce(0) { $0 + ($1.map { $0.1.height }.max() ?? 0) } + spacing * CGFloat(max(r.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let rowWidth = row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(row.count - 1, 0))
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            let h = row.map { $0.1.height }.max() ?? 0
            for (i, size) in row {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += h + spacing
        }
    }
}

// MARK: - Staff dashboard (Admin, Marketing, Developer, Franchise Admin)

struct StaffDashboardView: View {
    let role: String
    @EnvironmentObject private var store: LearnerStore
    @State private var data: StaffDashboard?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HomeHeader()
                    if let data {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(data.cards) { StaffCardView(card: $0) }
                        }
                        ForEach(data.lists) { list in
                            Text(list.title).font(.headline).padding(.top, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(list.rows.enumerated()), id: \.offset) { i, row in
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(row.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                            if !row.subtitle.isEmpty {
                                                Text(row.subtitle).font(.footnote).foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        Spacer(minLength: 8)
                                        if !row.value.isEmpty {
                                            Text(row.value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                                                .multilineTextAlignment(.trailing)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    if i < list.rows.count - 1 { Divider().padding(.leading, 16) }
                                }
                            }
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
                        }
                        Text("Updated \(data.updatedAt). Pull down to refresh.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if let error {
                        ErrorCard(message: error) { Task { await load() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(20)
            }
            .background(Theme.page)
            .pullToRefresh { await load() }
            .task(id: role) { data = nil; await load() }
            .navigationTitle(LearnerStore.roleName(role))
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
        }
    }

    private func load() async {
        do { data = try await store.loadStaffDashboard(role); error = nil } catch { self.error = error.localizedDescription }
    }
}

struct StaffCardView: View {
    let card: StaffCard

    private var tint: Color { card.tone == "warning" ? Theme.warning : Theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: card.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            Text(card.value).font(.system(size: 28, weight: .bold)).foregroundStyle(card.tone == "warning" ? Theme.warning : .primary)
            Text(card.title).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.title): \(card.value)")
    }
}

// MARK: - Finger signature for e-attendance

/// Someone who can sign in the signature dialog: the trainer ("trainer") or a roster learner (email).
struct Signer: Identifiable, Hashable {
    let id: String
    let name: String
    var signed = false
}

/// The dialog that takes a finger signature for attendance (replaces the check-in QR code).
/// Learner: one signer (themselves); signing checks them in and closes the dialog.
/// Trainer: picks who signs (themselves or a learner handed the phone); stays open for the next.
struct SignatureSheet: View {
    let title: String
    let sessionLabel: String
    /// More than one: a "Who is signing?" picker.
    let signers: [Signer]
    var hint = "Sign with your finger in the box below."
    var closeOnSuccess = true
    /// Sends the signature; answers the message to show.
    let submit: (_ signer: Signer, _ png: Data) async throws -> String

    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    @State private var signerId = ""
    @State private var done: Set<String> = []
    @State private var sending = false
    @State private var message: String?
    @State private var error: String?
    @State private var padSize = CGSize(width: 320, height: 200)
    @State private var drawing = false

    private var signer: Signer? { signers.first { $0.id == signerId } ?? signers.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.headline)
                        if !sessionLabel.isEmpty {
                            Text(sessionLabel).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if signers.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Who is signing?").font(.subheadline.weight(.semibold))
                            Picker("Who is signing?", selection: $signerId) {
                                ForEach(signers) { s in
                                    Text(s.name + (isSigned(s) ? "  ✓ signed" : "")).tag(s.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("signerPicker")
                        }
                    } else if let s = signers.first {
                        Label(s.name, systemImage: "person.fill").font(.subheadline.weight(.semibold))
                    }
                    Text(hint).font(.footnote).foregroundStyle(.secondary)
                    pad
                    if let message {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.success)
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    HStack(spacing: 12) {
                        Button {
                            strokes = []
                        } label: {
                            Label("Clear", systemImage: "eraser").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(strokes.isEmpty || sending)
                        .accessibilityIdentifier("clearSignature")
                        Button {
                            Task { await send() }
                        } label: {
                            HStack {
                                if sending { ProgressView().tint(.white) }
                                Label("Submit", systemImage: "signature")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brand)
                        .controlSize(.large)
                        .disabled(!hasInk || sending || signer == nil)
                        .accessibilityIdentifier("submitSignature")
                    }
                }
                .padding(20)
            }
            .scrollDisabled(true)
            .background(Theme.page)
            .navigationTitle("Sign Attendance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(closeOnSuccess ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        // A downward stroke must draw, not pull the dialog away.
        .interactiveDismissDisabled()
        .onAppear {
            if signerId.isEmpty { signerId = signers.first?.id ?? "" }
        }
    }

    /// Enough ink to count as a signature, not a stray tap.
    private var hasInk: Bool { strokes.reduce(0) { $0 + $1.count } >= 8 }

    private func isSigned(_ s: Signer) -> Bool { s.signed || done.contains(s.id) }

    private var pad: some View {
        ZStack(alignment: .bottomLeading) {
            // The pad is always white with black ink, in either theme, like paper.
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white)
            Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1)
                .padding(.horizontal, 24).padding(.bottom, 44)
            if strokes.isEmpty {
                Text("Sign here")
                    .font(.callout)
                    .foregroundStyle(Color.black.opacity(0.35))
                    .padding(.leading, 24).padding(.bottom, 52)
            }
            SignatureInk(strokes: strokes)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.15)))
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .background(GeometryReader { g in
            Color.clear.onAppear { padSize = g.size }.onChange(of: g.size) { _, new in padSize = new }
        })
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    let p = CGPoint(x: min(max(v.location.x, 0), padSize.width), y: min(max(v.location.y, 0), padSize.height))
                    if !drawing || strokes.isEmpty { strokes.append([p]); drawing = true } else { strokes[strokes.count - 1].append(p) }
                }
                .onEnded { _ in drawing = false }
        )
        .accessibilityElement()
        .accessibilityLabel("Signature pad")
        .accessibilityHint("Draw your signature with one finger.")
        .accessibilityIdentifier("signaturePad")
    }

    @MainActor
    private func png() -> Data? {
        let renderer = ImageRenderer(content: SignatureInk(strokes: strokes).frame(width: padSize.width, height: padSize.height))
        renderer.scale = 2
        return renderer.uiImage?.pngData()
    }

    private func send() async {
        guard let s = signer, let data = png() else { return }
        sending = true
        error = nil
        message = nil
        defer { sending = false }
        do {
            let text = try await submit(s, data)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            strokes = []
            done.insert(s.id)
            if closeOnSuccess {
                dismiss()
            } else {
                message = text
                // Hand the phone to the next learner who has not signed.
                if let next = signers.first(where: { $0.id != "trainer" && !isSigned($0) }) { signerId = next.id }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The ink of a signature: black strokes on a clear background (also what is uploaded).
struct SignatureInk: View {
    let strokes: [[CGPoint]]

    var body: some View {
        Canvas { ctx, _ in
            for stroke in strokes {
                var path = Path()
                if stroke.count == 1, let p = stroke.first {
                    path.addEllipse(in: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3))
                    ctx.fill(path, with: .color(.black))
                    continue
                }
                path.addLines(stroke)
                ctx.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
