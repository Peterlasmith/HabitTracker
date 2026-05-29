import Foundation

protocol HabitRepository {
    func fetchHabits() async throws -> [Habit]
    func saveHabit(_ habit: Habit) async throws
    func archiveHabit(_ habit: Habit) async throws
    func sync() async throws -> [Habit]
}

protocol CheckInRepository {
    func fetchCompletions() async throws -> [HabitCompletion]
    func recordCompletion(_ completion: HabitCompletion) async throws
    func sync() async throws -> [HabitCompletion]
}

protocol HabitRemoteDataSource: Sendable {
    func fetchHabits(authHeader: String?) async throws -> [Habit]
    func upsertHabit(_ habit: Habit, authHeader: String?) async throws
    func fetchCompletions(authHeader: String?) async throws -> [HabitCompletion]
    func upsertCompletion(_ completion: HabitCompletion, authHeader: String?) async throws
}

actor DefaultHabitRepository: HabitRepository {
    private let localStore: LocalStore
    private let remote: any HabitRemoteDataSource
    private let authService: AuthService

    init(localStore: LocalStore, remote: any HabitRemoteDataSource, authService: AuthService) {
        self.localStore = localStore
        self.remote = remote
        self.authService = authService
    }

    func fetchHabits() async throws -> [Habit] {
        try await localStore.readHabits()
    }

    func saveHabit(_ habit: Habit) async throws {
        var habits = try await localStore.readHabits()
        if let index = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[index] = habit
        } else {
            habits.append(habit)
        }
        try await localStore.writeHabits(habits)
        let authHeader = await MainActor.run { authService.authorizationHeader() }
        Task {
            try? await remote.upsertHabit(habit, authHeader: authHeader)
        }
    }

    func archiveHabit(_ habit: Habit) async throws {
        var archived = habit
        archived.archivedAt = .now
        try await saveHabit(archived)
    }

    func sync() async throws -> [Habit] {
        let localHabits = try await localStore.readHabits()
        let authHeader = await MainActor.run { authService.authorizationHeader() }

        for habit in localHabits {
            try? await remote.upsertHabit(habit, authHeader: authHeader)
        }

        let remoteHabits = try await remote.fetchHabits(authHeader: authHeader)
        let mergedHabits = mergeHabits(localHabits, with: remoteHabits)
        try await localStore.writeHabits(mergedHabits)
        return mergedHabits
    }

    private func mergeHabits(_ localHabits: [Habit], with remoteHabits: [Habit]) -> [Habit] {
        let merged = remoteHabits.reduce(into: [UUID: Habit]()) { partialResult, habit in
            partialResult[habit.id] = habit
        }

        let mergedWithLocal = localHabits.reduce(into: merged) { partialResult, habit in
            partialResult[habit.id] = habit
        }

        return mergedWithLocal.values.sorted { $0.createdAt < $1.createdAt }
    }
}

actor DefaultCheckInRepository: CheckInRepository {
    private let localStore: LocalStore
    private let remote: any HabitRemoteDataSource
    private let authService: AuthService
    private let calendar = Calendar.autoupdatingCurrent

    init(localStore: LocalStore, remote: any HabitRemoteDataSource, authService: AuthService) {
        self.localStore = localStore
        self.remote = remote
        self.authService = authService
    }

    func fetchCompletions() async throws -> [HabitCompletion] {
        try await localStore.readCompletions()
    }

    func recordCompletion(_ completion: HabitCompletion) async throws {
        var completions = try await localStore.readCompletions()
        completions = replaceCompletion(completion, in: completions)
        try await localStore.writeCompletions(completions)
        let authHeader = await MainActor.run { authService.authorizationHeader() }
        Task {
            try? await remote.upsertCompletion(completion, authHeader: authHeader)
        }
    }

    func sync() async throws -> [HabitCompletion] {
        let localCompletions = try await localStore.readCompletions()
        let authHeader = await MainActor.run { authService.authorizationHeader() }

        for completion in localCompletions {
            try? await remote.upsertCompletion(completion, authHeader: authHeader)
        }

        let remoteCompletions = try await remote.fetchCompletions(authHeader: authHeader)
        let mergedCompletions = mergeCompletions(localCompletions, with: remoteCompletions)
        try await localStore.writeCompletions(mergedCompletions)
        return mergedCompletions
    }

    private func mergeCompletions(_ localCompletions: [HabitCompletion], with remoteCompletions: [HabitCompletion]) -> [HabitCompletion] {
        let merged = remoteCompletions.reduce(into: [CompletionKey: HabitCompletion]()) { partialResult, completion in
            partialResult[completionKey(for: completion)] = completion
        }

        let mergedWithLocal = localCompletions.reduce(into: merged) { partialResult, completion in
            let key = completionKey(for: completion)
            if let existing = partialResult[key] {
                partialResult[key] = preferredCompletion(between: existing, and: completion)
            } else {
                partialResult[key] = completion
            }
        }

        return mergedWithLocal.values.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.date < rhs.date
        }
    }

    private func replaceCompletion(_ completion: HabitCompletion, in completions: [HabitCompletion]) -> [HabitCompletion] {
        let key = completionKey(for: completion)
        var updated = completions.filter { completionKey(for: $0) != key }
        updated.append(completion)
        return updated.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.date < rhs.date
        }
    }

    private func preferredCompletion(between lhs: HabitCompletion, and rhs: HabitCompletion) -> HabitCompletion {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt ? lhs : rhs
        }
        // When timestamps tie, prefer the later merge candidate so local state
        // wins over a stale remote copy during startup sync.
        return rhs
    }

    private func completionKey(for completion: HabitCompletion) -> CompletionKey {
        CompletionKey(
            habitId: completion.habitId,
            day: calendar.startOfDay(for: completion.date)
        )
    }
}

