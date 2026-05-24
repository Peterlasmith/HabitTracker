import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Create Account"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Your habit history should follow you.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 14) {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding()
                    .background(.white.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                SecureField("Password", text: $password)
                    .padding()
                    .background(.white.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Button {
                Task {
                    if mode == .signIn {
                        await environment.signIn(email: email, password: password)
                    } else {
                        await environment.signUp(email: email, password: password)
                    }
                }
            } label: {
                Text(mode.rawValue)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(AppTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .disabled(email.isEmpty || password.isEmpty)
            .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1)

            Text("Email/password is wired for Supabase Auth. Add your project URL and anon key in the app plist to activate it.")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)

            Spacer()
        }
        .padding(24)
    }
}
