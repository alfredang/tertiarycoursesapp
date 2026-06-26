import Foundation
import SwiftUI
import UIKit

@main
struct TertiaryCoursesApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

enum Theme {
    static let accent = Color.teal
    static let card = Color(.secondarySystemGroupedBackground)
    static let page = Color(.systemGroupedBackground)
}

struct MainTabView: View {
    @StateObject private var catalog = CourseCatalogStore()

    var body: some View {
        TabView {
            CatalogView(catalog: catalog)
                .tabItem { Label("Courses", systemImage: "books.vertical.fill") }

            GrantCalculatorView(catalog: catalog)
                .tabItem { Label("Grants", systemImage: "dollarsign.circle.fill") }

            EnquiryView(catalog: catalog)
                .tabItem { Label("Enquiry", systemImage: "envelope.fill") }

            FeedbackView()
                .tabItem { Label("Feedback", systemImage: "bubble.left.and.bubble.right.fill") }

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle.fill") }
        }
        .tint(Theme.accent)
        .task {
            await catalog.loadCourseRuns()
        }
    }
}

enum FundingTier: String, CaseIterable, Identifiable {
    case tier1 = "Tier 1 SSG"
    case tier2 = "Tier 2 WSQ"
    case unfunded = "No SSG funding"

    var id: String { rawValue }

    var shortDescription: String {
        switch self {
        case .tier1:
            "Emerging skills, employability, SCTP, SkillsFuture Series, WPLN, or stackable IHL modules."
        case .tier2:
            "WSQ or other approved skills courses supporting general upskilling and reskilling."
        case .unfunded:
            "Not listed as SSG-funded. SkillsFuture Credit may still depend on official approval."
        }
    }
}

struct Course: Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let duration: String
    let delivery: String
    let fee: Decimal
    let fundingTier: FundingTier
    let skillsFutureClaimable: Bool
    let courseCode: String
    let summary: String
    let outcomes: [String]
    let isRemote: Bool

    init(
        id: String = UUID().uuidString,
        title: String,
        category: String,
        duration: String,
        delivery: String,
        fee: Decimal,
        fundingTier: FundingTier,
        skillsFutureClaimable: Bool,
        courseCode: String,
        summary: String,
        outcomes: [String],
        isRemote: Bool = false
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.duration = duration
        self.delivery = delivery
        self.fee = fee
        self.fundingTier = fundingTier
        self.skillsFutureClaimable = skillsFutureClaimable
        self.courseCode = courseCode
        self.summary = summary
        self.outcomes = outcomes
        self.isRemote = isRemote
    }
}

