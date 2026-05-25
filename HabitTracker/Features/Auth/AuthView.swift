import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @FocusState private var focusedField: Field?

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Create Account"
        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .signIn:
                return "Welcome back. Pick up right where you left off."
            case .signUp:
                return "Create your account to keep your streaks and trends in sync."
            }
        }

        var buttonTitle: String {
            switch self {
            case .signIn:
                return "Sign In"
            case .signUp:
                return "Create Account"
            }
        }
    }

    private enum Field {
        case email
        case password
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var inlineValidationMessage: String? {
        if trimmedEmail.isEmpty || trimmedPassword.isEmpty {
            return nil
        }

        if !trimmedEmail.contains("@") || !trimmedEmail.contains(".") {
            return "Enter a valid email address."
        }

        if mode == .signUp, trimmedPassword.count < 8 {
            return "Use at least 8 characters so your account is secure."
        }

        return nil
    }

    private var activeErrorMessage: String? {
        environment.errorMessage ?? inlineValidationMessage
    }

    private var shouldHighlightFields: Bool {
        inlineValidationMessage != nil
    }

    private var isSubmitDisabled: Bool {
        environment.isBusy || trimmedEmail.isEmpty || trimmedPassword.isEmpty || inlineValidationMessage != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                authCard
                configurationFootnote
            }
            .frame(maxWidth: 460, alignment: .leading)
            .padding(24)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 14, height: 14)

                Text("HabitClaw")
                    .font(AppTheme.serif(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Your rhythm should follow you.")
                    .font(AppTheme.serif(size: 31, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(mode.subtitle)
                    .font(AppTheme.sans(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var authCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Account")
                .font(AppTheme.sans(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(1.1)

            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in
                environment.errorMessage = nil
            }

            VStack(alignment: .leading, spacing: 14) {
                inputGroup(title: "Email") {
                    TextField("you@example.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .password
                        }
                        .appInput()
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(shouldHighlightFields ? AppTheme.error.opacity(0.45) : AppTheme.border, lineWidth: 1)
                        }
                        .onChange(of: email, initial: false) { _, newValue in
                            let normalized = newValue.replacingOccurrences(of: " ", with: "")
                            if normalized != newValue {
                                email = normalized
                                return
                            }
                            environment.errorMessage = nil
                        }
                }

                inputGroup(title: "Password") {
                    SecureField(mode == .signUp ? "Choose a password" : "Enter your password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            submit()
                        }
                        .appInput()
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(shouldHighlightFields ? AppTheme.error.opacity(0.45) : AppTheme.border, lineWidth: 1)
                        }
                        .onChange(of: password, initial: false) { _, _ in
                            environment.errorMessage = nil
                        }
                }
            }

            if let activeErrorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: shouldHighlightFields ? "exclamationmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(shouldHighlightFields ? AppTheme.error : AppTheme.warning)
                        .padding(.top, 1)

                    Text(activeErrorMessage)
                        .font(AppTheme.sans(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(shouldHighlightFields ? AppTheme.errorBackground : AppTheme.warningSoft)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke((shouldHighlightFields ? AppTheme.error : AppTheme.warning).opacity(0.14), lineWidth: 1)
                }
            }

            if mode == .signUp {
                Text("Use 8 or more characters so your account is easy to keep and hard to crack.")
                    .font(AppTheme.sans(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Button(action: submit) {
                HStack(spacing: 10) {
                    if environment.isBusy {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(environment.isBusy ? "Working..." : mode.buttonTitle)
                        .font(AppTheme.sans(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isSubmitDisabled ? AppTheme.accent.opacity(0.45) : AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: isSubmitDisabled ? .clear : AppTheme.accent.opacity(0.22), radius: 14, x: 0, y: 10)
            }
            .disabled(isSubmitDisabled)
        }
        .appCard(fill: AppTheme.surfaceStrong, padding: 20, cornerRadius: 26)
    }

    private var configurationFootnote: some View {
        Text("Email/password is wired for Supabase Auth. Add your project URL and anon key in the app plist to activate it.")
            .font(AppTheme.sans(size: 12))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: 420, alignment: .leading)
    }

    @ViewBuilder
    private func inputGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTheme.sans(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)

            content()
        }
    }

    private func submit() {
        guard !isSubmitDisabled else { return }
        environment.errorMessage = nil
        focusedField = nil

        Task {
            if mode == .signIn {
                await environment.signIn(email: trimmedEmail, password: trimmedPassword)
            } else {
                await environment.signUp(email: trimmedEmail, password: trimmedPassword)
            }
        }
    }
}
