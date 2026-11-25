import SwiftUI

// Staff homes in the TIA TMS layout: Admin (today's and upcoming classes, with
// KPI tiles) and Developer (the course list), plus the month grid both the
// learner/trainer Calendar and the Admin Calendar draw.

// MARK: - Shared pieces

/// A KPI tile: a big number over a short caption.
struct KpiTile: View {
    let value: Int
    let label: String
    var highlight = false

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(highlight ? Theme.accent : .primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// An inline search field on a white card, as in TIA TMS.
struct InlineSearch: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Admin home

struct AdminHomeView: View {
    @EnvironmentObject private var store: LearnerStore
    @State private var data: AdminClassesReply?
    @State private var error: String?
    @State private var upcoming = false
    @State private var query = ""

    private var list: [AdminClass] {
        let all = (upcoming ? data?.upcoming : data?.current) ?? []
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.sku.localizedCaseInsensitiveContains(q)
                || $0.classId.localizedCaseInsensitiveContains(q) || $0.trainer.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HomeHeader()
                    if let data {
                        let k = data.kpis
                        HStack(spacing: 8) {
                            KpiTile(value: k?.runningToday ?? 0, label: "Running today")
                            KpiTile(value: k?.next30Days ?? 0, label: "Next 30 days")
                            KpiTile(value: k?.learnersToday ?? 0, label: "Learners today", highlight: true)
                        }
                        Picker("Classes", selection: $upcoming) {
                            Text("Current (\(data.current?.count ?? 0))").tag(false)
                            Text("Upcoming (\(data.upcoming?.count ?? 0))").tag(true)
                        }
                        .pickerStyle(.segmented)
                        InlineSearch(prompt: "Search course, class ID or trainer", text: $query)
                        if list.isEmpty {
                            ContentUnavailableView {
                                Label(query.isEmpty ? (upcoming ? "No upcoming classes" : "No classes running today") : "No classes found",
                                      systemImage: "calendar.badge.clock")
                            } description: {
                                Text(query.isEmpty ? "Classes in the next 30 days appear here." : "Try another course, class ID or trainer.")
                            }
                            .padding(.top, 20)
                        }
                        ForEach(list) { AdminClassCard(item: $0) }
                    } else if let error {
                        ErrorCard(message: error) { Task { await load() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(20)
            }
            .background(Theme.page)
            .scrollDismissesKeyboard(.interactively)
            .pullToRefresh { await load() }
            .task { if data == nil { await load() } }
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
        }
    }

    private func load() async {
        do { data = try await store.loadAdminClasses(); error = nil } catch { self.error = error.localizedDescription }
    }
}

struct AdminClassCard: View {
    let item: AdminClass

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.classId.isEmpty ? item.sku : "\(item.sku) · \(item.classId)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(item.title).font(.headline).multilineTextAlignment(.leading)
            VStack(alignment: .leading, spacing: 5) {
                Label(Fmt.range(item.startDate, item.endDate) + (item.startTime.isEmpty ? "" : " · " + Fmt.times(item.startTime, item.endTime)),
                      systemImage: "calendar")
                if item.trainer.isEmpty {
                    Label("No trainer assigned", systemImage: "person.fill").foregroundStyle(Theme.warning)
                } else {
                    Label(item.trainer, systemImage: "person.fill")
                }
                HStack(spacing: 14) {
                    Label("\(item.learnerCount) learner\(item.learnerCount == 1 ? "" : "s")", systemImage: "person.3.fill")
                    Label(item.mode == "Classroom" ? "Physical" : item.mode,
                          systemImage: item.mode == "Live Online" ? "video.fill" : "building.2.fill")
                }
                if !item.venue.isEmpty { Label(item.venue, systemImage: "mappin.and.ellipse") }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

// MARK: - Developer home

struct DeveloperHomeView: View {
    @EnvironmentObject private var store: LearnerStore
    @State private var data: DevCoursesReply?
    @State private var error: String?
    @State private var filter = Filter.all
    @State private var query = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", enabled = "Enabled", disabled = "Disabled"
        var id: String { rawValue }
    }

    private var list: [DevCourse] {
        var all = data?.courses ?? []
        switch filter {
        case .all: break
        case .enabled: all = all.filter { $0.enabled }
        case .disabled: all = all.filter { !$0.enabled }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.sku.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HomeHeader()
                    if let data {
                        HStack(spacing: 8) {
                            KpiTile(value: data.kpis.courses, label: "Courses")
                            KpiTile(value: data.kpis.courses - data.kpis.disabled, label: "Enabled")
                            KpiTile(value: data.kpis.disabled, label: "Disabled", highlight: true)
                        }
                        Picker("Filter", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        InlineSearch(prompt: "Search title or course code", text: $query)
                        Text("\(list.count) course\(list.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LazyVStack(spacing: 12) {
                            ForEach(list) { c in
                                NavigationLink { DevCourseDetailView(course: c) } label: { DevCourseCard(course: c) }
                                    .buttonStyle(.plain)
                            }
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
            .scrollDismissesKeyboard(.interactively)
            .pullToRefresh { await load() }
            .task { if data == nil { await load() } }
            .navigationTitle("Developer")
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
        }
    }

    private func load() async {
        do { data = try await store.loadDevCourses(); error = nil } catch { self.error = error.localizedDescription }
    }
}

struct DevCourseCard: View {
    let course: DevCourse

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(course.sku).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                StatusChip(text: course.enabled ? "Enabled" : "Disabled", color: course.enabled ? Theme.success : .red)
                if let type = course.courseType, !type.isEmpty {
                    StatusChip(text: type, color: Theme.accent)
                }
            }
            Text(course.title).font(.headline).multilineTextAlignment(.leading)
            if course.trainingHours != nil || course.assessmentHours != nil {
                Label("\(DevHours.text(course.trainingHours)) training · \(DevHours.text(course.assessmentHours)) assessment",
                      systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

/// "7.5 h", "16 h", "0 h".
enum DevHours {
    static func text(_ hours: Double?) -> String {
        let h = hours ?? 0
        return (h == h.rounded() ? String(Int(h)) : String(format: "%.1f", h)) + " h"
    }
}

// MARK: - Developer course page

/// A course for the Developer role: its identity, funding validity, type and hours, every
/// courseware link, and the Practice Exam switch. No description or class information.
struct DevCourseDetailView: View {
    @EnvironmentObject private var store: LearnerStore
    let course: DevCourse
    @State private var detail: DevCourseDetail?
    @State private var error: String?
    @State private var doc: DocLink?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let d = detail {
                    HStack(spacing: 6) {
                        Text(d.sku).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        StatusChip(text: d.enabled ? "Enabled" : "Disabled", color: d.enabled ? Theme.success : .red)
                    }
                    Text(d.title).font(.title3.weight(.semibold))
                    card("Course details") {
                        row("Course Title", d.title)
                        row("Course Code", d.sku)
                        row("Funding Validity", fundingValidity(d))
                        row("Course Type", d.courseType ?? (d.sku.uppercased().hasPrefix("TGS-") ? "WSQ" : "Non-WSQ"))
                        row("Duration", d.durationDays.map { $0 > 0 ? "\($0) day\($0 == 1 ? "" : "s")" : "Not set" } ?? d.durationHours.map { "\($0) hours" })
                        row("Training Hours", DevHours.text(d.trainingHours ?? Double(d.durationHours ?? "")))
                        row("Assessment Hours", DevHours.text(d.assessmentHours))
                    }
                    card("Courseware") {
                        let links = d.courseware ?? []
                        if links.isEmpty {
                            Text("No courseware links saved yet.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(links) { link in
                            CoursewareLinkRow(link: link) {
                                if let url = URL(string: link.url) { openDocument(url, title: link.label, in: $doc) }
                            }
                        }
                    }
                    if let setting = d.practiceExamSetting {
                        PracticeExamSwitch(courseId: d.id, setting: setting).id(setting)
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
        .navigationTitle(course.sku)
        .navigationBarTitleDisplayMode(.inline)
        .documentViewer($doc)
        .task { if detail == nil { await load() } }
    }

    private func load() async {
        do { detail = try await store.loadDevCourse(id: course.id); error = nil } catch { self.error = error.localizedDescription }
    }

    /// The SSG funding window of a WSQ course; non-WSQ courses have none (the web shows NA).
    private func fundingValidity(_ d: DevCourseDetail) -> String {
        guard let end = d.fundingValidityEnd, !end.isEmpty else { return "Not applicable (non-funded course)" }
        let start = d.fundingValidityStart.map(Fmt.longDate) ?? "N/A"
        return "\(start) – \(Fmt.longDate(end))"
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        if let v = value, !v.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(v).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

/// One courseware link: its name and the link itself. Tap to open; hold to copy or share.
struct CoursewareLinkRow: View {
    let link: DevCoursewareLink
    let open: () -> Void

    private var icon: String {
        if link.key == "courseware_link" || link.key == "lab_url" { return "folder.fill" }
        if link.key.contains("slides") { return "play.rectangle.fill" }
        if link.key == "practice_exam_url" { return "checkmark.seal.fill" }
        return "doc.text.fill"
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.label).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(link.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square").foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { UIPasteboard.general.string = link.url } label: { Label("Copy Link", systemImage: "doc.on.doc") }
            if let url = URL(string: link.url) {
                ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                Link(destination: url) { Label("Open in Safari", systemImage: "safari") }
            }
        }
        .accessibilityHint("Opens the link. Touch and hold to copy it.")
    }
}

/// The course's Practice Exam switch: on links the course to one exam on Tertiary Exams,
/// off removes it. Saved on the website straight away.
struct PracticeExamSwitch: View {
    @EnvironmentObject private var store: LearnerStore
    let courseId: Int
    @State var setting: PracticeExamSetting
    @State private var on: Bool
    @State private var slug: String
    @State private var saving = false
    @State private var problem: String?

    init(courseId: Int, setting: PracticeExamSetting) {
        self.courseId = courseId
        _setting = State(initialValue: setting)
        _on = State(initialValue: setting.enabled)
        _slug = State(initialValue: setting.examSlug)
    }

    private var currentTitle: String {
        setting.exams.first { $0.slug == setting.examSlug }?.title ?? setting.examCode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { on }, set: { switched($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Practice Exam").font(.headline)
                    Text(setting.enabled ? "On · \(currentTitle)" : "Off")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .tint(Theme.accent)
            .disabled(!setting.configured || saving)
            .accessibilityIdentifier("practice-exam-toggle")

            if !setting.configured {
                Text("Practice exams are not set up on this site.").font(.footnote).foregroundStyle(.secondary)
            } else if on {
                if setting.exams.isEmpty {
                    Text(setting.warning ?? "No practice exams are available.").font(.footnote).foregroundStyle(Theme.warning)
                } else {
                    Picker("Exam", selection: Binding(get: { slug }, set: { picked($0) })) {
                        if slug.isEmpty { Text("Choose an exam").tag("") }
                        ForEach(setting.exams) { Text("\($0.code) · \($0.title)").tag($0.slug) }
                    }
                    .pickerStyle(.menu)
                    .disabled(saving)
                }
            }
            if saving { ProgressView().frame(maxWidth: .infinity) }
            if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
            Text("Learners and trainers of this course's classes get a Practice Exam section on the class page.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }

    /// Off saves at once; on waits for an exam to be chosen (or saves the only one there is).
    private func switched(_ value: Bool) {
        problem = nil
        on = value
        if !value {
            slug = ""
            if setting.enabled { save("") }
        } else if setting.exams.count == 1 {
            picked(setting.exams[0].slug)
        }
    }

    private func picked(_ value: String) {
        slug = value
        guard !value.isEmpty, value != setting.examSlug else { return }
        save(value)
    }

    private func save(_ value: String) {
        saving = true
        Task {
            defer { saving = false }
            do {
                setting = try await store.setPracticeExam(courseId: courseId, examSlug: value)
                on = setting.enabled
                slug = setting.examSlug
            } catch {
                problem = error.localizedDescription
                on = setting.enabled
                slug = setting.examSlug
            }
        }
    }
}

// MARK: - Month grid (TIA TMS calendar)

/// One class on the calendar: the days it runs and whether it is over.
struct CalendarEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let days: [String]
    let past: Bool
}

/// A standard month calendar: one box per day, each listing that day's classes.
/// Tap a day to select it; swipe sideways to change month.
struct MonthGrid: View {
    @Binding var month: Date
    @Binding var selected: String
    let entries: [CalendarEntry]
    @Environment(\.horizontalSizeClass) private var sizeClass

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2   // Monday
        return c
    }
    private var cal: Calendar { Self.calendar }
    private var wide: Bool { sizeClass == .regular }

    static func firstOfMonth(_ d: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: d)) ?? d
    }

    private var byDay: [String: [CalendarEntry]] {
        var map: [String: [CalendarEntry]] = [:]
        for e in entries { for d in e.days { map[d, default: []].append(e) } }
        return map
    }

    private var gridDays: [Date?] {
        let first = month
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        var days: [Date?] = Array(repeating: nil, count: lead)
        for i in 0..<count { days.append(cal.date(byAdding: .day, value: i, to: first)) }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    var body: some View {
        let map = byDay
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.vertical, 12)
            weekdayRow
            grid(map)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardBorder))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                shift(value.translation.width < 0 ? 1 : -1)
            })
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(month.formatted(.dateTime.month(.wide).year())).font(.title3.bold())
            Spacer()
            Button("Today") {
                selected = Fmt.ymd(Date())
                withAnimation(.easeInOut(duration: 0.2)) { month = Self.firstOfMonth(Date()) }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 34, height: 34)
            }
            .accessibilityLabel("Previous month")
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").frame(width: 34, height: 34)
            }
            .accessibilityLabel("Next month")
        }
        .font(.body.weight(.semibold))
    }

    private var weekdayRow: some View {
        let symbols = cal.shortWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return HStack(spacing: 0) {
            ForEach(ordered, id: \.self) { name in
                Text(name.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .background(Theme.page)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
    }

    private func grid(_ map: [String: [CalendarEntry]]) -> some View {
        let days = gridDays
        return VStack(spacing: 0) {
            ForEach(0..<(days.count / 7), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        cell(days[row * 7 + col], map)
                            .overlay(alignment: .trailing) {
                                if col < 6 { Rectangle().fill(Theme.cardBorder).frame(width: 1) }
                            }
                    }
                }
                .overlay(alignment: .bottom) {
                    if row < days.count / 7 - 1 { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                }
            }
        }
    }

    @ViewBuilder private func cell(_ day: Date?, _ map: [String: [CalendarEntry]]) -> some View {
        let height: CGFloat = wide ? 104 : 72
        if let day {
            let key = Fmt.ymd(day)
            let classes = map[key] ?? []
            let isToday = key == Fmt.ymd(Date())
            let isSelected = key == selected
            let limit = wide ? 3 : 2
            Button {
                selected = key
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(cal.component(.day, from: day))")
                        .font(.footnote.weight(isToday || isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? Color.white : isToday ? Theme.accent : .primary)
                        .frame(width: 24, height: 24)
                        .background {
                            if isSelected { Circle().fill(Theme.brand) } else if isToday { Circle().fill(Theme.accentSoft) }
                        }
                    ForEach(classes.prefix(limit)) { e in
                        Text(e.title)
                            .font(.system(size: wide ? 11 : 9, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(e.past ? Color.primary.opacity(0.7) : Color.white)
                            .background(e.past ? Color(.systemGray4) : Theme.brand,
                                        in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    if classes.count > limit {
                        Text("+\(classes.count - limit) more").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(3)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
                .background(Rectangle().fill(isSelected ? Theme.accentSoft : Color.clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(day.formatted(date: .complete, time: .omitted)
                                + (classes.isEmpty ? ", no classes" : ", \(classes.count) class\(classes.count == 1 ? "" : "es")"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            Color(.systemGray6).opacity(0.5)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        }
    }

    private func shift(_ months: Int) {
        if let next = cal.date(byAdding: .month, value: months, to: month) {
            withAnimation(.easeInOut(duration: 0.2)) { month = next }
        }
    }
}

/// Legend and the month's class count under the grid.
struct CalendarLegend: View {
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            legend(Theme.brand, "Upcoming")
            legend(Color(.systemGray3), "Past")
            Spacer()
            Text("\(count) class\(count == 1 ? "" : "es") this month")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            Text(text)
        }
    }
}

/// Every date from start to end (at most 62), as yyyy-MM-dd.
func daySpan(_ start: String, _ end: String) -> [String] {
    guard let s = Fmt.date(start) else { return [] }
    let e = Fmt.date(end) ?? s
    var out: [String] = []
    var d = s
    while d <= e && out.count < 62 {
        out.append(Fmt.ymd(d))
        d = MonthGrid.calendar.date(byAdding: .day, value: 1, to: d) ?? e.addingTimeInterval(86400)
    }
    return out
}

func monthCount(_ entries: [CalendarEntry], _ month: Date) -> Int {
    let prefix = String(Fmt.ymd(month).prefix(7))
    return entries.filter { $0.days.contains { $0.hasPrefix(prefix) } }.count
}

// MARK: - Admin calendar

struct AdminCalendarView: View {
    @EnvironmentObject private var store: LearnerStore
    @State private var month = MonthGrid.firstOfMonth(Date())
    @State private var selected = Fmt.ymd(Date())
    @State private var classes: [AdminClass] = []
    @State private var error: String?
    @State private var loading = false

    private var entries: [CalendarEntry] {
        let today = Fmt.ymd(Date())
        return classes.map { CalendarEntry(id: "\($0.runId)", title: $0.title, days: daySpan($0.startDate, $0.endDate), past: $0.endDate < today) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MonthGrid(month: $month, selected: $selected, entries: entries)
                    CalendarLegend(count: monthCount(entries, month))
                    Text(Fmt.longDate(selected)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                    let day = classes.filter { daySpan($0.startDate, $0.endDate).contains(selected) }
                    if let error {
                        ErrorCard(message: error) { Task { await load() } }
                    } else if day.isEmpty {
                        InfoCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(loading ? "Loading classes…" : "No classes on this day").font(.headline)
                                Text("Pick another day, or swipe the calendar to change month.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ForEach(day) { AdminClassCard(item: $0) }
                }
                .padding(20)
            }
            .background(Theme.page)
            .pullToRefresh { await load() }
            .task(id: month) { await load() }
            .navigationTitle("Academy Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
        }
    }

    private func load() async {
        let cal = MonthGrid.calendar
        let from = cal.date(byAdding: .day, value: -7, to: month) ?? month
        let to = cal.date(byAdding: DateComponents(month: 1, day: 6), to: month) ?? month
        loading = true
        defer { loading = false }
        do {
            classes = try await store.loadAdminClasses(from: Fmt.ymd(from), to: Fmt.ymd(to)).classes ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
