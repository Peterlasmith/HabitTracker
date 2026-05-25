import Foundation
import OSLog
import StoreKit
import UserNotifications
import WidgetKit

enum AppError: LocalizedError, Equatable {
    case network(String)
    case storage(String)
    case configuration(String)

    var errorDescription: String? {
        switch self {
        case .network(let message), .storage(let message), .configuration(let message):
            return message
        }
    }
}

protocol ReminderService {
    func requestAuthorization() async throws -> Bool
    func rescheduleNotifications(for habits: [Habit]) async throws
}

struct DefaultReminderService: ReminderService {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func rescheduleNotifications(for habits: [Habit]) async throws {
        let center = UNUserNotificationCenter.current()
        let identifiers = habits.map { "habit-\($0.id.uuidString)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        for habit in habits where habit.reminderTime != nil && !habit.isArchived {
            let content = UNMutableNotificationContent()
            content.title = habit.name
            content.body = "Time to keep your streak alive."
            content.sound = .default

            switch habit.schedule {
            case .daily:
                guard let reminderTime = habit.reminderTime else { continue }
                var components = DateComponents()
                components.hour = reminderTime.hour
                components.minute = reminderTime.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(identifier: "habit-\(habit.id.uuidString)", content: content, trigger: trigger)
                try await center.add(request)
            case .weekdays(let days):
                for day in days {
                    guard let reminderTime = habit.reminderTime else { continue }
                    var components = DateComponents()
                    components.weekday = day.rawValue
                    components.hour = reminderTime.hour
                    components.minute = reminderTime.minute
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    let request = UNNotificationRequest(
                        identifier: "habit-\(habit.id.uuidString)-\(day.rawValue)",
                        content: content,
                        trigger: trigger
                    )
                    try await center.add(request)
                }
            }
        }
    }
}

@MainActor
final class PurchaseService: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var entitlement: PurchaseEntitlement = .unknown

    let productID = "com.example.HabitTracker.fullunlock"

    func loadProducts() async {
        do {
            products = try await Product.products(for: [productID])
        } catch {
            AppLogger.purchase.error("Failed to load products: \(error.localizedDescription)")
        }
    }

    func refreshEntitlements() async {
        for await verificationResult in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verificationResult else { continue }
            if transaction.productID == productID {
                entitlement = .unlocked(transaction.purchaseDate)
                return
            }
        }
        entitlement = .locked
    }

    func purchase() async throws {
        guard let product = products.first else {
            throw AppError.configuration("Store product not found.")
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verificationResult):
            guard case .verified(let transaction) = verificationResult else {
                throw AppError.network("Unable to verify purchase.")
            }
            entitlement = .unlocked(transaction.purchaseDate)
            await transaction.finish()
        case .pending:
            throw AppError.network("Purchase is pending approval.")
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }
}

struct WidgetSyncService {
    static let appGroup = "group.com.example.HabitTracker.shared"
    static let summaryKey = "widget.summary"

    func publish(habits: [Habit], completions: [HabitCompletion], date: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        let dueHabits = habits.filter { $0.isDue(on: date, calendar: calendar) }
        let summaries = dueHabits.map { habit -> WidgetHabitSummary in
            let completion = completions
                .filter { $0.habitId == habit.id && calendar.isDate($0.date, inSameDayAs: today) }
                .max { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    return lhs.createdAt < rhs.createdAt
                }
            return WidgetHabitSummary(
                id: habit.id,
                name: habit.name,
                emojiOrIcon: habit.emojiOrIcon,
                colorName: habit.color.rawValue,
                isComplete: completion?.isCompleted(for: habit) == true
            )
        }

        let completedCount = summaries.filter(\.isComplete).count
        let summary = WidgetSummary(
            date: today,
            completionRatio: dueHabits.isEmpty ? 0 : Double(completedCount) / Double(dueHabits.count),
            completedCount: completedCount,
            totalCount: dueHabits.count,
            habits: summaries
        )

        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let data = try? JSONEncoder.supabase.encode(summary)
        else { return }

        defaults.set(data, forKey: Self.summaryKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct AnalyticsService {
    func track(_ event: AnalyticsEvent) {
        AppLogger.analytics.info("Analytics event: \(event.rawValue, privacy: .public)")
    }
}

enum AnalyticsEvent: String {
    case completedOnboarding
    case createdAccount
    case signedIn
    case purchasedUnlock
    case failedPurchase
    case createdHabit
    case enabledReminder
    case completedHabit
}

enum AppLogger {
    static let app = Logger(subsystem: "com.example.HabitTracker", category: "app")
    static let analytics = Logger(subsystem: "com.example.HabitTracker", category: "analytics")
    static let purchase = Logger(subsystem: "com.example.HabitTracker", category: "purchase")
}
