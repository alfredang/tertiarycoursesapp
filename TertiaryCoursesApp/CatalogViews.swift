import SwiftUI

/// WSQ / non-WSQ funding filter across the whole catalog.
enum FundingFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case wsq = "WSQ"
    case nonWSQ = "Non-WSQ"

    var id: String { rawValue }

    func matches(_ course: Course) -> Bool {
        switch self {
        case .all: true
        case .wsq: course.isWSQCourse
        case .nonWSQ: !course.isWSQCourse
        }
    }
}

struct CatalogView: View {
    @ObservedObject var catalog: CourseCatalogStore
    @State private var selectedCategory = "All"
    @State private var fundingFilter: FundingFilter = .all
    @State private var searchText = ""
    /// Categories the user has collapsed. Sections start expanded.
    @State private var collapsed: Set<String> = []

    private var categories: [String] {
        ["All"] + catalog.categories.map(\.name)
    }

    private var filteredCourses: [Course] {
        catalog.courses.filter { course in
            let categoryMatches = selectedCategory == "All" || course.category == selectedCategory
            let queryMatches = normalizedSearchText.isEmpty || course.searchIndex.localizedCaseInsensitiveContains(normalizedSearchText)
            return categoryMatches && queryMatches && fundingFilter.matches(course)
        }
    }

    /// Filtered courses grouped into catalog-ordered category sections.
    private var sections: [(name: String, icon: String, courses: [Course])] {
        let grouped = Dictionary(grouping: filteredCourses, by: \.category)
        return catalog.categories.compactMap { category in
            guard let courses = grouped[category.name], !courses.isEmpty else { return nil }
            return (category.name, category.icon, courses)
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// While searching, sections auto-expand so matches are never hidden behind a collapsed header.
    private func isExpanded(_ name: String) -> Bool {
        !normalizedSearchText.isEmpty || !collapsed.contains(name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Picker("Funding", selection: $fundingFilter) {
                        ForEach(FundingFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)

                        Spacer()

                        Text("\(filteredCourses.count) course\(filteredCourses.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if filteredCourses.isEmpty {
                        ContentUnavailableView {
                            Label("No courses found", systemImage: "magnifyingglass")
                        } description: {
                            Text("Try a different keyword, category, or funding filter.")
                        } actions: {
                            Button("Clear Filters") {
                                searchText = ""
                                selectedCategory = "All"
                                fundingFilter = .all
                            }
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(sections, id: \.name) { section in
                            CategorySection(
                                name: section.name,
                                icon: section.icon,
                                courses: section.courses,
                                isExpanded: isExpanded(section.name),
                                toggle: {
                                    if collapsed.contains(section.name) {
                                        collapsed.remove(section.name)
                                    } else {
                                        collapsed.insert(section.name)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.page)
            .navigationTitle("Catalog")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search courses")
            .navigationDestination(for: Course.self) { course in
                CourseDetailView(course: course)
            }
            .brandToolbar()
            // A refreshed feed can retire a category the user had selected; without this
            // the list would silently show nothing.
            .onChange(of: catalog.courses) { _, _ in
                if selectedCategory != "All" && !categories.contains(selectedCategory) {
                    selectedCategory = "All"
                }
            }
        }
    }
}

/// A collapsible category header plus its course cards.
struct CategorySection: View {
    let name: String
    let icon: String
    let courses: [Course]
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(courses.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .foregroundStyle(Theme.accent)
                        .background(Theme.accentSoft, in: Capsule())
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name), \(courses.count) courses")
            .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")

            if isExpanded {
                ForEach(courses) { course in
                    NavigationLink(value: course) {
                        CourseCard(course: course)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct CourseCard: View {
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: course.iconName)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 6) {
                    Text(course.courseCode)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(course.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(course.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            HStack {
                Label(course.duration, systemImage: "clock")
                Spacer(minLength: 10)
                Label("\(currency(course.feeWithGST)) w/GST", systemImage: "tag")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                ForEach(course.fundingBadges, id: \.self) { badge in
                    SchemeBadge(text: badge)
                }
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }

}

// Small funding-scheme chip (WSQ / SFC / SFEC / PSEA / UTAP) sized to fit five in a row.
struct SchemeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(Theme.accent)
            .background(Theme.accentSoft, in: Capsule())
    }
}

struct CourseDetailView: View {
    let course: Course
    @State private var showGrantCalculator = false

    private let whatsAppNumber = "6588666375"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InfoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(course.category)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        Text(course.summary)
                            .font(.body)
                        Divider()
                        LabeledContent("Course code", value: course.courseCode)
                        LabeledContent("Duration", value: course.duration)
                        LabeledContent("Fee (before GST)", value: currency(course.fee))
                        LabeledContent("Fee with GST (9%)", value: currency(course.feeWithGST))
                        if course.isRemote {
                            LabeledContent("Course run ID", value: course.id)
                        }
                    }
                }

                Link(destination: course.registerURL) {
                    Label("Check Schedule", systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showGrantCalculator = true
                } label: {
                    Label("Calculate My Grant & Net Fee", systemImage: "dollarsign.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    enquire()
                } label: {
                    Label("Enquire via WhatsApp", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                InfoCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Funding")
                        ForEach(course.fundingSchemes, id: \.abbreviation) { scheme in
                            HStack(spacing: 10) {
                                Image(systemName: scheme.eligible ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(scheme.eligible ? Theme.accent : Color.secondary)
                                Text(scheme.abbreviation)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 48, alignment: .leading)
                                Text(scheme.name)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }
                        }
                        Text(course.fundingTier.shortDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !course.outcomes.isEmpty {
                    InfoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Outcomes")
                            ForEach(course.outcomes, id: \.self) { outcome in
                                Label(outcome, systemImage: "checkmark.circle.fill")
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.page)
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGrantCalculator) {
            CourseGrantSheet(course: course)
        }
    }

    private func enquire() {
        let body = """
        Tertiary Courses Singapore course enquiry

        Course: \(course.title)
        Course code: \(course.courseCode)
        """
        openWhatsApp(number: whatsAppNumber, body: body)
    }
}

// Grant calculator sheet launched from a course — the course fee (with GST) is autopopulated;
// the user enters nationality, age, sponsorship, and SkillsFuture Credit.
struct CourseGrantSheet: View {
    let course: Course
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    InfoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(course.title)
                                .font(.headline)
                            LabeledContent("Course fee (before GST)", value: currency(course.fee))
                            LabeledContent("Course fee with GST", value: currency(course.feeWithGST))
                        }
                    }

                    GrantCalculatorForm(course: course)
                }
                .padding(20)
            }
            .background(Theme.page)
            .navigationTitle("Grant Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
        .tint(Theme.accent)
    }
}
