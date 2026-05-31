import Foundation
import Security

@MainActor
protocol AuthService: AnyObject {
    var currentUser: AppUser? { get }
    func restoreSession() async throws -> AppUser?
    func signIn(email: String, password: String) async throws -> AppUser
    func signUp(email: String, password: String) async throws -> AppUser
    func deleteAccount(currentPassword: String) async throws
    func signOut() async throws
    func authorizationHeader() -> String?
}

@MainActor
final class SupabaseAuthService: ObservableObject, AuthService {
    @Published private(set) var currentUser: AppUser?

    private struct DeleteAccountRPCUnavailable: Error {}

    private let configuration: SupabaseConfiguration
    private let urlSession: URLSession
    private let sessionStore: SessionStore

    init(
        configuration: SupabaseConfiguration = .fromBundle(),
        urlSession: URLSession = .shared,
        sessionStore: SessionStore = .init()
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.sessionStore = sessionStore
    }

    func restoreSession() async throws -> AppUser? {
        guard let session = try sessionStore.read() else {
            currentUser = nil
            return nil
        }

        do {
            let user = try await userForValidSession(from: session)
            currentUser = user
            return user
        } catch {
            if shouldDiscardStoredSession(for: error) {
                try? sessionStore.clear()
                currentUser = nil
                return nil
            }
            throw error
        }
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        try validateCredentials(email: email, password: password, mode: .signIn)
        let session = try await authenticate(path: "auth/v1/token", queryItems: [
            URLQueryItem(name: "grant_type", value: "password")
        ], body: [
            "email": email,
            "password": password
        ])
        try sessionStore.write(session)
        let user = AppUser(id: session.user.id, email: session.user.email)
        currentUser = user
        return user
    }

    func signUp(email: String, password: String) async throws -> AppUser {
        try validateCredentials(email: email, password: password, mode: .signUp)
        let data = try await performRequest(path: "auth/v1/signup", body: [
            "email": email,
            "password": password
        ])

        if let session = try? JSONDecoder.supabase.decode(SupabaseSession.self, from: data) {
            try sessionStore.write(session)
            let user = AppUser(id: session.user.id, email: session.user.email)
            currentUser = user
            return user
        }

        if let response = try? JSONDecoder.supabase.decode(SupabaseSignUpResponse.self, from: data) {
            if let session = response.session {
                try sessionStore.write(session)
                let user = AppUser(id: session.user.id, email: session.user.email)
                currentUser = user
                return user
            }

            if let user = response.user {
                do {
                    return try await signIn(email: email, password: password)
                } catch {
                    throw AppError.network("Account created for \(user.email), but automatic sign-in failed: \(error.localizedDescription)")
                }
            }
        }

        if let user = try? JSONDecoder.supabase.decode(SupabaseUser.self, from: data) {
            do {
                return try await signIn(email: email, password: password)
            } catch {
                throw AppError.network("Account created for \(user.email), but automatic sign-in failed: \(error.localizedDescription)")
            }
        }

        throw AppError.network("Received an unexpected signup response from Supabase.")
    }

    func signOut() async throws {
        currentUser = nil
        try sessionStore.clear()
    }

    func deleteAccount(currentPassword: String) async throws {
        guard let user = currentUser else {
            throw AppError.network("Sign in again before deleting your account.")
        }

        let trimmedPassword = currentPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else {
            throw AppError.network("Enter your password to confirm account deletion.")
        }

        _ = try await authenticate(path: "auth/v1/token", queryItems: [
            URLQueryItem(name: "grant_type", value: "password")
        ], body: [
            "email": user.email,
            "password": trimmedPassword
        ])

        guard let authHeader = authorizationHeader() else {
            throw AppError.network("Your session expired. Sign in again to delete your account.")
        }

        do {
            try await deleteAccountViaRPC(authHeader: authHeader)
        } catch is DeleteAccountRPCUnavailable {
            try await deleteAccountViaEdgeFunction(authHeader: authHeader, currentPassword: trimmedPassword)
        }

        currentUser = nil
        try sessionStore.clear()
    }

