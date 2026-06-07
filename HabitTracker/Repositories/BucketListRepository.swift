import Foundation

protocol BucketListRepository {
    func fetchBucketItems() async throws -> [BucketItem]
    func saveBucketItem(_ item: BucketItem) async throws
    func deleteBucketItem(_ item: BucketItem) async throws
    func sync() async throws -> [BucketItem]
}

protocol BucketListRemoteDataSource: Sendable {
    func fetchBucketItems(authHeader: String?) async throws -> [BucketItem]
    func upsertBucketItem(_ item: BucketItem, authHeader: String?) async throws
    func deleteBucketItem(_ item: BucketItem, authHeader: String?) async throws -> Bool
}

actor DefaultBucketListRepository: BucketListRepository {
    private let localStore: LocalStore
    private let remote: any BucketListRemoteDataSource
    private let authService: AuthService

    init(localStore: LocalStore, remote: any BucketListRemoteDataSource, authService: AuthService) {
        self.localStore = localStore
        self.remote = remote
        self.authService = authService
    }

    func fetchBucketItems() async throws -> [BucketItem] {
        try await localStore.readBucketItems()
    }

    func saveBucketItem(_ item: BucketItem) async throws {
        var items = try await localStore.readBucketItems()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        try await localStore.writeBucketItems(sortedBucketItems(items))
        try await performAuthorizedRemoteRequest { [self] authHeader in
            try await self.remote.upsertBucketItem(item, authHeader: authHeader)
        }
    }

    func deleteBucketItem(_ item: BucketItem) async throws {
        let previousItems = try await localStore.readBucketItems()
        let previousDeletedItems = try await localStore.readDeletedBucketItems()
        var updatedItems = previousItems
        updatedItems.removeAll { $0.id == item.id }
        var updatedDeletedItems = previousDeletedItems.filter { $0.bucketItemId != item.id }
        updatedDeletedItems.append(DeletedBucketItemRecord(bucketItemId: item.id, userId: item.userId))
        try await localStore.writeBucketItems(updatedItems)
        try await localStore.writeDeletedBucketItems(updatedDeletedItems)

        do {
            let deletedRemotely = try await performAuthorizedRemoteRequest { [self] authHeader in
                try await self.remote.deleteBucketItem(item, authHeader: authHeader)
            }
            guard deletedRemotely else {
                throw AppError.network("Supabase did not confirm deleting this bucket item. Check your latest schema/policies and try again.")
            }
        } catch {
            try? await localStore.writeBucketItems(previousItems)
            try? await localStore.writeDeletedBucketItems(previousDeletedItems)
            throw error
        }
    }

    func sync() async throws -> [BucketItem] {
        var deletedItems = try await localStore.readDeletedBucketItems()
        let deletedItemIDs = Set(deletedItems.map(\.bucketItemId))
        let localItems = try await localStore.readBucketItems()
            .filter { !deletedItemIDs.contains($0.id) }

        for deletedItem in deletedItems {
            do {
                _ = try await performAuthorizedRemoteRequest { [self] authHeader in
                    try await self.remote.deleteBucketItem(deletedItem.bucketItem, authHeader: authHeader)
                }
            } catch {
                // Keep the tombstone so we can retry the remote delete on the next sync.
            }
        }

        let remoteItems = try await performAuthorizedRemoteRequest { [self] authHeader in
            try await self.remote.fetchBucketItems(authHeader: authHeader)
        }
        let remoteItemIDs = Set(remoteItems.map(\.id))
        deletedItems.removeAll { !remoteItemIDs.contains($0.bucketItemId) }
        let pendingDeletedItemIDs = Set(deletedItems.map(\.bucketItemId))
        let mergedItems = mergeBucketItems(localItems, with: remoteItems)
            .filter { !pendingDeletedItemIDs.contains($0.id) }

        for item in mergedItems {
            try? await performAuthorizedRemoteRequest { [self] authHeader in
                try await self.remote.upsertBucketItem(item, authHeader: authHeader)
            }
        }

        try await localStore.writeBucketItems(mergedItems)
        try await localStore.writeDeletedBucketItems(deletedItems)
        return mergedItems
    }

    private func performAuthorizedRemoteRequest<T>(
        _ operation: @escaping @Sendable (String?) async throws -> T
    ) async throws -> T {
        let authHeader = await MainActor.run { authService.authorizationHeader() }

        do {
            return try await operation(authHeader)
        } catch {
            guard authHeader == nil || error.isExpiredSupabaseSession else {
                throw error
            }

            _ = try await authService.restoreSession()
            guard let refreshedAuthHeader = await MainActor.run(body: { authService.authorizationHeader() }) else {
                throw AppError.network("Your session expired. Sign in again to keep going.")
            }

            return try await operation(refreshedAuthHeader)
        }
    }

    private func mergeBucketItems(_ localItems: [BucketItem], with remoteItems: [BucketItem]) -> [BucketItem] {
        let merged = remoteItems.reduce(into: [UUID: BucketItem]()) { partialResult, item in
            partialResult[item.id] = item
        }

        let mergedWithLocal = localItems.reduce(into: merged) { partialResult, item in
            if let existing = partialResult[item.id] {
                partialResult[item.id] = preferredBucketItem(between: existing, and: item)
            } else {
                partialResult[item.id] = item
            }
        }

        return sortedBucketItems(Array(mergedWithLocal.values))
    }
}

