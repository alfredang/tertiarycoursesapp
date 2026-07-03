import SwiftUI
import UIKit

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
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))

                    Button(action: send) {
                        Label("Send via WhatsApp", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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
