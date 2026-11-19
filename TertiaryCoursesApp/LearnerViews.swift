import EventKit
import SwiftUI

// MARK: - Calendar

/// Month view of the learner's class days, with the day's classes below.
struct CalendarView: View {
    @EnvironmentObject private var store: LearnerStore
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State private var selected = Fmt.ymd(Date())
    @State private var notice: String?

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2   // Monday
        return c
    }

    /// yyyy-MM-dd → classes on that day.
    private var byDay: [String: [ClassItem]] {
        var map: [String: [ClassItem]] = [:]
        for item in store.allClasses {
            let days = item.classDays.isEmpty ? [item.startDate] : item.classDays
            for d in days where !d.isEmpty { map[d, default: []].append(item) }
        }
        return map
    }

    private var gridDays: [Date?] {
        let range = cal.range(of: .day, in: .month, for: month)!
        let firstWeekday = cal.component(.weekday, from: month)
        let lead = (firstWeekday - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + range.map { cal.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    InfoCard {
                        VStack(spacing: 12) {
                            HStack {
                                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                                    .accessibilityLabel("Previous month")
                                Spacer()
                                Text(month.formatted(.dateTime.month(.wide).year()))
                                    .font(.headline)
                                Spacer()
                                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                                    .accessibilityLabel("Next month")
                            }
                            let symbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                                ForEach(symbols, id: \.self) { s in
                                    Text(s).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                }
                                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                                    if let day {
                                        dayCell(day)
                                    } else {
                                        Color.clear.frame(height: 40)
                                    }
                                }
                            }
                        }
                    }

                    SectionLabel(Fmt.longDate(selected))
                    let items = byDay[selected] ?? []
                    if items.isEmpty {
                        Text(store.classes == nil ? "Loading your classes…" : "No class on this day.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        if item.runId > 0 {
                            NavigationLink(value: item) { ClassCard(item: item) }
                                .buttonStyle(.plain)
                        } else {
                            ClassCard(item: item)
                        }
                    }

                    let upcoming = store.allClasses.filter { $0.bucket != "past" && $0.runId > 0 && !$0.startDate.isEmpty }
                    if !upcoming.isEmpty {
                        Button {
                            Task { await addToCalendar(upcoming) }
                        } label: {
                            Label("Add My Classes to Calendar", systemImage: "calendar.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .padding(.top, 6)
                    }
                }
                .padding(20)
            }
            .background(Theme.page)
            .refreshable { await store.refreshClasses() }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ClassItem.self) { ClassDestination(item: $0) }
            .brandToolbar()
            .alert("Calendar", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(notice ?? "")
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let key = Fmt.ymd(day)
        let hasClass = byDay[key] != nil
        let isSelected = key == selected
        let isToday = key == Fmt.ymd(Date())
        return Button {
            selected = key
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(.subheadline.weight(isToday || hasClass ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Theme.accent : Color.primary))
                Circle()
                    .fill(hasClass ? (isSelected ? Color.white : Theme.accent) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isSelected ? Theme.brand : (hasClass ? Theme.accentSoft : Color.clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (hasClass ? ", class day" : ""))
    }

    private func shift(_ months: Int) {
        if let m = cal.date(byAdding: .month, value: months, to: month) { month = m }
    }

    /// Writes each upcoming class day into the device calendar (write-only access).
    private func addToCalendar(_ items: [ClassItem]) async {
        let ek = EKEventStore()
        do {
            guard try await ek.requestWriteOnlyAccessToEvents() else {
                notice = "Allow calendar access in Settings to add your classes."
                return
            }
            var tz = Calendar(identifier: .gregorian)
            tz.timeZone = TimeZone(identifier: Site.timeZone) ?? .current
            var added = 0
            for item in items {
                for day in (item.classDays.isEmpty ? [item.startDate] : item.classDays) {
                    guard let date = Fmt.date(day) else { continue }
                    let ev = EKEvent(eventStore: ek)
                    ev.title = item.title
                    ev.calendar = ek.defaultCalendarForNewEvents
                    ev.location = item.mode == "Live Online" ? item.virtualLink : [item.room, item.venue].filter { !$0.isEmpty }.joined(separator: ", ")
                    ev.notes = "\(item.classId) · \(Site.siteName)"
                    let parts = cal.dateComponents([.year, .month, .day], from: date)
                    func at(_ hm: String, fallback: Int) -> Date? {
                        let p = hm.split(separator: ":").compactMap { Int($0) }
                        var c = parts
                        c.hour = p.count == 2 ? p[0] : fallback
                        c.minute = p.count == 2 ? p[1] : 0
                        return tz.date(from: c)
                    }
                    if let s = at(item.startTime, fallback: 9), let e = at(item.endTime, fallback: 17) {
                        ev.startDate = s
                        ev.endDate = e
                        ev.timeZone = tz.timeZone
                        try ek.save(ev, span: .thisEvent, commit: false)
                        added += 1
                    }
                }
            }
            try ek.commit()
            notice = "Added \(added) class day\(added == 1 ? "" : "s") to your calendar."
        } catch {
            notice = "Couldn't add to your calendar: \(error.localizedDescription)"
        }
    }
}

// MARK: - Certificates

struct CertificatesView: View {
    @EnvironmentObject private var store: LearnerStore
    @State private var doc: DocLink?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let certs = store.certificates {
                        if certs.isEmpty {
                            ContentUnavailableView {
                                Label("No certificates yet", systemImage: "rosette")
                            } description: {
                                Text("Certificates are issued after class when attendance requirements are met.")
                            }
                            .padding(.top, 40)
                        }
                        ForEach(certs) { cert in
                            InfoCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(cert.name, systemImage: "rosette")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.accent)
                                    Text(cert.title).font(.headline)
                                    Text("\(cert.certNo) · \(Fmt.range(cert.startDate, cert.endDate))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    if let url = URL(string: cert.url) {
                                        HStack {
                                            Button {
                                                openDocument(url, title: cert.title, in: $doc)
                                            } label: {
                                                Label("View PDF", systemImage: "doc.richtext").frame(maxWidth: .infinity)
                                            }
                                            .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                                            ShareLink(item: url) {
                                                Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                            }
                        }
                    } else if let err = store.loadError {
                        ErrorCard(message: err) { Task { await store.refreshCertificates() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(20)
            }
            .background(Theme.page)
            .refreshable { await store.refreshCertificates() }
            .navigationTitle("Certificates")
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
            .documentViewer($doc)
        }
    }
}

// MARK: - Billing

struct BillingView: View {
    @EnvironmentObject private var store: LearnerStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let orders = store.orders {
                        if orders.isEmpty {
                            ContentUnavailableView {
                                Label("No registrations yet", systemImage: "creditcard")
                            } description: {
                                Text("Your course registrations and payments appear here.")
                            }
                            .padding(.top, 40)
                        }
                        ForEach(orders) { OrderCard(order: $0) }
                    } else if let err = store.loadError {
                        ErrorCard(message: err) { Task { await store.refreshBilling() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(20)
            }
            .background(Theme.page)
            .refreshable { await store.refreshBilling() }
            .navigationTitle("Billing")
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
        }
    }
}

struct OrderCard: View {
    let order: Order

    private var statusColor: Color {
        switch order.status {
        case "paid": Theme.success
        case "pending": Theme.warning
        default: .secondary
        }
    }

    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Order #\(order.orderNo)").font(.subheadline.weight(.semibold))
                    Spacer()
                    StatusChip(text: order.statusLabel, color: statusColor)
                }
                ForEach(order.items, id: \.self) { line in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.title).font(.headline)
                        if !line.classDate.isEmpty {
                            Text([line.classDate, line.classTime].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text(line.sku + (line.qty > 1 ? " × \(Int(line.qty))" : ""))
                            Spacer()
                            Text(Fmt.money(line.amount, order.currency))
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                Divider()
                LabeledContent("Total", value: Fmt.money(order.total, order.currency))
                    .font(.subheadline.weight(.semibold))
                if order.refunded > 0 {
                    LabeledContent("Refunded", value: Fmt.money(order.refunded, order.currency)).font(.footnote)
                }
                Group {
                    LabeledContent("Ordered", value: Fmt.longDate(order.date))
                    if !order.paymentMethod.isEmpty {
                        LabeledContent("Payment", value: order.paymentMethod)
                    }
                    if !order.invoices.isEmpty {
                        LabeledContent("Invoice", value: order.invoices.joined(separator: ", "))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Account

struct AccountView: View {
    @EnvironmentObject private var store: LearnerStore
    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    @State private var deleting = false
    @State private var message: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: "profile") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(store.learner?.fullName.isEmpty == false ? store.learner!.fullName : "My account")
                                    .font(.headline)
                                if store.isTrainer { StatusChip(text: "Trainer", color: Theme.accent) }
                            }
                            Text(store.learner?.email ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Edit profile and appearance")
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("editProfile")
                }

                Section {
                    ReminderSettingsRow()
                } footer: {
                    Text("Reminds you 3 days before a class starts, the evening before each class day, and an hour before it begins.")
                }

                Section("Explore") {
                    NavigationLink { CatalogView(embedded: true) } label: {
                        Label("Browse Courses", systemImage: "books.vertical.fill")
                    }
                    Link(destination: Site.baseURL) {
                        Label(Site.websiteLabel, systemImage: "globe")
                    }
                }

                Section("Support") {
                    NavigationLink { FeedbackView(embedded: true) } label: {
                        Label("Send Feedback", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    NavigationLink { AboutView(embedded: true) } label: {
                        Label("About", systemImage: "info.circle.fill")
                    }
                    Link(destination: Site.privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                }

                Section {
                    Button("Sign Out") { confirmSignOut = true }
                }

                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        HStack {
                            Label("Delete Account", systemImage: "trash")
                            if deleting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(deleting)
                } footer: {
                    Text("Permanently deletes your \(Site.siteName) login account. Records we must keep by law — registrations, invoices, attendance and certificates — are retained.")
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
            .navigationDestination(for: String.self) { _ in EditProfileView() }
            #if DEBUG
            // Screenshot automation: OPEN_PROFILE=1 opens Edit Profile.
            .onAppear { if ProcessInfo.processInfo.environment["OPEN_PROFILE"] == "1", path.isEmpty { path.append("profile") } }
            #endif
            .confirmationDialog("Sign out of \(Site.appName)?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { Task { await store.signOut() } }
            }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Account Permanently", role: .destructive) { Task { await delete() } }
            } message: {
                Text("This removes your login for the app and \(Site.websiteLabel). It cannot be undone.")
            }
            .alert("Account", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func delete() async {
        deleting = true
        defer { deleting = false }
        do {
            _ = try await store.deleteAccount()
        } catch {
            message = error.localizedDescription
        }
    }
}