enum CourseData {
    static let courses: [Course] = [
        Course(
            title: "WSQ - Applications Integration with Power Apps and Power Automate",
            category: "Microsoft Power Platform",
            duration: "2 days",
            delivery: "Classroom",
            fee: 872,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-001",
            summary: "Build app and workflow integrations using Microsoft Power Apps and Power Automate.",
            outcomes: ["Create low-code business apps", "Automate approval workflows", "Connect app data sources"]
        ),
        Course(
            title: "WSQ - Python Fundamental Course for Beginners",
            category: "Programming",
            duration: "2 days",
            delivery: "Classroom",
            fee: 817.50,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-002",
            summary: "Learn beginner-friendly Python syntax, data structures, and practical scripting.",
            outcomes: ["Write Python scripts", "Use functions and collections", "Solve beginner programming tasks"]
        ),
        Course(
            title: "WSQ - R Fundamental and Statistical Analysis for Beginners",
            category: "Data Analytics",
            duration: "2 days",
            delivery: "Classroom",
            fee: 817.50,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-003",
            summary: "Use R for introductory statistics, analysis workflows, and data exploration.",
            outcomes: ["Run R scripts", "Summarise datasets", "Apply basic statistical analysis"]
        ),
        Course(
            title: "WSQ - Build and Deploy Python Applications with Vibe Coding",
            category: "AI and Programming",
            duration: "2 days",
            delivery: "Classroom",
            fee: 817.50,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-004",
            summary: "Create Python applications faster with AI-assisted coding workflows.",
            outcomes: ["Plan app features", "Use AI coding tools", "Deploy a Python application"]
        ),
        Course(
            title: "WSQ - Data Visualisation with Tableau",
            category: "Data Visualisation",
            duration: "2 days",
            delivery: "Classroom",
            fee: 817.50,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-005",
            summary: "Build Tableau dashboards and visual analytics for business reporting.",
            outcomes: ["Connect data in Tableau", "Design visual dashboards", "Publish interactive views"]
        ),
        Course(
            title: "WSQ - Cyber Security Awareness Course for Personal and Businesses",
            category: "Cybersecurity",
            duration: "1 day",
            delivery: "Classroom",
            fee: 381.50,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-006",
            summary: "Understand cyber threats, common attack patterns, and practical protection steps.",
            outcomes: ["Identify phishing risks", "Harden accounts and devices", "Respond to common incidents"]
        ),
        Course(
            title: "WSQ - Robotics Process Automation (RPA) for Beginners",
            category: "Automation",
            duration: "2 days",
            delivery: "Classroom",
            fee: 817.50,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-007",
            summary: "Use RPA concepts and tools to automate repeatable office processes.",
            outcomes: ["Map automation workflows", "Build simple bots", "Test automated processes"]
        ),
        Course(
            title: "WSQ - Data Analytics and Visualization with Power BI",
            category: "Business Intelligence",
            duration: "2 days",
            delivery: "Classroom",
            fee: 872,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-008",
            summary: "Create decision-ready Power BI reports with data shaping, models, and visual dashboards.",
            outcomes: ["Transform data with Power Query", "Create report visuals", "Publish Power BI dashboards"]
        ),
        Course(
            title: "WSQ - SQL Fundamental for Beginners",
            category: "Databases",
            duration: "1 day",
            delivery: "Classroom",
            fee: 381.50,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-009",
            summary: "Learn SQL queries for retrieving, filtering, joining, and summarising relational data.",
            outcomes: ["Write SELECT queries", "Filter and join tables", "Aggregate business data"]
        )
    ]
}

@MainActor
final class CourseCatalogStore: ObservableObject {
    @Published private(set) var courses = CourseData.courses
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var loadedFromAPI = false

    private let client = CourseAPIClient()

    func loadCourseRuns() async {
        guard !isLoading else { return }
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "TERTIARY_COURSES_API_KEY") as? String ?? ""

        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Using bundled WSQ catalog until the API key is configured."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let remoteCourses = try await client.listCourseRuns(apiKey: apiKey).filter(\.isWSQCourse)
            if remoteCourses.isEmpty {
                errorMessage = "The API returned no TGS-coded WSQ course runs. Showing bundled WSQ catalog."
                loadedFromAPI = false
            } else {
                courses = remoteCourses
                errorMessage = nil
                loadedFromAPI = true
            }
        } catch {
            errorMessage = "Could not load live WSQ course runs. Showing bundled WSQ catalog."
            loadedFromAPI = false
        }
    }
}

struct CourseAPIClient {
    private var listURL: URL {
        endpointURL(pathKey: "TERTIARY_COURSES_LIST_RUNS_PATH", fallbackPath: "/api/external/list-course-runs")
    }

    private var getRunURL: URL {
        endpointURL(pathKey: "TERTIARY_COURSES_GET_RUN_PATH", fallbackPath: "/api/external/get-course-run")
    }

    func listCourseRuns(apiKey: String) async throws -> [Course] {
        var request = URLRequest(url: listURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data)
        return extractCourseRuns(from: json).compactMap(course(from:))
    }

