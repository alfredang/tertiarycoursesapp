import SwiftUI

enum Nationality: String, CaseIterable, Identifiable {
    case singaporeCitizen = "Singapore Citizen"
    case permanentResident = "Singapore PR"
    case others = "Others"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .singaporeCitizen: "Citizen"
        case .permanentResident: "PR"
        case .others: "Others"
        }
    }
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
    /// Non-WSQ / unfunded courses receive no SSG subsidy regardless of the learner profile.
    let ssgFunded: Bool
    let skillsFutureClaimable: Bool
    let nationality: Nationality
    let age: Int
    let sponsorship: Sponsorship
    let creditBalance: Decimal

    var fundingRate: Decimal {
        guard ssgFunded else { return 0 }
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
        guard ssgFunded else { return "Not SSG-funded — full fee payable" }
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
    @State private var selectedCourseID = CourseData.courses.first?.id ?? ""
    @State private var showCoursePicker = false

    private var selectedCourse: Course? {
        catalog.courses.first { $0.id == selectedCourseID } ?? catalog.courses.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let course = selectedCourse {
                        InfoCard {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel("Course")
                                Button {
                                    showCoursePicker = true
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(course.title)
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
                                .buttonStyle(.plain)
                                LabeledContent("Course fee (before GST)", value: currency(course.fee))
                                LabeledContent("Course fee with GST", value: currency(course.feeWithGST))
                            }
                        }

                        GrantCalculatorForm(course: course)
                    } else {
                        ContentUnavailableView(
                            "Catalog unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text("The bundled course catalog could not be loaded.")
                        )
                    }
                }
                .padding(20)
            }
            .background(Theme.page)
            .navigationTitle("Grant Calculator")
            .brandToolbar()
            .sheet(isPresented: $showCoursePicker) {
                CoursePickerSheet(courses: catalog.courses, selectedCourseID: $selectedCourseID)
            }
        }
    }
}

/// Searchable course chooser — the catalog is far too large for a flat menu.
struct CoursePickerSheet: View {
    let courses: [Course]
    @Binding var selectedCourseID: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var results: [Course] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return courses }
        return courses.filter { $0.searchIndex.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(results) { course in
                Button {
                    selectedCourseID = course.id
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(course.courseCode) · \(currency(course.feeWithGST)) w/GST")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if course.id == selectedCourseID {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search courses")
            .navigationTitle("Select Course")
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

// MARK: - Shared calculator form (used by the tab and by each course's detail page)

struct GrantCalculatorForm: View {
    let course: Course

    @State private var nationality: Nationality = .singaporeCitizen
    @State private var age = 35
    @State private var sponsorship: Sponsorship = .selfSponsored
    @State private var skillsFutureCreditText = ""
    @FocusState private var creditFieldFocused: Bool

    // Parse whatever the user typed ("350", "$1,200.50", …) into a Decimal; empty = 0.
    private var creditBalance: Decimal {
        Decimal(string: skillsFutureCreditText.filter { "0123456789.".contains($0) }) ?? 0
    }

    private var estimate: GrantEstimate {
        GrantEstimate(
            courseFee: course.fee,
            ssgFunded: course.isWSQCourse,
            skillsFutureClaimable: course.skillsFutureClaimable,
            nationality: nationality,
            age: age,
            sponsorship: sponsorship,
            creditBalance: creditBalance
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InfoCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Learner")

                    Picker("Nationality", selection: $nationality) {
                        ForEach(Nationality.allCases) { item in
                            Text(item.shortLabel).tag(item)
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
                        Text("Credit to claim")
                        Spacer()
                        HStack(spacing: 2) {
                            Text("S$")
                                .foregroundStyle(.secondary)
                            TextField("0", text: $skillsFutureCreditText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 110)
                                .focused($creditFieldFocused)
                                .disabled(!estimate.canUseSkillsFutureCredit)
                                .foregroundStyle(estimate.canUseSkillsFutureCredit ? .primary : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Text("Enter the SkillsFuture Credit you want to claim — it is deducted from the net fee. Applies only to self-sponsored Singapore Citizens on claimable courses.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            InfoCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Estimate")

                    Label(estimate.grantName,
                          systemImage: estimate.fundingRate > 0 ? "checkmark.seal.fill" : "info.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(estimate.fundingRate > 0 ? Theme.accent : Color.secondary)

                    Divider()

                    EstimateRow(title: "Course fee (before GST)", value: estimate.courseFee)
                    EstimateRow(title: "GST 9% (on original fee)", value: estimate.gst)
                    EstimateRow(title: "Course fee with GST", value: estimate.feeWithGST)
                    if estimate.fundingRate > 0 {
                        EstimateRow(title: "SSG grant (\(estimate.rateText))", value: -estimate.grant)
                    }
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { creditFieldFocused = false }
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
            GrantCalculatorForm(course: CourseData.courses[0])  // preview only
                .padding(20)
        }
        .background(Theme.page)
    }
}
