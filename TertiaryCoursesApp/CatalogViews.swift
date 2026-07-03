import SwiftUI

struct CatalogView: View {
    @ObservedObject var catalog: CourseCatalogStore
    @State private var selectedCategory = "All"
    @State private var searchText = ""

    private var categories: [String] {
        ["All"] + Array(Set(catalog.courses.map(\.category))).sorted()
    }

    private var filteredCourses: [Course] {
        catalog.courses.filter { course in
            let categoryMatches = selectedCategory == "All" || course.category == selectedCategory
            let queryMatches = normalizedSearchText.isEmpty || course.searchIndex.localizedCaseInsensitiveContains(normalizedSearchText)
            return categoryMatches && queryMatches
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if catalog.isLoading {
                        ProgressView("Loading course runs")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if catalog.loadedFromAPI {
                        Label("Live TGS-coded WSQ course runs from LMS/TMS", systemImage: "checkmark.icloud.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let errorMessage = catalog.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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
                            Text("Try a different keyword or category.")
                        } actions: {
                            Button("Clear Search") {
                                searchText = ""
                                selectedCategory = "All"
                            }
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(filteredCourses) { course in
                            NavigationLink(value: course) {
                                CourseCard(course: course)
                            }
                            .buttonStyle(.plain)
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
        }
    }
}

struct CourseCard: View {
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
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

            HStack {
                CourseBadge(text: course.fundingTier.rawValue, symbol: "checkmark.seal.fill")
                if course.skillsFutureClaimable {
                    CourseBadge(text: "SkillsFuture Claimable", symbol: "person.crop.circle.badge.checkmark")
                }
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private var iconName: String {
        switch course.category {
        case "Cybersecurity": "lock.shield.fill"
        case "Automation": "gearshape.2.fill"
        case "Microsoft Power Platform": "square.grid.2x2.fill"
        case "Programming", "AI and Programming": "chevron.left.forwardslash.chevron.right"
        case "Data Analytics": "chart.xyaxis.line"
        case "Data Visualisation", "Business Intelligence": "chart.bar.xaxis"
        case "Databases": "cylinder.split.1x2.fill"
        default: "books.vertical.fill"
        }
    }
}

struct CourseBadge: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
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
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Funding")
                        LabeledContent("SSG funding", value: course.fundingTier.rawValue)
                        LabeledContent("SkillsFuture Credit", value: course.skillsFutureClaimable ? "Claimable" : "Not marked claimable")
                        Text(course.fundingTier.shortDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                InfoCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Outcomes")
                        ForEach(course.outcomes, id: \.self) { outcome in
                            Label(outcome, systemImage: "checkmark.circle.fill")
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
