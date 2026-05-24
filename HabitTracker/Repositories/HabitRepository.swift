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

actor DefaultHabitRepository: HabitRepository {
    private let localStore: LocalStore
    private let remote: SupabaseHabitRemoteDataSource
    private let authService: AuthService

    init(localStore: LocalStore, remote: SupabaseHabitRemoteDataSource, authService: AuthService) {
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
        try await remote.upsertHabit(habit, authHeader: authHeader)
    }

    func archiveHabit(_ habit: Habit) async throws {
        var archived = habit
        archived.archivedAt = .now
        try await saveHabit(archived)
    }

    func sync() async throws -> [Habit] {
        let authHeader = await MainActor.run { authService.authorizationHeader() }
        let remoteHabits = try await remote.fetchHabits(authHeader: authHeader)
        try await localStore.writeHabits(remoteHabits)
        return remoteHabits
    }
}

actor DefaultCheckInRepository: CheckInRepository {
    private let localStore: LocalStore
    private let remote: SupabaseHabitRemoteDataSource
    private let authService: AuthService

    init(localStore: LocalStore, remote: SupabaseHabitRemoteDataSource, authService: AuthService) {
        self.localStore = localStore
        self.remote = remote
        self.authService = authService
    }

    func fetchCompletions() async throws -> [HabitCompletion] {
        try await localStore.readCompletions()
    }

    func recordCompletion(_ completion: HabitCompletion) async throws {
        var completions = try await localStore.readCompletions()
        if let index = completions.firstIndex(where: { $0.id == completion.id }) {
            completions[index] = completion
        } else {
            completions.append(completion)
        }
        try await localStore.writeCompletions(completions)
        let authHeader = await MainActor.run { authService.authorizationHeader() }
        try await remote.upsertCompletion(completion, authHeader: authHeader)
    }

    func sync() async throws -> [HabitCompletion] {
        let authHeader = await MainActor.run { authService.authorizationHeader() }
        let remoteCompletions = try await remote.fetchCompletions(authHeader: authHeader)
        try await localStore.writeCompletions(remoteCompletions)
        return remoteCompletions
    }
}

actor LocalStore {
    private let fileManager: FileManager
    private let baseURL: URL
    private let encoder = JSONEncoder.supabase
    private let decoder = JSONDecoder.supabase

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.baseURL = root.appending(path: "HabitTracker", directoryHint: .isDirectory)
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
        let rows: [HabitRow] = try await performRequest(path: "/rest/v1/habits?select=*", method: "GET", authHeader: authHeader)
        return rows.map(\.habit)
    }

    func upsertHabit(_ habit: Habit, authHeader: String?) async throws {
        _ = try await performRequest(
            path: "/rest/v1/habits",
            method: "POST",
            authHeader: authHeader,
            preferHeader: "resolution=merge-duplicates",
            body: [HabitRow(habit: habit)]
        ) as [HabitRow]
    }

    func fetchCompletions(authHeader: String?) async throws -> [HabitCompletion] {
        let rows: [HabitCompletionRow] = try await performRequest(path: "/rest/v1/habit_completions?select=*", method: "GET", authHeader: authHeader)
        return rows.map(\.completion)
    }

    func upsertCompletion(_ completion: HabitCompletion, authHeader: String?) async throws {
        _ = try await performRequest(
            path: "/rest/v1/habit_completions",
            method: "POST",
            authHeader: authHeader,
            preferHeader: "resolution=merge-duplicates",
            body: [HabitCompletionRow(completion: completion)]
        ) as [HabitCompletionRow]
    }

    private func performRequest<Response: Decodable>(
        path: String,
        method: String,
        authHeader: String?,
        preferHeader: String? = nil
    ) async throws -> Response {
        try await performRequest(
            path: path,
            method: method,
            authHeader: authHeader,
            preferHeader: preferHeader,
            body: Optional<EmptyRequestBody>.none
        )
    }

    private func performRequest<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        authHeader: String?,
        preferHeader: String? = nil,
        body: Body? = nil
    ) async throws -> Response {
        var request = URLRequest(url: configuration.url.appending(path: path))
        request.httpMethod = method
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            let message = (try? JSONDecoder.supabase.decode(SupabaseError.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AppError.network(message)
        }
        return try JSONDecoder.supabase.decode(Response.self, from: data)
    }
}

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
        self.targetType = habit.targetType.rawValue
        self.targetCount = habit.targetCount
        self.reminderHour = habit.reminderTime?.hour
        self.reminderMinute = habit.reminderTime?.minute
        self.createdAt = habit.createdAt
        self.archivedAt = habit.archivedAt
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
            targetType: HabitTargetType(rawValue: targetType) ?? .binary,
            targetCount: targetCount,
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
        self.count = completion.count
        self.note = completion.note
        self.createdAt = completion.createdAt
    }

    var completion: HabitCompletion {
        HabitCompletion(
            id: id,
            habitId: habitId,
            userId: userId,
            date: date,
            count: count,
            note: note,
            createdAt: createdAt
        )
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
