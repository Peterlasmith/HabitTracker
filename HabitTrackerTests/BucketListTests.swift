import XCTest
@testable import HabitTracker

final class BucketListTests: XCTestCase {
    func testBucketItemRowRoundTripPreservesCompletionDate() {
        let item = BucketItem(
            id: UUID(),
            userId: UUID(),
            title: "See the northern lights",
            category: .travel,
            completedAt: Date(timeIntervalSince1970: 1_780_000_000),
            createdAt: Date(timeIntervalSince1970: 1_770_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )

        let row = BucketItemRow(bucketItem: item)

        XCTAssertEqual(row.bucketItem, item)
    }

    func testBucketItemRowEncodingIncludesNullCompletedAt() throws {
        let item = BucketItem(
            id: UUID(),
            userId: UUID(),
            title: "Run a marathon",
            category: .skills,
            completedAt: nil,
            createdAt: .now,
            updatedAt: .now
        )

        let row = BucketItemRow(bucketItem: item)
        let data = try JSONEncoder.supabase.encode([row])
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let encodedRow = try XCTUnwrap(payload.first)

        XCTAssertTrue(encodedRow.keys.contains("completed_at"))
        XCTAssertTrue(encodedRow["completed_at"] is NSNull)
    }

    func testBucketRepositorySyncPrefersNewestUpdatedAt() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = LocalStore(baseURL: baseURL)
        let remote = StubBucketRemoteDataSource()
        let authService = await MainActor.run { BucketMockAuthService() }
        let repository = DefaultBucketListRepository(
            localStore: localStore,
            remote: remote,
            authService: authService
        )

        let itemID = UUID()
        let userID = UUID()
        let localItem = BucketItem(
            id: itemID,
            userId: userID,
            title: "Local title",
            category: .travel,
            completedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let remoteItem = BucketItem(
            id: itemID,
            userId: userID,
            title: "Remote title",
            category: .travel,
            completedAt: Date(timeIntervalSince1970: 1_790_000_000),
            createdAt: localItem.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )

        try await localStore.writeBucketItems([localItem])
        await remote.setItems([remoteItem])

        let synced = try await repository.sync()
        let persistedItems = try await localStore.readBucketItems()

        XCTAssertEqual(synced, [remoteItem])
        XCTAssertEqual(persistedItems, [remoteItem])
    }

    func testSummaryMetricsCalculatesCountsPercentageAndTimeline() {
        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 6))!
        let userID = UUID()
        let items = [
            BucketItem(
                id: UUID(),
                userId: userID,
                title: "See the northern lights",
                category: .travel,
                completedAt: calendar.date(from: DateComponents(year: 2023, month: 8, day: 1)),
                createdAt: referenceDate,
                updatedAt: referenceDate
            ),
            BucketItem(
                id: UUID(),
                userId: userID,
                title: "Visit Japan",
                category: .travel,
                completedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)),
                createdAt: referenceDate,
                updatedAt: referenceDate
            ),
            BucketItem(
                id: UUID(),
                userId: userID,
                title: "Hold a conversation in Spanish",
                category: .skills,
                completedAt: nil,
                createdAt: referenceDate,
                updatedAt: referenceDate
            )
        ]

        let metrics = BucketListSummaryMetrics.make(items: items, referenceDate: referenceDate, calendar: calendar)

        XCTAssertEqual(metrics.achievedCount, 2)
        XCTAssertEqual(metrics.totalCount, 3)
        XCTAssertEqual(metrics.remainingCount, 1)
        XCTAssertEqual(metrics.percentageLived, 67)
        XCTAssertEqual(metrics.thisYearCount, 1)
        XCTAssertEqual(metrics.currentYear, 2026)
        XCTAssertEqual(metrics.currentMonth, 6)
        XCTAssertEqual(metrics.timelineWindow.minimumYear, 1926)
        XCTAssertEqual(metrics.timelineWindow.maximumYear, 2076)
        XCTAssertEqual(metrics.timelineWindow.defaultStartYear, 2026)
        XCTAssertEqual(metrics.timelineWindow.visibleYearCount, 5)
        XCTAssertEqual(metrics.timelineYears.first?.year, 1926)
        XCTAssertEqual(metrics.timelineYears.last?.year, 2076)
        XCTAssertEqual(metrics.timelineYears.first?.completedCount, 0)
        XCTAssertEqual(metrics.timelineYears.first(where: { $0.year == 2023 })?.completedCount, 1)
        XCTAssertEqual(metrics.timelineYears.first(where: { $0.year == 2026 })?.completedCount, 1)
        XCTAssertEqual(metrics.timelineMarkers.map(\.title), ["See the northern lights", "Visit Japan"])
        XCTAssertEqual(metrics.timelineMarkers.map(\.achievedLabel), ["Aug 2023", "May 2026"])
    }

    func testSectionDataRespectsAllAndTodoFilters() {
        let userID = UUID()
        let completedTravel = BucketItem(
            id: UUID(),
            userId: userID,
            title: "Drive the Pacific Coast Highway",
            category: .travel,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let todoTravel = BucketItem(
            id: UUID(),
            userId: userID,
            title: "See the northern lights",
            category: .travel,
            completedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_600_000_100),
            updatedAt: Date(timeIntervalSince1970: 1_600_000_100)
        )
        let todoSkill = BucketItem(
            id: UUID(),
            userId: userID,
            title: "Run a marathon",
            category: .skills,
            completedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_600_000_200),
            updatedAt: Date(timeIntervalSince1970: 1_600_000_200)
        )

        let items = [completedTravel, todoTravel, todoSkill]
        let allSections = BucketListSectionData.make(items: items, filter: .all)
        let todoSections = BucketListSectionData.make(items: items, filter: .todo)

        XCTAssertEqual(allSections.map(\.category), [.travel, .skills])
        XCTAssertEqual(allSections.first?.progressCount, 1)
        XCTAssertEqual(allSections.first?.totalCount, 2)
        XCTAssertEqual(allSections.first?.items.map(\.title), ["Drive the Pacific Coast Highway", "See the northern lights"])

        XCTAssertEqual(todoSections.map(\.category), [.travel, .skills])
        XCTAssertEqual(todoSections.first?.progressCount, 1)
        XCTAssertEqual(todoSections.first?.totalCount, 2)
        XCTAssertEqual(todoSections.first?.items.map(\.title), ["See the northern lights"])
        XCTAssertEqual(todoSections.last?.progressCount, 0)
    }

    func testPrototypeCategoriesStayInExpectedOrder() {
        XCTAssertEqual(
            BucketCategory.prototypeCases,
            [.travel, .adventure, .skills, .experiences, .milestones, .giving]
        )
    }
}

private actor StubBucketRemoteDataSource: BucketListRemoteDataSource {
    private var items: [BucketItem] = []

    func setItems(_ items: [BucketItem]) {
        self.items = items
    }

    func fetchBucketItems(authHeader: String?) async throws -> [BucketItem] {
        items
    }

    func upsertBucketItem(_ item: BucketItem, authHeader: String?) async throws {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    func deleteBucketItem(_ item: BucketItem, authHeader: String?) async throws -> Bool {
        items.removeAll { $0.id == item.id }
        return true
    }
}

@MainActor
private final class BucketMockAuthService: AuthService {
    var currentUser: AppUser?

    func restoreSession() async throws -> AppUser? { currentUser }
    func signIn(email: String, password: String) async throws -> AppUser { throw AppError.network("Unused") }
    func signUp(email: String, password: String) async throws -> AppUser { throw AppError.network("Unused") }
    func deleteAccount(currentPassword: String) async throws {}
    func signOut() async throws {}
    func authorizationHeader() -> String? { nil }
}