    func authorizationHeader() -> String? {
        guard let session = try? sessionStore.read() else { return nil }
        let token = session.accessToken
        return "Bearer \(token)"
    }

    private func deleteAccountViaRPC(authHeader: String) async throws {
        var request = URLRequest(url: endpointURL(path: "rest/v1/rpc/delete_my_account", queryItems: []))
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Missing HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder.supabase.decode(SupabaseError.self, from: data).bestMessage)
                ?? String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)

            if httpResponse.statusCode == 404, isDeleteAccountRPCUnavailableMessage(message) {
                throw DeleteAccountRPCUnavailable()
            }

            throw AppError.network(normalizedErrorMessage(message, statusCode: httpResponse.statusCode))
        }
    }

    private func deleteAccountViaEdgeFunction(authHeader: String, currentPassword: String) async throws {
        var request = URLRequest(url: endpointURL(path: "functions/v1/delete-account", queryItems: []))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "current_password": currentPassword
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
    }

    private func isDeleteAccountRPCUnavailableMessage(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("could not find the function")
            || lowercased.contains("function public.delete_my_account")
            || lowercased.contains("schema cache")
    }

    private func fetchCurrentUser(accessToken: String) async throws -> AppUser {
        var request = URLRequest(url: endpointURL(path: "auth/v1/user", queryItems: []))
        request.httpMethod = "GET"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
        let user = try JSONDecoder.supabase.decode(SupabaseUser.self, from: data)
        return AppUser(id: user.id, email: user.email)
    }

    private func userForValidSession(from session: StoredSession) async throws -> AppUser {
        do {
            return try await fetchCurrentUser(accessToken: session.accessToken)
        } catch {
            guard shouldAttemptSessionRefresh(for: error),
                  let refreshToken = session.refreshToken?.nilIfEmpty
            else {
                throw error
            }

            let refreshedSession = try await refreshSession(refreshToken: refreshToken)
            try sessionStore.write(refreshedSession)
            return AppUser(id: refreshedSession.user.id, email: refreshedSession.user.email)
        }
    }

    private func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        let data = try await performRequest(path: "auth/v1/token", queryItems: [
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ], body: [
            "refresh_token": refreshToken
        ])
        return try JSONDecoder.supabase.decode(SupabaseSession.self, from: data)
    }

    private func authenticate(path: String, queryItems: [URLQueryItem], body: [String: String]) async throws -> SupabaseSession {
        let data = try await performRequest(path: path, queryItems: queryItems, body: body)
        return try JSONDecoder.supabase.decode(SupabaseSession.self, from: data)
    }

    private func performRequest(path: String, body: [String: String]) async throws -> Data {
        try await performRequest(path: path, queryItems: [], body: body)
    }

    private func performRequest(path: String, queryItems: [URLQueryItem], body: [String: String]) async throws -> Data {
        var request = URLRequest(url: endpointURL(path: path, queryItems: queryItems))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func endpointURL(path: String, queryItems: [URLQueryItem]) -> URL {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let baseURL = configuration.url.appending(path: normalizedPath)
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url ?? baseURL
    }

    private func validateCredentials(email: String, password: String, mode: AuthMode) throws {
        if configuration.anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AppError.configuration("Supabase isn't configured yet. Add your project URL and anon key in the app plist to enable \(mode.actionNoun).")
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            throw AppError.network("Enter a valid email address to \(mode.actionVerb).")
        }

        if mode == .signUp, password.count < 8 {
            throw AppError.network("Use at least 8 characters for your password.")
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Missing HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder.supabase.decode(SupabaseError.self, from: data).bestMessage)
                ?? String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AppError.network(normalizedErrorMessage(message, statusCode: httpResponse.statusCode))
        }
    }

    private func normalizedErrorMessage(_ message: String, statusCode: Int) -> String {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = normalized.lowercased()

        if statusCode == 400 || statusCode == 401 {
            if lowercased.contains("invalid login credentials") || lowercased.contains("invalid_grant") {
                return "That email and password combination didn't match. Double-check your details and try again."
            }

            if lowercased.contains("email not confirmed") {
                return "Check your inbox to confirm your email before signing in."
            }
        }

        if statusCode == 403 {
            if lowercased.contains("bad_jwt") || lowercased.contains("invalid jwt") || lowercased.contains("token is expired") {
                return "Your session expired. Sign in again to keep going."
            }
        }

        if lowercased.contains("user already registered") {
            return "An account with that email already exists. Try signing in instead."
        }

        if lowercased.contains("password should be at least") {
            return "Use at least 8 characters for your password."
        }

        if lowercased.contains("unable to validate email address") || lowercased.contains("invalid email") {
            return "Enter a valid email address and try again."
        }

        if lowercased.contains("requested function was not found")
            || lowercased.contains("could not find the function")
            || lowercased.contains("schema cache")
        {
            return "Account deletion isn't enabled on this Supabase project yet. Apply the latest Supabase schema/backend updates and try again."
        }

        return normalized
    }

    private func shouldDiscardStoredSession(for error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("bad_jwt")
            || message.contains("invalid jwt")
            || message.contains("token is expired")
            || message.contains("session expired")
            || message.contains("refresh token")
            || message.contains("invalid refresh token")
            || message.contains("invalid_grant")
    }

    private func shouldAttemptSessionRefresh(for error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("bad_jwt")
            || message.contains("invalid jwt")
            || message.contains("token is expired")
            || message.contains("session expired")
    }
}

