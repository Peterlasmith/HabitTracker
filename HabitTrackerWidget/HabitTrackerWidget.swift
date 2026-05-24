import SwiftUI
import WidgetKit

private enum WidgetSharedKeys {
    static let appGroup = "group.com.example.HabitTracker.shared"
    static let summaryKey = "widget.summary"
}

struct WidgetHabitSummary: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let emojiOrIcon: String
    let colorName: String
    let isComplete: Bool
}

struct WidgetSummary: Codable, Equatable {
    let date: Date
    let completionRatio: Double
    let completedCount: Int
    let totalCount: Int
    let habits: [WidgetHabitSummary]
}

private enum HabitColor: String {
    case teal
    case gold
}

private extension JSONDecoder {
    static var widgetDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct HabitTrackerWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitTrackerWidgetEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitTrackerWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitTrackerWidgetEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> HabitTrackerWidgetEntry {
        guard let defaults = UserDefaults(suiteName: WidgetSharedKeys.appGroup),
              let data = defaults.data(forKey: WidgetSharedKeys.summaryKey),
              let summary = try? JSONDecoder.widgetDecoder.decode(WidgetSummary.self, from: data)
        else {
            return .sample
        }
        return HabitTrackerWidgetEntry(date: .now, summary: summary)
    }
}

struct HabitTrackerWidgetEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary

    static let sample = HabitTrackerWidgetEntry(
        date: .now,
        summary: WidgetSummary(
            date: .now,
            completionRatio: 0.5,
            completedCount: 2,
            totalCount: 4,
            habits: [
                .init(id: UUID(), name: "Walk", emojiOrIcon: "🚶", colorName: HabitColor.teal.rawValue, isComplete: true),
                .init(id: UUID(), name: "Read", emojiOrIcon: "📚", colorName: HabitColor.gold.rawValue, isComplete: false)
            ]
        )
    )
}

struct HabitTrackerWidgetEntryView: View {
    var entry: HabitTrackerWidgetProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.24, blue: 0.22), Color(red: 0.10, green: 0.14, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            switch family {
            case .systemSmall:
                smallBody
            default:
                mediumBody
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
            Text("\(entry.summary.completedCount)/\(entry.summary.totalCount)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            ProgressView(value: entry.summary.completionRatio)
                .tint(.white)
        }
        .padding()
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today")
                    .font(.headline)
                Spacer()
                Text("\(entry.summary.completedCount)/\(entry.summary.totalCount)")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)

            ForEach(entry.summary.habits.prefix(3)) { habit in
                HStack {
                    Text("\(habit.emojiOrIcon) \(habit.name)")
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: habit.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(habit.isComplete ? .green : .white.opacity(0.8))
                }
            }
        }
        .padding()
    }
}

@main
struct HabitTrackerWidget: Widget {
    let kind = "HabitTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitTrackerWidgetProvider()) { entry in
            HabitTrackerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Habit Progress")
        .description("See today’s habits and check-in progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
