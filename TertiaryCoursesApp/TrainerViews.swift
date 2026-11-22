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
    @State private var showQR = false
    @State private var surveyQR: SurveyLink?
    @State private var doc: DocLink?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let d = detail {
                    overview(d)
                    attendanceCard(d)
                    materialsCard(d)
                    feedbackCard(d)
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
        .documentViewer($doc)
        .sheet(isPresented: $showQR) {
            if let d = detail, let link = d.checkinUrl, !link.isEmpty {
                CheckInQRView(link: link, title: d.title, sessionLabel: d.currentSessionLabel ?? "")
            }
        }
        .sheet(item: $surveyQR) { s in
            CheckInQRView(link: s.url, title: detail?.title ?? "", sessionLabel: "",
                          heading: s.title, hint: s.hint, shareLabel: "Share Link")
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
            detail = d
            error = nil
            if session.isEmpty || !d.sessions.contains(where: { $0.key == session }) {
                session = (d.currentSession ?? "").isEmpty ? (d.sessions.first?.key ?? "") : (d.currentSession ?? "")
            }
            resetMarks(d)
            #if DEBUG
            // Screenshot automation: OPEN_DOC=1 opens the first material, OPEN_QR=1 the check-in QR.
            let env = ProcessInfo.processInfo.environment
            if env["OPEN_DOC"] == "1", doc == nil, let m = d.materials.first, let url = URL(string: m.url) {
                doc = DocLink(title: m.title, url: url)
            }
            if env["OPEN_QR"] == "1" { showQR = true }
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
                HStack(spacing: 6) {
                    StatusChip(text: "Teaching", color: Theme.accent)
                    if d.bucket == "current" { StatusChip(text: "In progress", color: Theme.success) }
                }
                Text(d.title).font(.title3.bold())
                Text([d.classId, d.sku].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Divider()
                Label(Fmt.range(d.startDate, d.endDate), systemImage: "calendar")
                if !d.startTime.isEmpty {
                    Label(Fmt.times(d.startTime, d.endTime), systemImage: "clock")
                }
                if !d.mode.isEmpty {
                    Label(d.mode, systemImage: d.mode == "Live Online" ? "video.fill" : "building.2.fill")
                }
                if !d.venue.isEmpty || !d.room.isEmpty {
                    Label([d.room, d.venue].filter { !$0.isEmpty }.joined(separator: "\n"), systemImage: "mappin.and.ellipse")
                        .textSelection(.enabled)
                }
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

    private func attendanceCard(_ d: TrainerClassDetail) -> some View {
        let open = d.attendanceOpen ?? false
        return InfoCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel("Take attendance")
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
                                    Text(r.name.isEmpty ? r.email : r.name)
                                        .font(.subheadline.weight(.medium))
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
                    if let link = d.checkinUrl, !link.isEmpty {
                        Button {
                            showQR = true
                        } label: {
                            Label("Show Check-in QR", systemImage: "qrcode").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("showQR")
                    }
                }
            }
        }
    }

    private func materialsCard(_ d: TrainerClassDetail) -> some View {
        let all = d.materials + (d.documents ?? [])
        return InfoCard {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Class materials")
                    .padding(.bottom, 6)
                if all.isEmpty {
                    Text("No materials are linked to this course yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
                ForEach(all) { m in
                    if let url = URL(string: m.url) {
                        MaterialRow(material: m) { openDocument(url, title: m.title, in: $doc) }
                        if m != all.last { Divider() }
                    }
                }
            }
        }
    }

    private func feedbackCard(_ d: TrainerClassDetail) -> some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Course feedback")
                let n = d.surveyResponses ?? 0
                Label(n == 0 ? "No feedback submitted yet" : "\(n) of \(d.roster.count) learner\(d.roster.count == 1 ? "" : "s") gave feedback",
                      systemImage: "star.bubble.fill")
                    .font(.subheadline)
                    .foregroundStyle(n == 0 ? Color.secondary : Color.primary)
                if let url = d.feedbackUrl, !url.isEmpty {
                    Button {
                        surveyQR = SurveyLink(title: "Course Survey", url: url,
                                              hint: "Learners scan this to give their course feedback.")
                    } label: {
                        Label("Show Course Survey QR", systemImage: "qrcode").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("showSurveyQR")
                }
                Text("Learners give feedback in this app from the first day of class.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var linkedin = ""
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
                TextField("First name", text: $firstName)
                    .textContentType(.givenName)
                TextField("Last name", text: $lastName)
                    .textContentType(.familyName)
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
                        FlowLayout(spacing: 8) {
                            ForEach(missing, id: \.code) { b in
                                Button {
                                    certs.append(CertDraft(name: b.name, issuer: b.issuer))
                                } label: {
                                    Label(b.code, systemImage: "plus")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Theme.accentSoft, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, 2)
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
                .disabled(saving || firstName.trimmingCharacters(in: .whitespaces).isEmpty)
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
            firstName = l.firstName
            lastName = l.lastName
            phone = l.phone ?? ""
            linkedin = l.linkedinUrl ?? ""
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
            var notice = try await store.updateProfile(
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                phone: phone.trimmingCharacters(in: .whitespaces),
                linkedin: isStaffOrTrainer ? linkedin.trimmingCharacters(in: .whitespaces) : nil,
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
            .refreshable { await load() }
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
            .refreshable { await load() }
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
            .refreshable { await load() }
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
