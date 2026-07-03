import Foundation

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

/// `fee` is the ORIGINAL course fee before GST. GST is always computed on this
/// original fee, per SSG rules — see https://www.tpgateway.gov.sg/faq/grant-calculator-and-funding-eligibility
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
    let websiteURLString: String?

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
        isRemote: Bool = false,
        websiteURLString: String? = nil
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
        self.websiteURLString = websiteURLString
    }

    var feeWithGST: Decimal {
        GrantEstimate.roundedCurrency(fee * (1 + GrantEstimate.gstRate))
    }

    /// Course page on www.tertiarycourses.com.sg for registration. Falls back to a
    /// catalog search by title when no explicit page URL is known.
    var registerURL: URL {
        if let websiteURLString, let url = URL(string: websiteURLString) {
            return url
        }
        var components = URLComponents(string: "https://www.tertiarycourses.com.sg/catalogsearch/result/")!
        components.queryItems = [URLQueryItem(name: "q", value: title.replacingOccurrences(of: "WSQ - ", with: ""))]
        return components.url!
    }
}

enum CourseData {
    static let courses: [Course] = [
        Course(
            title: "WSQ - Applications Integration with Power Apps and Power Automate",
            category: "Microsoft Power Platform",
            duration: "2 days",
            delivery: "Classroom",
            fee: 800,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-001",
            summary: "Build app and workflow integrations using Microsoft Power Apps and Power Automate.",
            outcomes: ["Create low-code business apps", "Automate approval workflows", "Connect app data sources"],
            websiteURLString: "https://www.tertiarycourses.com.sg/wsq-applications-integration-with-power-apps-and-power-automate.html"
        ),
        Course(
            title: "WSQ - Python Fundamental Course for Beginners",
            category: "Programming",
            duration: "2 days",
            delivery: "Classroom",
            fee: 750,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-002",
            summary: "Learn beginner-friendly Python syntax, data structures, and practical scripting.",
            outcomes: ["Write Python scripts", "Use functions and collections", "Solve beginner programming tasks"],
            websiteURLString: "https://www.tertiarycourses.com.sg/wsq-python-fundamental-course-for-beginners.html"
        ),
        Course(
            title: "WSQ - R Fundamental and Statistical Analysis for Beginners",
            category: "Data Analytics",
            duration: "2 days",
            delivery: "Classroom",
            fee: 750,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-003",
            summary: "Use R for introductory statistics, analysis workflows, and data exploration.",
            outcomes: ["Run R scripts", "Summarise datasets", "Apply basic statistical analysis"],
            websiteURLString: "https://www.tertiarycourses.com.sg/wsq-r-fundamental-and-statistical-analysis-for-beginners.html"
        ),
        Course(
            title: "WSQ - Build and Deploy Python Applications with Vibe Coding",
            category: "AI and Programming",
            duration: "2 days",
            delivery: "Classroom",
            fee: 750,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-004",
            summary: "Create Python applications faster with AI-assisted coding workflows.",
            outcomes: ["Plan app features", "Use AI coding tools", "Deploy a Python application"],
            websiteURLString: "https://www.tertiarycourses.com.sg/wsq-build-and-deploy-python-applications-with-vibe-coding.html"
        ),
        Course(
            title: "WSQ - Data Visualisation with Tableau",
            category: "Data Visualisation",
            duration: "2 days",
            delivery: "Classroom",
            fee: 750,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-005",
            summary: "Build Tableau dashboards and visual analytics for business reporting.",
            outcomes: ["Connect data in Tableau", "Design visual dashboards", "Publish interactive views"],
            websiteURLString: "https://www.tertiarycourses.com.sg/wsq-data-visualisation-with-tableau.html"
        ),
        Course(
            title: "WSQ - Cyber Security Awareness Course for Personal and Businesses",
            category: "Cybersecurity",
            duration: "1 day",
            delivery: "Classroom",
            fee: 350,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-006",
            summary: "Understand cyber threats, common attack patterns, and practical protection steps.",
            outcomes: ["Identify phishing risks", "Harden accounts and devices", "Respond to common incidents"],
            websiteURLString: "https://www.tertiarycourses.com.sg/wsq-cyber-security-awareness-course-for-personal-and-businesses.html"
        ),
        Course(
            title: "WSQ - Robotics Process Automation (RPA) for Beginners",
            category: "Automation",
            duration: "2 days",
            delivery: "Classroom",
            fee: 750,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-007",
            summary: "Use RPA concepts and tools to automate repeatable office processes.",
            outcomes: ["Map automation workflows", "Build simple bots", "Test automated processes"],
            websiteURLString: "https://www.tertiarycourses.com.sg/wsq-robotics-process-automation-rpa-for-beginners.html"
        ),
        Course(
            title: "WSQ - Data Analytics and Visualization with Power BI",
            category: "Business Intelligence",
            duration: "2 days",
            delivery: "Classroom",
            fee: 800,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-008",
            summary: "Create decision-ready Power BI reports with data shaping, models, and visual dashboards.",
            outcomes: ["Transform data with Power Query", "Create report visuals", "Publish Power BI dashboards"],
            websiteURLString: "https://www.tertiarycourses.com.sg/wsq-data-analytics-and-visualization-with-power-bi.html"
        ),
        Course(
            title: "WSQ - SQL Fundamental for Beginners",
            category: "Databases",
            duration: "1 day",
            delivery: "Classroom",
            fee: 350,
            fundingTier: .tier2,
            skillsFutureClaimable: true,
            courseCode: "TGS-PLACEHOLDER-009",
            summary: "Learn SQL queries for retrieving, filtering, joining, and summarising relational data.",
            outcomes: ["Write SELECT queries", "Filter and join tables", "Aggregate business data"],
            websiteURLString: "https://www.tertiarycourses.com.sg/wsq-sql-fundamental-for-beginners.html"
        )
    ]
}

extension Course {
    var searchIndex: String {
        ([courseCode, title, category, duration, delivery, fundingTier.rawValue, summary] + outcomes).joined(separator: " ")
    }

    var isWSQCourse: Bool {
        courseCode.uppercased().hasPrefix("TGS")
    }
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
        let summary = stringValue(dictionary, keys: ["summary", "description", "course_description", "courseDescription", "synopsis", "objective"]) ?? title
        let outcomes = arrayValue(dictionary, keys: ["outcomes", "learning_outcomes", "learningOutcomes", "objectives"])
        let fundingTier = fundingTierFrom(title: title, category: category, dictionary: dictionary)

        // Prefer an explicit fee-before-GST; fall back to a GST-inclusive fee divided out,
        // so Course.fee is always the original (pre-GST) fee.
        var fee = decimalValue(dictionary, keys: ["course_fee", "courseFee", "fee_before_gst", "feeBeforeGst", "price", "fee", "amount"]) ?? 0
        if fee == 0, let gstInclusive = decimalValue(dictionary, keys: ["gst_inclusive_fee", "gstInclusiveFee", "fee_gst_inclusive", "course_fee_gst", "courseFeeGst"]) {
            fee = GrantEstimate.roundedCurrency(gstInclusive / (1 + GrantEstimate.gstRate))
        }

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