struct DeletedBucketItemRecord: Codable, Equatable {
    let bucketItemId: UUID
    let userId: UUID

    var bucketItem: BucketItem {
        BucketItem(
            id: bucketItemId,
            userId: userId,
            title: "",
            category: .other,
            completedAt: nil,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }
}

struct SupabaseBucketListRemoteDataSource {
    let configuration: SupabaseConfiguration
    let urlSession: URLSession

    private struct EmptyRequestBody: Encodable {}

    init(configuration: SupabaseConfiguration = .fromBundle(), urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func fetchBucketItems(authHeader: String?) async throws -> [BucketItem] {
        let rows: [BucketItemRow] = try await performRequest(
            path: "rest/v1/bucket_items",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.asc")
            ],
            method: "GET",
            authHeader: authHeader
        )
        return sortedBucketItems(rows.map(\.bucketItem))
    }

    func upsertBucketItem(_ item: BucketItem, authHeader: String?) async throws {
        _ = try await performRequest(
            path: "rest/v1/bucket_items",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            method: "POST",
            authHeader: authHeader,
            preferHeader: "resolution=merge-duplicates",
            body: [BucketItemRow(bucketItem: item)]
        ) as [BucketItemRow]
    }

    func deleteBucketItem(_ item: BucketItem, authHeader: String?) async throws -> Bool {
        let deletedRows: [BucketItemRow] = try await performRequest(
            path: "rest/v1/bucket_items",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(item.id.uuidString.lowercased())"),
                URLQueryItem(name: "user_id", value: "eq.\(item.userId.uuidString.lowercased())"),
            ],
            method: "DELETE",
            authHeader: authHeader
        )
        return deletedRows.contains { $0.id == item.id }
    }

    private func performRequest<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        authHeader: String?,
        preferHeader: String? = nil
    ) async throws -> Response {
        try await performRequest(
            path: path,
            queryItems: queryItems,
            method: method,
            authHeader: authHeader,
            preferHeader: preferHeader,
            body: Optional<EmptyRequestBody>.none
        )
    }

    private func performRequest<Response: Decodable, Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        authHeader: String?,
        preferHeader: String? = nil,
        body: Body? = nil
    ) async throws -> Response {
        var request = URLRequest(url: endpointURL(path: path, queryItems: queryItems))
        request.httpMethod = method
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")

        if let authHeader {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        if let preferHeader {
            request.setValue("return=representation,\(preferHeader)", forHTTPHeaderField: "Prefer")
        }
        if let body {
            request.httpBody = try JSONEncoder.supabase.encode(body)
        }

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
            throw AppError.network(message)
        }
        return try JSONDecoder.supabase.decode(Response.self, from: data)
    }

    private func endpointURL(path: String, queryItems: [URLQueryItem]) -> URL {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let baseURL = configuration.url.appending(path: normalizedPath)
        guard !queryItems.isEmpty else { return baseURL }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        return components?.url ?? baseURL
    }
}

extension SupabaseBucketListRemoteDataSource: BucketListRemoteDataSource {}

struct BucketItemRow: Codable {
    let id: UUID
    let userId: UUID
    let title: String
    let category: String
    let completedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case category
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(bucketItem: BucketItem) {
        self.id = bucketItem.id
        self.userId = bucketItem.userId
        self.title = bucketItem.title
        self.category = bucketItem.category.rawValue
        self.completedAt = bucketItem.completedAt
        self.createdAt = bucketItem.createdAt
        self.updatedAt = bucketItem.updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(String.self, forKey: .category)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var bucketItem: BucketItem {
        BucketItem(
            id: id,
            userId: userId,
            title: title,
            category: BucketCategory(rawValue: category) ?? .other,
            completedAt: completedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

func preferredBucketItem(between lhs: BucketItem, and rhs: BucketItem) -> BucketItem {
    if lhs.updatedAt == rhs.updatedAt {
        return rhs
    }
    return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
}

func sortedBucketItems(_ items: [BucketItem]) -> [BucketItem] {
    items.sorted { lhs, rhs in
        if lhs.category != rhs.category {
            return lhs.category.sortIndex < rhs.category.sortIndex
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