    func courseRunURL(courseRunID: String) -> URL {
        var components = URLComponents(url: getRunURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.queryItems = [URLQueryItem(name: "course_run_id", value: courseRunID)]
        return components.url ?? getRunURL
    }

    private func endpointURL(pathKey: String, fallbackPath: String) -> URL {
        let info = Bundle.main.infoDictionary
        let baseURLString = info?["TERTIARY_COURSES_API_BASE_URL"] as? String ?? "https://lms-tms.tertiaryinfotech.com"
        let path = info?[pathKey] as? String ?? fallbackPath

        guard var components = URLComponents(string: baseURLString) else {
            return URL(string: "https://lms-tms.tertiaryinfotech.com\(fallbackPath)")!
        }

        components.path = path
        return components.url ?? URL(string: "https://lms-tms.tertiaryinfotech.com\(fallbackPath)")!
    }

    private func extractCourseRuns(from json: Any) -> [[String: Any]] {
        if let array = json as? [[String: Any]] {
            return array
        }

        guard let dictionary = json as? [String: Any] else {
            return []
        }

        for key in ["data", "course_runs", "courseRuns", "results", "items", "runs"] {
            if let nested = dictionary[key] {
                let extracted = extractCourseRuns(from: nested)
                if !extracted.isEmpty {
                    return extracted
                }
            }
        }

        if stringValue(dictionary, keys: ["course_run_id", "courseRunId", "id", "course_id", "courseId"]) != nil,
           stringValue(dictionary, keys: ["course_title", "courseTitle", "title", "name", "course_name", "courseName"]) != nil {
            return [dictionary]
        }

        return []
    }

    private func course(from dictionary: [String: Any]) -> Course? {
        guard let title = stringValue(dictionary, keys: ["course_title", "courseTitle", "title", "name", "course_name", "courseName"]) else {
            return nil
        }

        let courseCode = stringValue(dictionary, keys: ["course_code", "courseCode", "tgs_code", "tgsCode", "tpgateway_code", "tpGatewayCode", "reference_number", "referenceNumber", "course_reference_number", "courseReferenceNumber"]) ?? ""
        guard courseCode.uppercased().hasPrefix("TGS") else {
            return nil
        }

        let id = stringValue(dictionary, keys: ["course_run_id", "courseRunId", "run_id", "runId", "id", "course_id", "courseId"]) ?? courseCode
        let category = stringValue(dictionary, keys: ["category", "course_category", "courseCategory", "domain", "programme", "program"]) ?? categoryFromTitle(title)
        let duration = stringValue(dictionary, keys: ["duration", "course_duration", "courseDuration", "duration_text", "durationText"]) ?? "Check course run"
        let delivery = stringValue(dictionary, keys: ["delivery", "delivery_mode", "deliveryMode", "training_mode", "trainingMode", "venue", "location"]) ?? "Check course run"
        let fee = decimalValue(dictionary, keys: ["gst_inclusive_fee", "gstInclusiveFee", "fee_gst_inclusive", "course_fee_gst", "courseFeeGst", "course_fee", "courseFee", "price", "fee", "amount"]) ?? 0
        let summary = stringValue(dictionary, keys: ["summary", "description", "course_description", "courseDescription", "synopsis", "objective"]) ?? title
        let outcomes = arrayValue(dictionary, keys: ["outcomes", "learning_outcomes", "learningOutcomes", "objectives"])
        let fundingTier = fundingTierFrom(title: title, category: category, dictionary: dictionary)

        return Course(
            id: id,
            title: title,
            category: category,
            duration: duration,
            delivery: delivery,
            fee: fee,
            fundingTier: fundingTier,
            skillsFutureClaimable: skillsFutureClaimable(title: title, dictionary: dictionary),
            courseCode: courseCode,
            summary: summary,
            outcomes: outcomes.isEmpty ? ["Check the live course run for current objectives and schedule."] : outcomes,
            isRemote: true
        )
    }

    private func stringValue(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private func decimalValue(_ dictionary: [String: Any], keys: [String]) -> Decimal? {
        guard let rawValue = stringValue(dictionary, keys: keys) else { return nil }
        let cleaned = rawValue.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned)
    }

    private func arrayValue(_ dictionary: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let array = dictionary[key] as? [String] {
                return array.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            if let string = dictionary[key] as? String {
                return string
                    .components(separatedBy: CharacterSet(charactersIn: "\n;•"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
        return []
    }

    private func fundingTierFrom(title: String, category: String, dictionary: [String: Any]) -> FundingTier {
        let combined = ([title, category] + dictionary.values.compactMap { $0 as? String }).joined(separator: " ").lowercased()
        if combined.contains("wsq") { return .tier2 }
        if combined.contains("ssg") || combined.contains("skillsfuture") || combined.contains("sctp") { return .tier1 }
        return .unfunded
    }

    private func skillsFutureClaimable(title: String, dictionary: [String: Any]) -> Bool {
        let combined = ([title] + dictionary.values.compactMap { $0 as? String }).joined(separator: " ").lowercased()
        return combined.contains("skillsfuture") || combined.contains("wsq") || combined.contains("ssg")
    }

    private func categoryFromTitle(_ title: String) -> String {
        let lowercased = title.lowercased()
        if lowercased.contains("cyber") || lowercased.contains("security") { return "Cybersecurity" }
        if lowercased.contains("power bi") || lowercased.contains("tableau") || lowercased.contains("analytics") { return "Data Analytics" }
        if lowercased.contains("python") || lowercased.contains("program") || lowercased.contains("coding") { return "Programming" }
        if lowercased.contains("rpa") || lowercased.contains("automate") { return "Automation" }
        if lowercased.contains("power apps") { return "Microsoft Power Platform" }
        if lowercased.contains("sql") { return "Databases" }
        return "Courses"
    }
}

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
            .navigationTitle("Courses")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search courses")
            .navigationDestination(for: Course.self) { course in
                CourseDetailView(course: course)
            }
        }
    }
}

private extension Course {
    var searchIndex: String {
        ([courseCode, title, category, duration, delivery, fundingTier.rawValue, summary] + outcomes).joined(separator: " ")
    }

    var isWSQCourse: Bool {
        courseCode.uppercased().hasPrefix("TGS")
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
                Label(currency(course.fee), systemImage: "tag")
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
            .background(Theme.accent.opacity(0.12), in: Capsule())
    }
}

struct CourseDetailView: View {
    let course: Course

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(course.category)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(course.summary)
                        .font(.body)
                    LabeledContent("Course code", value: course.courseCode)
                    LabeledContent("Duration", value: course.duration)
                    LabeledContent("Delivery", value: course.delivery)
                    LabeledContent("Published fee", value: currency(course.fee))
                    if course.isRemote {
                        LabeledContent("Course run ID", value: course.id)
                    }
                }
            }

