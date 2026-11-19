import CoreImage.CIFilterBuiltins
import SwiftUI

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
                        .accessibilityLabel("Check-in QR code")
                }
                Text("Learners scan this with their phone camera to check in to this session.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let url = URL(string: link) {
                    ShareLink(item: url) {
                        Label("Share Check-in Link", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Theme.page)
            .navigationTitle("Check-in QR")
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

// MARK: - Edit profile

struct EditProfileView: View {
    @EnvironmentObject private var store: LearnerStore
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var theme: ThemeChoice = Appearance.cached
    @State private var loaded = false
    @State private var saving = false
    @State private var message: String?
    @State private var saved = false

    var body: some View {
        Form {
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
            } header: {
                Text("Contact")
            } footer: {
                Text("Your sign-in email is \(store.learner?.email ?? ""). Contact us to change it.")
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
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let l = store.learner else { return }
            loaded = true
            firstName = l.firstName
            lastName = l.lastName
            phone = l.phone ?? ""
            theme = l.theme == nil ? Appearance.cached : l.themeChoice
        }
        // Show the chosen appearance straight away; Save stores it on the account.
        .onChange(of: theme) { _, t in Appearance.apply(t) }
        .alert("Profile", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil; if saved { dismiss() } } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            message = try await store.updateProfile(
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                phone: phone.trimmingCharacters(in: .whitespaces),
                theme: theme
            )
            saved = true
        } catch {
            message = error.localizedDescription
        }
    }
}
