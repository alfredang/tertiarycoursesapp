import SwiftUI

enum Nationality: String, CaseIterable, Identifiable {
    case singaporeCitizen = "Singapore Citizen"
    case permanentResident = "Singapore PR"
    case others = "Others"

    var id: String { rawValue }
}

enum Sponsorship: String, CaseIterable, Identifiable {
    case selfSponsored = "Self-Sponsored"
    case employerSME = "Employer-Sponsored (SME)"
    case employerNonSME = "Employer-Sponsored (Non-SME)"

    var id: String { rawValue }
}

/// SSG funding estimate per TP Gateway rules
/// (https://www.tpgateway.gov.sg/faq/grant-calculator-and-funding-eligibility):
/// - Baseline: 50% for Singapore Citizens below 40
/// - Enhanced (MCES): 70% for Singapore Citizens 40 and above
/// - Singapore PR: always 50%
/// - SME employer-sponsored (ETSS): 70% for Citizens and PRs regardless of age
/// - GST (9%) is always computed on the ORIGINAL course fee, before any grant.
struct GrantEstimate {
    static let gstRate: Decimal = 0.09

    let courseFee: Decimal          // original fee, before GST
    let skillsFutureClaimable: Bool
    let nationality: Nationality
    let age: Int
    let sponsorship: Sponsorship
    let creditBalance: Decimal

    var fundingRate: Decimal {
        switch nationality {
        case .singaporeCitizen:
            if sponsorship == .employerSME { return 0.70 }
            return age >= 40 ? 0.70 : 0.50
        case .permanentResident:
            return sponsorship == .employerSME ? 0.70 : 0.50
        case .others:
            return 0
        }
    }

    var grantName: String {
        switch nationality {
        case .singaporeCitizen:
            if sponsorship == .employerSME { return "SME Enhanced Training Support (70%)" }
            return age >= 40 ? "Enhanced Grant — MCES (70%)" : "Baseline Grant (50%)"
        case .permanentResident:
            return sponsorship == .employerSME ? "SME Enhanced Training Support (70%)" : "Baseline Grant (50%)"
        case .others:
            return "Not eligible for SSG funding"
        }
    }

    var gst: Decimal { Self.roundedCurrency(courseFee * Self.gstRate) }

    var feeWithGST: Decimal { courseFee + gst }

    var grant: Decimal { Self.roundedCurrency(courseFee * fundingRate) }

    var netBeforeCredit: Decimal { max(0, feeWithGST - grant) }

    /// SkillsFuture Credit applies only to self-sponsored Singapore Citizens on claimable courses.
    var canUseSkillsFutureCredit: Bool {
        nationality == .singaporeCitizen && sponsorship == .selfSponsored && skillsFutureClaimable
    }

    var skillsFutureCreditApplied: Decimal {
        guard canUseSkillsFutureCredit else { return 0 }
        return min(netBeforeCredit, max(0, creditBalance))
    }

    var netFee: Decimal { max(0, netBeforeCredit - skillsFutureCreditApplied) }

    var rateText: String {
        "\(Int((fundingRate as NSDecimalNumber).doubleValue * 100))%"
    }

    static func roundedCurrency(_ amount: Decimal) -> Decimal {
        var value = amount
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }
}

// MARK: - Grant Calculator tab

struct GrantCalculatorView: View {
    @ObservedObject var catalog: CourseCatalogStore
    @State private var selectedCourseID = CourseData.courses[0].id

    private var selectedCourse: Course {
        catalog.courses.first { $0.id == selectedCourseID } ?? catalog.courses.first ?? CourseData.courses[0]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    InfoCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Course")
                            Menu {
                                ForEach(catalog.courses) { course in
                                    Button(course.title) { selectedCourseID = course.id }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Text(selectedCourse.title)
                                        .font(.subheadline.weight(.semibold))
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(Theme.accent)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            LabeledContent("Course fee (before GST)", value: currency(selectedCourse.fee))
                            LabeledContent("Course fee with GST", value: currency(selectedCourse.feeWithGST))
                        }
                    }

                    GrantCalculatorForm(course: selectedCourse)
                }
                .padding(20)
            }
            .background(Theme.page)
            .navigationTitle("Grant Calculator")
            .onChange(of: catalog.courses) { _, courses in
                if !courses.contains(where: { $0.id == selectedCourseID }) {
                    selectedCourseID = courses.first?.id ?? CourseData.courses[0].id
                }
            }
        }
    }
}

// MARK: - Shared calculator form (used by the tab and by each course's detail page)

struct GrantCalculatorForm: View {
    let course: Course

    @State private var nationality: Nationality = .singaporeCitizen
    @State private var age = 35
    @State private var sponsorship: Sponsorship = .selfSponsored
    @State private var skillsFutureCredit = 500.0

    private var estimate: GrantEstimate {
        GrantEstimate(
            courseFee: course.fee,
            skillsFutureClaimable: course.skillsFutureClaimable,
            nationality: nationality,
            age: age,
            sponsorship: sponsorship,
            creditBalance: Decimal(skillsFutureCredit)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InfoCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Learner")

                    Picker("Nationality", selection: $nationality) {
                        ForEach(Nationality.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: $age, in: 16...90) {
                        LabeledContent("Age", value: "\(age)")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sponsorship")
                        Menu {
                            ForEach(Sponsorship.allCases) { item in
                                Button(item.rawValue) { sponsorship = item }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text(sponsorship.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Theme.accent)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            InfoCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("SkillsFuture Credit")
                    HStack {
                        Text("Available credit")
                        Spacer()
                        TextField("Credit", value: $skillsFutureCredit, format: .currency(code: "SGD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 150)
                            .disabled(!estimate.canUseSkillsFutureCredit)
                            .foregroundStyle(estimate.canUseSkillsFutureCredit ? .primary : .secondary)
                    }
                    Text("SkillsFuture Credit applies only to self-sponsored Singapore Citizens on claimable courses.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            InfoCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Estimate")

                    Label(estimate.grantName, systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)

                    Divider()

                    EstimateRow(title: "Course fee (before GST)", value: estimate.courseFee)
                    EstimateRow(title: "GST 9% (on original fee)", value: estimate.gst)
                    EstimateRow(title: "Course fee with GST", value: estimate.feeWithGST)
                    EstimateRow(title: "SSG grant (\(estimate.rateText))", value: -estimate.grant)
                    if estimate.canUseSkillsFutureCredit {
                        EstimateRow(title: "SkillsFuture Credit", value: -estimate.skillsFutureCreditApplied)
                    }

                    Divider()

                    EstimateRow(title: "Net fee payable", value: estimate.netFee, isTotal: true)
                }
            }

            InfoCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This is an estimate based on SSG funding rules for self-sponsored and employer-sponsored (SME) learners. Final payable amounts depend on official course approval, learner eligibility, and available SkillsFuture Credit balance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("TP Gateway — Grant Calculator and Funding Eligibility", destination: URL(string: "https://www.tpgateway.gov.sg/faq/grant-calculator-and-funding-eligibility")!)
                        .font(.footnote)
                }
            }
        }
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
                .foregroundStyle(value < 0 ? .green : (isTotal ? Theme.accent : .primary))
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            GrantCalculatorForm(course: CourseData.courses[0])
                .padding(20)
        }
        .background(Theme.page)
    }
}