            Section("Funding") {
                LabeledContent("SSG funding", value: course.fundingTier.rawValue)
                LabeledContent("SkillsFuture Credit", value: course.skillsFutureClaimable ? "Claimable" : "Not marked claimable")
                Text(course.fundingTier.shortDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Outcomes") {
                ForEach(course.outcomes, id: \.self) { outcome in
                    Label(outcome, systemImage: "checkmark.circle.fill")
                }
            }
        }
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum Nationality: String, CaseIterable, Identifiable {
    case singaporeCitizen = "Singapore Citizen"
    case permanentResident = "Permanent Resident"
    case ltvpPlus = "LTVP+ Holder"
    case other = "Other"

    var id: String { rawValue }
}

struct GrantCalculatorView: View {
    @ObservedObject var catalog: CourseCatalogStore
    @State private var selectedCourseID = CourseData.courses[0].id
    @State private var nationality: Nationality = .singaporeCitizen
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -35, to: Date()) ?? Date()
    @State private var skillsFutureCreditBalance = 500.0

    private var selectedCourse: Course {
        catalog.courses.first { $0.id == selectedCourseID } ?? catalog.courses.first ?? CourseData.courses[0]
    }

    private var estimate: GrantEstimate {
        GrantEstimate(course: selectedCourse, nationality: nationality, dateOfBirth: dateOfBirth, creditBalance: Decimal(skillsFutureCreditBalance))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Learner") {
                    Picker("Nationality", selection: $nationality) {
                        ForEach(Nationality.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }

                    DatePicker("Date of birth", selection: $dateOfBirth, displayedComponents: .date)
                    LabeledContent("Age", value: "\(estimate.age)")
                }

                Section("Course") {
                    Picker("Course", selection: $selectedCourseID) {
                        ForEach(catalog.courses) { course in
                            Text(course.title).tag(course.id)
                        }
                    }

                    LabeledContent("Published fee", value: currency(selectedCourse.fee))
                    LabeledContent("Funding tier", value: selectedCourse.fundingTier.rawValue)
                }

                Section("SkillsFuture Credit") {
                    HStack {
                        Text("Available balance")
                        Spacer()
                        TextField("Balance", value: $skillsFutureCreditBalance, format: .currency(code: "SGD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 150)
                    }
                    Text("SkillsFuture Credit is modelled only for Singapore Citizens and only when the course is marked claimable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Estimate") {
                    EstimateRow(title: "Course fee", value: estimate.courseFee)
                    EstimateRow(title: "SSG or WSQ subsidy", value: -estimate.subsidy)
                    EstimateRow(title: "SkillsFuture Credit", value: -estimate.skillsFutureCreditApplied)
                    EstimateRow(title: "Estimated payable", value: estimate.payable, isTotal: true)
                    LabeledContent("Funding rate", value: estimate.rateText)
                }

                Section("Important") {
                    Text("This is an estimate based on public SSG funding tiers. Final payable amounts depend on official course approval, learner status, GST treatment, available credit balance, and training-provider verification.")
                        .font(.footnote)
                    Link("Check official course eligibility on MySkillsFuture", destination: URL(string: "https://www.myskillsfuture.gov.sg/")!)
                }
            }
            .navigationTitle("Grant Calculator")
            .onChange(of: catalog.courses) { _, courses in
                if !courses.contains(where: { $0.id == selectedCourseID }) {
                    selectedCourseID = courses.first?.id ?? CourseData.courses[0].id
                }
            }
        }
    }
}

struct GrantEstimate {
    let course: Course
    let nationality: Nationality
    let dateOfBirth: Date
    let creditBalance: Decimal