private extension SupabaseAuthService {
    enum AuthMode {
        case signIn
        case signUp

        var actionVerb: String {
            switch self {
            case .signIn:
                return "sign in"
            case .signUp:
                return "create an account"
            }
        }

        var actionNoun: String {
            switch self {
            case .signIn:
                return "sign-in"
            case .signUp:
                return "account creation"
            }
        }
    }
}

struct SupabaseConfiguration {
    let url: URL
    let anonKey: String

    static func fromBundle(bundle: Bundle = .main) -> Self {
        let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        let anonKey = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
        return .init(url: URL(string: urlString) ?? URL(string: "https://example.supabase.co")!, anonKey: anonKey)
    }
}

struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let user: SupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

struct SupabaseUser: Codable {
    let id: UUID
    let email: String
}

struct SupabaseError: Codable {
    let message: String?
    let msg: String?
    let error: String?
    let errorDescription: String?
    let code: String?

    enum CodingKeys: String, CodingKey {
        case message
        case msg
        case error
        case errorDescription = "error_description"
        case code
    }

    var bestMessage: String {
        [
            message,
            msg,
            errorDescription,
            error,
            code
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? "Unknown Supabase error."
    }
}

struct SupabaseSignUpResponse: Codable {
    let user: SupabaseUser?
    let session: SupabaseSession?
}

struct StoredSession: Codable {
    let accessToken: String
    let refreshToken: String?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct SessionStore {
    private let service: String
    private let account: String

    init(service: String = "HabitTracker.auth", account: String = "supabase.session") {
        self.service = service
        self.account = account
    }

    func write(_ session: SupabaseSession) throws {
        let data = try JSONEncoder().encode(StoredSession(accessToken: session.accessToken, refreshToken: session.refreshToken))
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = query.merging([
            kSecValueData as String: data
        ]) { _, new in new }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError.storage("Unable to write session to Keychain.")
        }
    }

    func read() throws -> StoredSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw AppError.storage("Unable to read session from Keychain.")
        }

        return try JSONDecoder().decode(StoredSession.self, from: data)
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.storage("Unable to clear session from Keychain.")
        }
    }
}
