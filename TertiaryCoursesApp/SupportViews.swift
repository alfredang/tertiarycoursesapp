import SwiftUI
import UIKit

enum FeedbackCategory: String, CaseIterable, Identifiable {
    case feature = "Feature Idea"
    case bug = "Bug Report"
    case comment = "Comment"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .feature: "lightbulb.fill"
        case .bug: "ant.fill"
        case .comment: "text.bubble.fill"
        }
    }

    var prompt: String {
        switch self {
        case .feature:
            "What feature would make this app more useful? e.g. course schedules, favourites, reminders…"
        case .bug:
            "What went wrong? Tell us what you did, what you expected, and what happened instead."
        case .comment:
            "Any comments about the app or our courses — we read everything."
        }
    }
}

struct FeedbackView: View {
    @State private var category: FeedbackCategory = .feature
    @State private var title = ""
    @State private var message = ""
    @FocusState private var focusedField: Field?
    private let whatsAppNumber = "6588666375"

    private enum Field {
        case title, message
    }

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    InfoCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("We'd love to hear from you", systemImage: "heart.fill")
                                .font(.headline)
                                .foregroundStyle(Theme.accent)
                            Text("Suggest features you'd like, report bugs you found, or just leave a comment. Your feedback goes straight to our team on WhatsApp.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SectionLabel("What kind of feedback?")
                    HStack(spacing: 10) {
                        ForEach(FeedbackCategory.allCases) { item in
                            Button {
                                category = item
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: item.symbol)
                                        .font(.title3)
                                    Text(item.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(category == item ? .white : Theme.accent)
                                .background(
                                    category == item ? Theme.accent : Theme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SectionLabel("Your feedback")
                    TextField("Short title", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .message }

                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text(category.prompt)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                        }
                        TextEditor(text: $message)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 160)
                            .focused($focusedField, equals: .message)
                    }
                    .padding(8)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))

                    Button(action: send) {
                        Label("Send via WhatsApp", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSend)

                    Text("Sent to Tertiary Courses Singapore (+65 8866 6375) via WhatsApp.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(20)
            }
            .background(Theme.page)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Feedback")
            .brandToolbar()
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    private func send() {
        var body = "\(category.rawValue) — Tertiary Courses SG app\n"
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
    private let developerURL = URL(string: "https://www.tertiaryinfotech.com/")!
    private let tpGatewayURL = URL(string: "https://www.tpgateway.gov.sg/faq/grant-calculator-and-funding-eligibility")!
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
                            Text("Browse the Tertiary Courses Singapore catalog, estimate SSG grants (Baseline, MCES, and SME) with SkillsFuture Credit, and get your net course fee — all in one app.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    SectionLabel("Official site")
                    InfoCard {
                        VStack(alignment: .leading, spacing: 0) {
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

                    SectionLabel("Developer")
                    InfoCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tertiary Infotech Academy Pte. Ltd.")
                                .font(.subheadline.weight(.semibold))
                            Link(destination: developerURL) {
                                Label("tertiaryinfotech.com", systemImage: "link")
                            }
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
                            Link(destination: tpGatewayURL) {
                                Label("TP Gateway grant calculator & funding eligibility", systemImage: "checkmark.seal")
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
            .brandToolbar()
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
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

func currency(_ amount: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "SGD"
    formatter.currencySymbol = "S$"
    formatter.maximumFractionDigits = 2
    return formatter.string(from: amount as NSDecimalNumber) ?? "S$\(amount)"
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