private struct CompletionKey: Hashable {
    let habitId: UUID
    let day: Date
}

actor LocalStore {
    private let fileManager: FileManager
    private let baseURL: URL
    private let encoder = JSONEncoder.supabase
    private let decoder = JSONDecoder.supabase

    init(fileManager: FileManager = .default, baseURL: URL? = nil) {
        self.fileManager = fileManager
        if let baseURL {
            self.baseURL = baseURL
        } else {
            let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.baseURL = root.appending(path: "HabitTracker", directoryHint: .isDirectory)
        }
    }

    func readHabits() async throws -> [Habit] {
        let url = baseURL.appending(path: "habits.json")
        guard fileManager.fileExists(atPath: url.path()) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([Habit].self, from: data)
    }

    func writeHabits(_ habits: [Habit]) async throws {
        try await write(habits, fileName: "habits.json")
    }

    func readCompletions() async throws -> [HabitCompletion] {
        let url = baseURL.appending(path: "completions.json")
        guard fileManager.fileExists(atPath: url.path()) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([HabitCompletion].self, from: data)
    }

    func writeCompletions(_ completions: [HabitCompletion]) async throws {
        try await write(completions, fileName: "completions.json")
    }

    func clearAll() async throws {
        guard fileManager.fileExists(atPath: baseURL.path()) else { return }
        try fileManager.removeItem(at: baseURL)
    }

    private func write<T: Encodable>(_ value: T, fileName: String) async throws {
        try ensureBaseDirectory()
        let url = baseURL.appending(path: fileName)
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func ensureBaseDirectory() throws {
        guard !fileManager.fileExists(atPath: baseURL.path()) else { return }
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }
}

struct SupabaseHabitRemoteDataSource {
    let configuration: SupabaseConfiguration
    let urlSession: URLSession

    private struct EmptyRequestBody: Encodable {}

    init(configuration: SupabaseConfiguration = .fromBundle(), urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func fetchHabits(authHeader: String?) async throws -> [Habit] {
        let rows: [HabitRow] = try await performRequest(path: "rest/v1/habits", queryItems: [URLQueryItem(name: "select", value: "*")], method: "GET", authHeader: authHeader)
        return rows.map(\.habit)
    }

    func upsertHabit(_ habit: Habit, authHeader: String?) async throws {
        _ = try await performRequest(
            path: "rest/v1/habits",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            method: "POST",
            authHeader: authHeader,
            preferHeader: "resolution=merge-duplicates",
            body: [HabitRow(habit: habit)]
        ) as [HabitRow]
    }

    func fetchCompletions(authHeader: String?) async throws -> [HabitCompletion] {
        let rows: [HabitCompletionRow] = try await performRequest(path: "rest/v1/habit_completions", queryItems: [URLQueryItem(name: "select", value: "*")], method: "GET", authHeader: authHeader)
        return rows.map(\.completion)
    }

    func upsertCompletion(_ completion: HabitCompletion, authHeader: String?) async throws {
        _ = try await performRequest(
            path: "rest/v1/habit_completions",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            method: "POST",
            authHeader: authHeader,
            preferHeader: "resolution=merge-duplicates",
            body: [HabitCompletionRow(completion: completion)]
        ) as [HabitCompletionRow]
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

extension SupabaseHabitRemoteDataSource: HabitRemoteDataSource {}

struct HabitRow: Codable {
    let id: UUID
    let userId: UUID
    let name: String
    let emojiOrIcon: String
    let color: String
    let scheduleType: String
    let scheduleWeekdays: [Int]
    let targetType: String
    let targetCount: Int
    let targetPeriod: String
    let reminderHour: Int?
    let reminderMinute: Int?
    let createdAt: Date
    let archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case emojiOrIcon = "emoji_or_icon"
        case color
        case scheduleType = "schedule_type"
        case scheduleWeekdays = "schedule_weekdays"
        case targetType = "target_type"
        case targetCount = "target_count"
        case targetPeriod = "target_period"
        case reminderHour = "reminder_hour"
        case reminderMinute = "reminder_minute"
        case createdAt = "created_at"
        case archivedAt = "archived_at"
    }

    init(habit: Habit) {
        self.id = habit.id
        self.userId = habit.userId
        self.name = habit.name
        self.emojiOrIcon = habit.emojiOrIcon
        self.color = habit.color.rawValue
        switch habit.schedule {
        case .daily:
            self.scheduleType = "daily"
            self.scheduleWeekdays = Weekday.allCases.map(\.rawValue)
        case .weekdays(let days):
            self.scheduleType = "weekdays"
            self.scheduleWeekdays = days.map(\.rawValue).sorted()
        }
        self.targetType = HabitTargetType.binary.rawValue
        self.targetCount = 1
        self.targetPeriod = HabitTargetPeriod.day.rawValue
        self.reminderHour = habit.reminderTime?.hour
        self.reminderMinute = habit.reminderTime?.minute
        self.createdAt = habit.createdAt
        self.archivedAt = habit.archivedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        emojiOrIcon = try container.decode(String.self, forKey: .emojiOrIcon)
        color = try container.decode(String.self, forKey: .color)
        scheduleType = try container.decode(String.self, forKey: .scheduleType)
        scheduleWeekdays = try container.decode([Int].self, forKey: .scheduleWeekdays)
        targetType = try container.decode(String.self, forKey: .targetType)
        targetCount = try container.decode(Int.self, forKey: .targetCount)
        targetPeriod = HabitTargetPeriod.day.rawValue
        reminderHour = try container.decodeIfPresent(Int.self, forKey: .reminderHour)
        reminderMinute = try container.decodeIfPresent(Int.self, forKey: .reminderMinute)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(name, forKey: .name)
        try container.encode(emojiOrIcon, forKey: .emojiOrIcon)
        try container.encode(color, forKey: .color)
        try container.encode(scheduleType, forKey: .scheduleType)
        try container.encode(scheduleWeekdays, forKey: .scheduleWeekdays)
        try container.encode(targetType, forKey: .targetType)
        try container.encode(targetCount, forKey: .targetCount)
        try container.encode(targetPeriod, forKey: .targetPeriod)
        try container.encode(reminderHour, forKey: .reminderHour)
        try container.encode(reminderMinute, forKey: .reminderMinute)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(archivedAt, forKey: .archivedAt)
    }

    var habit: Habit {
        Habit(
            id: id,
            userId: userId,
            name: name,
            emojiOrIcon: emojiOrIcon,
            color: HabitColor(rawValue: color) ?? .teal,
            schedule: scheduleType == "daily"
                ? .daily
                : .weekdays(Set(scheduleWeekdays.compactMap(Weekday.init(rawValue:)))),
            targetType: .binary,
            targetCount: 1,
            targetPeriod: .day,
            reminderTime: reminderHour == nil ? nil : DateComponents(hour: reminderHour, minute: reminderMinute ?? 0),
            createdAt: createdAt,
            archivedAt: archivedAt
        )
    }
}

struct HabitCompletionRow: Codable {
    let id: UUID
    let habitId: UUID
    let userId: UUID
    let date: Date
    let count: Int
    let note: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case habitId = "habit_id"
        case userId = "user_id"
        case date
        case count
        case note
        case createdAt = "created_at"
    }

    init(completion: HabitCompletion) {
        self.id = completion.id
        self.habitId = completion.habitId
        self.userId = completion.userId
        self.date = completion.date
        self.count = normalizedCheckCount(completion.count)
        self.note = completion.note
        self.createdAt = completion.createdAt
    }

    var completion: HabitCompletion {
        HabitCompletion(
            id: id,
            habitId: habitId,
            userId: userId,
            date: date,
            count: normalizedCheckCount(count),
            note: note,
            createdAt: createdAt
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension JSONEncoder {
    static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
