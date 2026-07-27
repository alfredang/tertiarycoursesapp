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
struct Course: Identifiable, Hashable, Decodable {
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
    let sfecEligible: Bool
    let pseaEligible: Bool
    let utapEligible: Bool
    let ibfEligible: Bool
    /// SF Symbol for the course's category, chosen when the catalog snapshot is built.
    let iconName: String

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
        websiteURLString: String? = nil,
        sfecEligible: Bool = true,
        pseaEligible: Bool = true,
        utapEligible: Bool = true,
        ibfEligible: Bool = false,
        iconName: String = "books.vertical.fill"
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
        self.sfecEligible = sfecEligible
        self.pseaEligible = pseaEligible
        self.utapEligible = utapEligible
        self.ibfEligible = ibfEligible
        self.iconName = iconName
    }

    // Decodes the bundled Courses.json snapshot scraped from tertiarycourses.com.sg.
    private enum CodingKeys: String, CodingKey {
        case id, title, courseCode, category, icon, summary, duration, delivery, fee
        case isWSQ, sfc, sfec, psea, utap, ibf, url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        courseCode = try c.decode(String.self, forKey: .courseCode)
        category = try c.decode(String.self, forKey: .category)
        iconName = try c.decodeIfPresent(String.self, forKey: .icon) ?? "books.vertical.fill"
        summary = try c.decode(String.self, forKey: .summary)
        duration = try c.decode(String.self, forKey: .duration)
        delivery = try c.decode(String.self, forKey: .delivery)
        fee = Decimal(try c.decode(Double.self, forKey: .fee))
        websiteURLString = try c.decodeIfPresent(String.self, forKey: .url)

        let isWSQ = try c.decode(Bool.self, forKey: .isWSQ)
        skillsFutureClaimable = try c.decodeIfPresent(Bool.self, forKey: .sfc) ?? false
        sfecEligible = try c.decodeIfPresent(Bool.self, forKey: .sfec) ?? false
        pseaEligible = try c.decodeIfPresent(Bool.self, forKey: .psea) ?? false
        utapEligible = try c.decodeIfPresent(Bool.self, forKey: .utap) ?? false
        ibfEligible = try c.decodeIfPresent(Bool.self, forKey: .ibf) ?? false

        fundingTier = isWSQ ? .tier2 : .unfunded
        outcomes = []
        isRemote = false
    }

    var feeWithGST: Decimal {
        GrantEstimate.roundedCurrency(fee * (1 + GrantEstimate.gstRate))
    }

    /// Short funding-scheme badges shown on course cards.
    var fundingBadges: [String] {
        var badges: [String] = []
        if isWSQCourse { badges.append("WSQ") }
        if ibfEligible { badges.append("IBF") }
        if skillsFutureClaimable { badges.append("SFC") }
        if sfecEligible { badges.append("SFEC") }
        if pseaEligible { badges.append("PSEA") }
        if utapEligible { badges.append("UTAP") }
        return badges
    }

    /// Funding schemes with full names and eligibility, for the course detail page.
    var fundingSchemes: [(abbreviation: String, name: String, eligible: Bool)] {
        var schemes: [(String, String, Bool)] = [
            ("WSQ", "Workforce Skills Qualifications (SSG-funded)", isWSQCourse)
        ]
        if ibfEligible {
            schemes.append(("IBF", "Institute of Banking and Finance funding", true))
        }
        schemes += [
            ("SFC", "SkillsFuture Credit", skillsFutureClaimable),
            ("SFEC", "SkillsFuture Enterprise Credit", sfecEligible),
            ("PSEA", "Post-Secondary Education Account", pseaEligible),
            ("UTAP", "NTUC Union Training Assistance Programme", utapEligible)
        ]
        return schemes.map { (abbreviation: $0.0, name: $0.1, eligible: $0.2) }
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
    /// Full catalog snapshot of tertiarycourses.com.sg (WSQ + non-WSQ), bundled as Courses.json.
    static let courses: [Course] = {
        guard let url = Bundle.main.url(forResource: "Courses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Course].self, from: data)
        else {
            assertionFailure("Courses.json missing or malformed in the app bundle")
            return []
        }
        return decoded
    }()

    /// Category names in catalog order, each with its SF Symbol.
    static let categories: [(name: String, icon: String)] = {
        var seen = Set<String>()
        return courses.compactMap { course in
            guard !seen.contains(course.category) else { return nil }
            seen.insert(course.category)
            return (course.category, course.iconName)
        }
    }()
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
    /// The bundled catalog snapshot of tertiarycourses.com.sg — all WSQ and non-WSQ courses.
    @Published private(set) var courses = CourseData.courses
}
