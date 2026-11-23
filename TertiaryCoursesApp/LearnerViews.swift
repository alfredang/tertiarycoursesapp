import EventKit
import SwiftUI

// MARK: - Calendar

/// Month calendar of the account's classes in the TIA TMS layout: one box per day
/// listing that day's classes (past ones muted); the selected day's classes below.
struct CalendarView: View {
    @EnvironmentObject private var store: LearnerStore
    @State private var month = MonthGrid.firstOfMonth(Date())
    @State private var selected = Fmt.ymd(Date())
    @State private var notice: String?

    private var cal: Calendar { MonthGrid.calendar }

    private var entries: [CalendarEntry] {
        store.allClasses.map { item in
            CalendarEntry(id: item.id, title: item.title,
                          days: item.classDays.isEmpty ? [item.startDate].filter { !$0.isEmpty } : item.classDays,
                          past: item.bucket == "past")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MonthGrid(month: $month, selected: $selected, entries: entries)
                    CalendarLegend(count: monthCount(entries, month))

                    Text("\(Fmt.longDate(selected)) · \(Site.countryName) time")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    let items = store.allClasses.filter { item in
                        (item.classDays.isEmpty ? [item.startDate] : item.classDays).contains(selected)
                    }
                    if items.isEmpty {
                        InfoCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(store.classes == nil ? "Loading your classes…" : "No classes on this day").font(.headline)
                                Text("Pick another day, or swipe the calendar to change month.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let next = nextClassDay {
                                    Button("Jump to next class") {
                                        selected = next
                                        if let d = Fmt.date(next) { month = MonthGrid.firstOfMonth(d) }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
            .pullToRefresh { await store.refreshClasses() }
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

    /// The first class day after the selected day, if any.
    private var nextClassDay: String? {
        entries.flatMap(\.days).filter { $0 > selected }.min()
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
            .pullToRefresh { await store.refreshCertificates() }
            .navigationTitle("Certificates")
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
            .documentViewer($doc)
        }
    }
}

// MARK: - Billing

struct BillingView: View {
    /// True when pushed inside another NavigationStack (Account → Billing).
    var embedded = false
    @EnvironmentObject private var store: LearnerStore

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
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
            .pullToRefresh { await store.refreshBilling() }
            .navigationTitle("Billing")
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
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
                ProfileSections()

                Section {
                    ReminderSettingsRow()
                } footer: {
                    Text("Reminds you 3 days before a class starts, the evening before each class day, and an hour before it begins.")
                }

                if store.staffRole == nil && !store.isTrainer {
                    Section("Registrations") {
                        NavigationLink { BillingView(embedded: true) } label: {
                            Label("Billing", systemImage: "creditcard.fill")
                        }
                    }
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


/// The profile picture, or the person's initials on the brand colour.
struct AvatarView: View {
    let image: UIImage?
    let name: String
    var size: CGFloat = 80

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return parts.isEmpty ? "?" : String(parts).uppercased()
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.brand
                    Text(initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
