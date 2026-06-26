import SwiftUI

struct AuthFlowView: View {
    var body: some View {
        NavigationStack {
            LoginView()
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tallystitch").foregroundStyle(Palette.clay700).font(.subheadline.weight(.semibold))
                Text("Welcome back").font(.largeTitle.weight(.semibold))
                Text("Log in to your workshop.").foregroundStyle(Palette.ink500)

                LabeledField(label: "Email", text: $email, keyboard: .emailAddress, secure: false)
                LabeledField(label: "Password", text: $password, keyboard: .default, secure: true)

                if let error { Text(error).foregroundStyle(Palette.danger).font(.callout) }
                if let message { Text(message).foregroundStyle(Palette.sage700).font(.callout) }

                Button(busy ? "Signing in…" : "Log in") { Task { await signIn() } }
                    .buttonStyle(PrimaryButton()).disabled(busy)

                Button("Email me a magic link instead") { Task { await magicLink() } }
                    .foregroundStyle(Palette.clay700).font(.body.weight(.medium))
                    .frame(maxWidth: .infinity).disabled(busy)

                HStack {
                    Text("New here?").foregroundStyle(Palette.ink500)
                    NavigationLink("Start a free trial") { SignupView() }
                        .foregroundStyle(Palette.clay700)
                }
                .frame(maxWidth: .infinity).padding(.top, 8)
            }
            .padding(24)
        }
        .background(Palette.cream50)
    }

    private func signIn() async {
        guard !email.isEmpty, !password.isEmpty else { error = "Please fill in both fields."; return }
        busy = true; error = nil
        do { try await auth.signIn(email: email, password: password) }
        catch { self.error = error.localizedDescription }
        busy = false
    }

    private func magicLink() async {
        guard !email.isEmpty else { error = "Enter your email first."; return }
        busy = true; error = nil; message = nil
        do { try await auth.sendMagicLink(email: email); message = "Check your email for a magic link." }
        catch { self.error = error.localizedDescription }
        busy = false
    }
}

struct SignupView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Start free trial").font(.largeTitle.weight(.semibold))
                Text("14 days, no credit card.").foregroundStyle(Palette.ink500)

                LabeledField(label: "Email", text: $email, keyboard: .emailAddress, secure: false)
                LabeledField(label: "Choose a password (8+ chars)", text: $password, keyboard: .default, secure: true)

                if let error { Text(error).foregroundStyle(Palette.danger).font(.callout) }
                if let message { Text(message).foregroundStyle(Palette.sage700).font(.callout) }

                Button(busy ? "Creating…" : "Create my workshop") { Task { await signUp() } }
                    .buttonStyle(PrimaryButton()).disabled(busy)
            }
            .padding(24)
        }
        .background(Palette.cream50)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signUp() async {
        guard !email.isEmpty, password.count >= 8 else { error = "Email + a password of 8+ characters required."; return }
        busy = true; error = nil; message = nil
        do {
            let hasSession = try await auth.signUp(email: email, password: password)
            if !hasSession { message = "Check your email to confirm your account, then log in." }
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}

/// A labelled text field — the SwiftUI equivalent of the RN `Field`.
struct LabeledField: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var secure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink700)
            Group {
                if secure { SecureField("", text: $text) }
                else { TextField("", text: $text).keyboardType(keyboard).autocapitalization(.none).autocorrectionDisabled() }
            }
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.cream200, lineWidth: 1))
        }
    }
}
