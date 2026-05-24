import Foundation
import Security

@MainActor
protocol AuthService: AnyObject {
    var currentUser: AppUser? { get }
    func restoreSession() async throws -> AppUser?
    func signIn(email: String, password: String) async throws -> AppUser
    func signUp(email: String, password: String) async throws -> AppUser
    func signOut() async throws
    func authorizationHeader() -> String?
}

@MainActor
final class SupabaseAuthService: ObservableObject, AuthService {
    @Published private(set) var currentUser: AppUser?

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

        let user = try await fetchCurrentUser(accessToken: session.accessToken)
        currentUser = user
        return user
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        let session = try await authenticate(path: "/auth/v1/token?grant_type=password", body: [
            "email": email,
            "password": password
        ])
        try sessionStore.write(session)
        let user = AppUser(id: session.user.id, email: session.user.email)
        currentUser = user
        return user
    }

    func signUp(email: String, password: String) async throws -> AppUser {
        let session = try await authenticate(path: "/auth/v1/signup", body: [
            "email": email,
            "password": password
        ])
        try sessionStore.write(session)
        let user = AppUser(id: session.user.id, email: session.user.email)
        currentUser = user
        return user
    }

    func signOut() async throws {
        currentUser = nil
        try sessionStore.clear()
    }

    func authorizationHeader() -> String? {
        guard let session = try? sessionStore.read() else { return nil }
        let token = session.accessToken
        return "Bearer \(token)"
    }

    private func fetchCurrentUser(accessToken: String) async throws -> AppUser {
        var request = URLRequest(url: configuration.url.appending(path: "/auth/v1/user"))
        request.httpMethod = "GET"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
        let user = try JSONDecoder.supabase.decode(SupabaseUser.self, from: data)
        return AppUser(id: user.id, email: user.email)
    }

    private func authenticate(path: String, body: [String: String]) async throws -> SupabaseSession {
        var request = URLRequest(url: configuration.url.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder.supabase.decode(SupabaseSession.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Missing HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder.supabase.decode(SupabaseError.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AppError.network(message)
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
    let message: String
}

struct StoredSession: Codable {
    let accessToken: String
    let refreshToken: String?
}

struct SessionStore {
    private let service = "HabitTracker.auth"
    private let account = "supabase.session"

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

