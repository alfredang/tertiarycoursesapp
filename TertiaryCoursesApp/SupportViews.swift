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
            "What would make this app more useful? e.g. class reminders, offline materials…"
        case .bug:
            "What went wrong? Tell us what you did, what you expected, and what happened instead."
        case .comment:
            "Any comments about the app or our courses — we read everything."
        }
    }
}

/// App feedback, sent to the site's team on WhatsApp.
struct FeedbackView: View {
    var embedded = false

    @State private var category: FeedbackCategory = .feature
    @State private var title = ""
    @State private var message = ""
    @FocusState private var focusedField: Field?

    private enum Field { case title, message }

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InfoCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("We'd love to hear from you", systemImage: "heart.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                        Text("Suggest features, report bugs, or leave a comment. Your feedback goes straight to our team on WhatsApp.")
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
                                Image(systemName: item.symbol).font(.title3)
                                Text(item.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(category == item ? Color.white : Theme.accent)
                            .background(category == item ? Theme.brand : Theme.accentSoft,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .tint(Theme.brand)
                .controlSize(.large)
                .disabled(!canSend)

                Text("Sent to \(Site.siteName) (\(Site.whatsAppLabel)) via WhatsApp.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
        }
        .background(Theme.page)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    private func send() {
        var body = "\(category.rawValue) — \(Site.appName) app\n"
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { body += "*\(t)*\n" }
        body += message.trimmingCharacters(in: .whitespacesAndNewlines)
        openWhatsApp(number: Site.whatsApp, body: body)
    }
}

struct AboutView: View {
    var embedded = false

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content.brandToolbar() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                InfoCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Site.appName).font(.title3.bold())
                        Text("The app for learners and trainers of \(Site.siteName). Sign in with your email code or password to see your current, upcoming and past classes, your class calendar and materials, and get reminders before each class. Learners check in to class, give course feedback, and download their certificates and billing records. Trainers take attendance and open the class materials. You can also browse our courses.")
                            .foregroundStyle(.secondary)
                    }
                }

                SectionLabel("Contact")
                InfoCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Link(destination: Site.baseURL) {
                            Label(Site.websiteLabel, systemImage: "globe")
                        }
                        .padding(.vertical, 12)
                        Divider()
                        Link(destination: URL(string: "tel:" + Site.phone.filter { $0.isNumber || $0 == "+" })!) {
                            Label(Site.phone, systemImage: "phone.fill")
                        }
                        .padding(.vertical, 12)
                        Divider()
                        Link(destination: URL(string: "mailto:" + Site.email)!) {
                            Label(Site.email, systemImage: "envelope.fill")
                        }
                        .padding(.vertical, 12)
                        Divider()
                        Button {
                            openWhatsApp(number: Site.whatsApp, body: "Hi, I have a question about \(Site.siteName).")
                        } label: {
                            Label("WhatsApp \(Site.whatsAppLabel)", systemImage: "message.fill")
                        }
                        .padding(.vertical, 12)
                    }
                }

                SectionLabel("Developer")
                InfoCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Site.academy).font(.subheadline.weight(.semibold))
                        Link(destination: Site.developerURL) {
                            Label("tertiaryinfotech.com", systemImage: "link")
                        }
                        Link(destination: Site.privacyURL) {
                            Label("Privacy Policy", systemImage: "hand.raised.fill")
                        }
                    }
                }

                SectionLabel("Data source")
                InfoCard {
                    Text("Courses, classes, attendance, certificates and billing come from your account on \(Site.websiteLabel).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                InfoCard {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionString).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.page)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
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
