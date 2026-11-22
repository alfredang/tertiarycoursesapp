import SwiftUI

/// Sign in with an emailed one-time code, or with the website password.
struct SignInView: View {
    @EnvironmentObject private var store: LearnerStore

    private enum Method: String, CaseIterable, Identifiable {
        case code = "Email Code"
        case password = "Password"
        var id: String { rawValue }
    }

    @State private var method: Method = .code
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?
    @State private var info: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password, code }

    private var emailValid: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".") && e.count >= 5
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Learner and trainer sign in")
                            .font(.title2.bold())
                        Text("Use the email you registered with on \(Site.websiteLabel) to see your classes, materials, attendance, certificates and billing.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sign in as").font(.subheadline.weight(.semibold))
                        Picker("Sign in as", selection: $store.loginRole) {
                            Text("Learner").tag("learner")
                            Text("Trainer").tag("trainer")
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("loginRole")
                        Text(store.loginRole == "trainer"
                             ? "See the classes you teach, attendance, payout and training hours."
                             : "See the courses you are taking. Trainers attending a course sign in as a learner.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Sign-in method", selection: $method) {
                        ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: method) { _, _ in
                        error = nil
                        info = nil
                    }

                    InfoCard {
                        VStack(alignment: .leading, spacing: 14) {
                            field("Email") {
                                TextField("you@example.com", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focus, equals: .email)
                                    .submitLabel(method == .password ? .next : .send)
                                    .onSubmit {
                                        if method == .password { focus = .password } else { Task { await sendCode() } }
                                    }
                                    .onChange(of: email) { _, _ in codeSent = false }
                                    .accessibilityIdentifier("email")
                            }

                            if method == .password {
                                field("Password") {
                                    SecureField("Your website password", text: $password)
                                        .textContentType(.password)
                                        .focused($focus, equals: .password)
                                        .submitLabel(.go)
                                        .onSubmit { Task { await signInWithPassword() } }
                                        .accessibilityIdentifier("password")
                                }
                                Button {
                                    Task { await signInWithPassword() }
                                } label: {
                                    busyLabel("Sign In")
                                }
                                .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                                .controlSize(.large)
                                .disabled(busy || !emailValid || password.isEmpty)
                                .accessibilityIdentifier("signIn")

                                Link("Forgot your password?", destination: Site.baseURL.appendingPathComponent("customer/account/forgotpassword/"))
                                    .font(.footnote)
                            } else if codeSent {
                                field("6-digit code") {
                                    TextField("123456", text: $code)
                                        .textContentType(.oneTimeCode)
                                        .keyboardType(.numberPad)
                                        .focused($focus, equals: .code)
                                        .onChange(of: code) { _, new in
                                            code = String(new.filter(\.isNumber).prefix(6))
                                        }
                                }
                                Button {
                                    Task { await verify() }
                                } label: {
                                    busyLabel("Verify & Sign In")
                                }
                                .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                                .controlSize(.large)
                                .disabled(busy || code.count != 6)

                                Button("Send a new code") { Task { await sendCode() } }
                                    .font(.footnote)
                                    .disabled(busy)
                            } else {
                                Button {
                                    Task { await sendCode() }
                                } label: {
                                    busyLabel("Email Me a Code")
                                }
                                .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                                .controlSize(.large)
                                .disabled(busy || !emailValid)
                            }
                        }
                    }

                    if let info {
                        Label(info, systemImage: "envelope.badge")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    InfoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("New to \(Site.siteName)?", systemImage: "sparkles")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Text("Learners: your account is created when you register for a course on \(Site.websiteLabel). Trainers: use your \(Site.websiteLabel) trainer login.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.page)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .brandToolbar()
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(12)
                .background(Theme.page, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
        }
    }

    private func busyLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            if busy { ProgressView().tint(.white) }
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }

    private func sendCode() async {
        guard emailValid, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            info = try await store.sendCode(email: email)
            codeSent = true
            code = ""
            focus = .code
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verify() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await store.verifyCode(email: email, code: code)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func signInWithPassword() async {
        guard emailValid, !password.isEmpty, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await store.signIn(email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