    var age: Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
    }

    var courseFee: Decimal { course.fee }

    var fundingRate: Decimal {
        switch course.fundingTier {
        case .tier1:
            switch nationality {
            case .singaporeCitizen where age >= 40: 0.90
            case .singaporeCitizen, .permanentResident, .ltvpPlus: 0.70
            case .other: 0
            }
        case .tier2:
            switch nationality {
            case .singaporeCitizen where age >= 40: 0.70
            case .singaporeCitizen where age >= 21,
                 .permanentResident where age >= 21,
                 .ltvpPlus where age >= 21: 0.50
            default: 0
            }
        case .unfunded:
            0
        }
    }

    var subsidy: Decimal {
        rounded(courseFee * fundingRate)
    }

    var netAfterSubsidy: Decimal {
        max(0, courseFee - subsidy)
    }

    var skillsFutureCreditApplied: Decimal {
        guard nationality == .singaporeCitizen, course.skillsFutureClaimable else { return 0 }
        return min(netAfterSubsidy, max(0, creditBalance))
    }

    var payable: Decimal {
        max(0, netAfterSubsidy - skillsFutureCreditApplied)
    }

    var rateText: String {
        "\(Int((fundingRate as NSDecimalNumber).doubleValue * 100))%"
    }

    private func rounded(_ amount: Decimal) -> Decimal {
        var value = amount
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }
}

struct EstimateRow: View {
    let title: String
    let value: Decimal
    var isTotal = false

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(isTotal ? .semibold : .regular)
            Spacer()
            Text(currency(value))
                .fontWeight(isTotal ? .bold : .regular)
                .foregroundStyle(value < 0 ? .green : .primary)
        }
    }
}

struct EnquiryView: View {
    @ObservedObject var catalog: CourseCatalogStore
    @State private var selectedCourseID = CourseData.courses[0].id
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var message = ""

    private let whatsAppNumber = "6588666375"

    private var selectedCourse: Course {
        catalog.courses.first { $0.id == selectedCourseID } ?? catalog.courses.first ?? CourseData.courses[0]
    }

