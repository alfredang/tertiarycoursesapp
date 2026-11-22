import SwiftUI
import AuthenticationServices
import CryptoKit

/// Sign in with an emailed one-time code (the default) or the website password.
/// Layout follows the TIA house sign-in: academy logo and name, the app name, one card.
/// A quiet "Admin sign-in" link in the footer opens the admin page (Continue with Google).
struct SignInView: View {
    @EnvironmentObject private var store: LearnerStore

    private enum Method { case code, password }

    @State private var method: Method = .code
    @State private var email = UserDefaults.standard.string(forKey: "rememberedEmail") ?? ""
    @State private var remember = UserDefaults.standard.object(forKey: "rememberEmail") as? Bool ?? true
    @State private var password = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?
    @State private var info: String?
    @State private var google = GoogleAdminSignIn()
    @State private var showAdmin = false
    @State private var adminError: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password, code }

    private var emailValid: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".") && e.count >= 5
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // Academy logo, name, then this app's name
                    AcademyBrandHeader(appName: Site.appName)
                        .padding(.top, 12)

                    // The sign-in card
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sign in").font(.title2.bold())
                            Text(codeSent && method == .code
                                 ? "Enter the 6-digit code we emailed you."
                                 : "Enter the email you registered with to continue.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
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

                        inputRow(icon: "envelope.fill") {
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .email)
                                .submitLabel(method == .password ? .next : .continue)
                                .onSubmit {
                                    if method == .password { focus = .password } else { Task { await sendCode() } }
                                }
                                .onChange(of: email) { _, _ in codeSent = false }
                                .accessibilityIdentifier("email")
                        }

                        if method == .password {
                            inputRow(icon: "lock.fill") {
                                SecureField("Website password", text: $password)
                                    .textContentType(.password)
                                    .focused($focus, equals: .password)
                                    .submitLabel(.go)
                                    .onSubmit { Task { await signInWithPassword() } }
                                    .accessibilityIdentifier("password")
                            }
                        } else if codeSent {
                            inputRow(icon: "number") {
                                TextField("6-digit code", text: $code)
                                    .textContentType(.oneTimeCode)
                                    .keyboardType(.numberPad)
                                    .focused($focus, equals: .code)
                                    .onChange(of: code) { _, new in
                                        code = String(new.filter(\.isNumber).prefix(6))
                                    }
                                    .accessibilityIdentifier("code")
                            }
                        }

                        Toggle(isOn: $remember) {
                            Text("Remember my email").font(.subheadline)
                        }
                        .tint(Theme.brand)
                        .onChange(of: remember) { _, on in
                            UserDefaults.standard.set(on, forKey: "rememberEmail")
                            if !on { UserDefaults.standard.removeObject(forKey: "rememberedEmail") }
                        }

                        Button {
                            Task {
                                switch method {
                                case .password: await signInWithPassword()
                                case .code: if codeSent { await verify() } else { await sendCode() }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if busy { ProgressView().tint(.white) } else { Image(systemName: "arrow.right") }
                                Text(method == .password ? "Sign In" : (codeSent ? "Verify & Sign In" : "Continue"))
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(.white)
                            .background(Theme.brand.opacity(primaryDisabled ? 0.45 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(primaryDisabled)
                        .accessibilityIdentifier(method == .password ? "signIn" : "continue")

                        if let info {
                            Label(info, systemImage: "envelope.badge").font(.footnote).foregroundStyle(Theme.accent)
                        }
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                        }

                        HStack {
                            if method == .code, codeSent {
                                Button("Send a new code") { Task { await sendCode() } }.disabled(busy)
                            } else if method == .password {
                                Link("Forgot your password?", destination: Site.baseURL.appendingPathComponent("customer/account/forgotpassword/"))
                            }
                            Spacer()
                            Button(method == .code ? "Use password instead" : "Use email code instead") {
                                method = method == .code ? .password : .code
                                error = nil
                                info = nil
                            }
                            .accessibilityIdentifier("switchMethod")
                        }
                        .font(.footnote.weight(.medium))
                    }
                    .padding(20)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.cardBorder))

                    VStack(spacing: 10) {
                        Text("Learners: your account is created when you register for a course on \(Site.websiteLabel).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        // Deliberately quiet: staff know it is here. Opens the admin page.
                        Button("Admin sign-in") {
                            error = nil
                            showAdmin = true
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .disabled(busy)
                        .accessibilityIdentifier("adminSignIn")
                    }
                    .padding(.horizontal, 8)
                }
                .padding(20)
            }
            .background(
                LinearGradient(colors: [Theme.page, Theme.accentSoft], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            )
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdmin) {
                AdminSignInPage(appName: Site.appName, busy: busy, error: adminError) { remember in
                    Task { await signInAsAdmin(remember: remember) }
                }
            }
        }
    }

    private var primaryDisabled: Bool {
        if busy || !emailValid { return true }
        switch method {
        case .password: return password.isEmpty
        case .code: return codeSent && code.count != 6
        }
    }

    private func inputRow<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Theme.page, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private func rememberEmail() {
        if remember { UserDefaults.standard.set(email.trimmingCharacters(in: .whitespaces), forKey: "rememberedEmail") }
    }

    /// Admin sign-in: Google in the system sign-in sheet, for the allowed admin account only.
    private func signInAsAdmin(remember: Bool) async {
        busy = true
        adminError = nil
        defer { busy = false }
        do {
            let result = try await google.start(ephemeral: !remember)
            try await store.signInWithGoogle(code: result.code, verifier: result.verifier)
            AdminRemember.signedIn(email: store.learner?.email ?? "")
            showAdmin = false
        } catch GoogleAdminSignIn.Failure.cancelled {
            // Closed the Google sheet: nothing to report.
        } catch {
            adminError = error.localizedDescription
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
            rememberEmail()
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
            rememberEmail()
        } catch {
            self.error = error.localizedDescription
        }
    }
}


/// Admin sign-in with Google, through the website's own Google sign-in. The app
/// sends the hash of a random verifier; the site answers at this app's URL scheme
/// with a single-use code, which only this verifier can exchange for a session.
@MainActor
final class GoogleAdminSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Failure: LocalizedError {
        case cancelled
        case message(String)
        var errorDescription: String? {
            switch self {
            case .cancelled: "Sign-in was cancelled."
            case .message(let m): m
            }
        }
    }

    private var session: ASWebAuthenticationSession?

    /// `ephemeral`: do not keep the Google sign-in in the browser (Remember me off).
    func start(ephemeral: Bool = false) async throws -> (code: String, verifier: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = bytes.map { String(format: "%02x", $0) }.joined()
        let challenge = SHA256.hash(data: Data(verifier.utf8)).map { String(format: "%02x", $0) }.joined()
        var components = URLComponents(url: Site.baseURL.appendingPathComponent("mobileapi/auth/googlestart"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "challenge", value: challenge)]
        let scheme = "tclms" + Site.code.lowercased()

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let s = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: scheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { continuation.resume(throwing: Failure.cancelled) }
                else { continuation.resume(throwing: Failure.message("Google sign-in could not start. Please try again.")) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = ephemeral
            session = s
            if !s.start() { continuation.resume(throwing: Failure.message("Google sign-in could not start. Please try again.")) }
        }
        session = nil
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let message = items.first(where: { $0.name == "error" })?.value { throw Failure.message(message) }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw Failure.message("Google sign-in did not complete. Please try again.")
        }
        return (code, verifier)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
}