    private var canSend: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    Picker("Course", selection: $selectedCourseID) {
                        ForEach(catalog.courses) { course in
                            Text(course.title).tag(course.id)
                        }
                    }
                }

                Section("Contact") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .textContentType(.emailAddress)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }

                Section("Message") {
                    TextEditor(text: $message)
                        .frame(minHeight: 130)
                }

                Section {
                    Button(action: send) {
                        Label("Send Enquiry via WhatsApp", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
                }
            }
            .navigationTitle("Enquiry")
            .onChange(of: catalog.courses) { _, courses in
                if !courses.contains(where: { $0.id == selectedCourseID }) {
                    selectedCourseID = courses.first?.id ?? CourseData.courses[0].id
                }
            }
        }
    }

    private func send() {
        let body = """
        Tertiary Courses Singapore course enquiry

        Course: \(selectedCourse.title)
        Name: \(name.trimmingCharacters(in: .whitespacesAndNewlines))
        Email: \(email.trimmingCharacters(in: .whitespacesAndNewlines))
        Phone: \(phone.trimmingCharacters(in: .whitespacesAndNewlines))

        \(message.trimmingCharacters(in: .whitespacesAndNewlines))
        """

        openWhatsApp(number: whatsAppNumber, body: body)
    }
}

struct FeedbackView: View {
    @State private var title = ""
    @State private var message = ""
    private let whatsAppNumber = "6588666375"

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)

                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Your message")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                        }
                        TextEditor(text: $message)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                    }
                    .padding(8)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button(action: send) {
                        Label("Send via WhatsApp", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
                }
                .padding(20)
            }
            .background(Theme.page)
            .navigationTitle("Feedback")
        }
    }

    private func send() {
        var body = ""
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            body += "*\(trimmedTitle)*\n"
        }
        body += trimmedMessage
        openWhatsApp(number: whatsAppNumber, body: body)
    }
}

struct AboutView: View {
    private let websiteURL = URL(string: "https://www.tertiarycourses.com.sg/")!
    private let ssgFundingURL = URL(string: "https://www.ssg.gov.sg/funding-and-levy/funding-for-individuals/")!
    private let skillsFutureCreditURL = URL(string: "https://www.myskillsfuture.gov.sg/")!
    private let emailURL = URL(string: "mailto:enquiry@tertiaryinfotech.com")!
    private let phoneURL = URL(string: "tel:+6561000613")!

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    InfoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tertiary Courses SG")
                                .font(.title3.bold())
                            Text("Native iPhone catalog for tertiarycourses.com.sg with WSQ, IBF, SkillsFuture and PEI-approved course highlights, grant estimates, and course enquiries.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    SectionLabel("Official site")
                    InfoCard {
                        VStack(alignment: .leading, spacing: 0) {
                            Label("Tertiary Courses Singapore", systemImage: "building.2.fill")
                                .padding(.vertical, 12)
                            Divider()
                            Link(destination: websiteURL) {
                                Label("tertiarycourses.com.sg", systemImage: "globe")
                            }
                            .padding(.vertical, 12)
                            Divider()
                            Link(destination: phoneURL) {
                                Label("+65 6100 0613", systemImage: "phone.fill")
                            }
                            .padding(.vertical, 12)
                            Divider()
                            Link(destination: emailURL) {
                                Label("enquiry@tertiaryinfotech.com", systemImage: "envelope.fill")
                            }
                            .padding(.vertical, 12)
                        }
                    }

                    SectionLabel("Data source")
                    InfoCard {
                        VStack(alignment: .leading, spacing: 0) {
                            Link(destination: websiteURL) {
                                Label("Tertiary Courses Singapore catalog", systemImage: "books.vertical")
                            }
                            .padding(.vertical, 12)
                            Divider()
                            Link(destination: ssgFundingURL) {
                                Label("SkillsFuture Singapore funding tiers", systemImage: "checkmark.seal")
                            }
                            .padding(.vertical, 12)
                            Divider()
                            Link(destination: skillsFutureCreditURL) {
                                Label("MySkillsFuture course and credit checks", systemImage: "person.text.rectangle")
                            }
                            .padding(.vertical, 12)
                        }
                    }

                    InfoCard {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text(versionString)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.page)
            .navigationTitle("About")
        }
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct InfoCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

func currency(_ amount: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "SGD"
    formatter.maximumFractionDigits = 2
    return formatter.string(from: amount as NSDecimalNumber) ?? "SGD \(amount)"
}

func openWhatsApp(number: String, body: String) {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "wa.me"
    components.path = "/\(number)"
    components.queryItems = [URLQueryItem(name: "text", value: body)]

    if let url = components.url {
        UIApplication.shared.open(url)
    }
}

#Preview {
    MainTabView()
}
