import SwiftUI

enum BucketListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case todo = "To do"

    var id: String { rawValue }
}

struct BucketTimelineMarker: Equatable, Identifiable {
    let id: UUID
    let title: String
    let achievedLabel: String
    let completedAt: Date
}

struct BucketTimelineYear: Equatable, Identifiable {
    let year: Int
    let completedCount: Int

    var id: Int { year }

    var shortLabel: String {
        let suffix = year % 100
        return String(format: "’%02d", suffix)
    }
}

struct BucketTimelineWindow: Equatable {
    let minimumYear: Int
    let maximumYear: Int
    let defaultStartYear: Int
    let visibleYearCount: Int

    var maximumStartYear: Int {
        maximumYear - visibleYearCount + 1
    }

    func clampedStartYear(_ year: Int) -> Int {
        min(max(year, minimumYear), maximumStartYear)
    }
}

struct BucketListSummaryMetrics: Equatable {
    let achievedCount: Int
    let totalCount: Int
    let remainingCount: Int
    let percentageLived: Int
    let thisYearCount: Int
    let currentYear: Int
    let currentMonth: Int
    let timelineWindow: BucketTimelineWindow
    let timelineMarkers: [BucketTimelineMarker]
    let timelineYears: [BucketTimelineYear]

    static func make(
        items: [BucketItem],
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> BucketListSummaryMetrics {
        let completedItems = items
            .filter(\.isCompleted)
            .sorted {
                guard let lhsDate = $0.completedAt, let rhsDate = $1.completedAt else { return false }
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return $0.createdAt < $1.createdAt
            }
        let currentYear = calendar.component(.year, from: referenceDate)
        let currentMonth = calendar.component(.month, from: referenceDate)
        let minimumYear = currentYear - 100
        let maximumYear = currentYear + 50
        let visibleYearCount = 5
        let achievedCount = completedItems.count
        let totalCount = items.count
        let remainingCount = max(totalCount - achievedCount, 0)
        let percentageLived = totalCount == 0
            ? 0
            : Int((Double(achievedCount) / Double(totalCount) * 100).rounded())
        let thisYearCount = completedItems.filter { item in
            guard let completedAt = item.completedAt else { return false }
            return calendar.component(.year, from: completedAt) == currentYear
        }.count
        let completedCountsByYear = completedItems.reduce(into: [Int: Int]()) { result, item in
            guard let completedAt = item.completedAt else { return }
            let year = calendar.component(.year, from: completedAt)
            result[year, default: 0] += 1
        }

        let timelineMarkers = completedItems.compactMap { item -> BucketTimelineMarker? in
            guard let completedAt = item.completedAt else { return nil }
            return BucketTimelineMarker(
                id: item.id,
                title: item.title,
                achievedLabel: bucketMonthFormatter.string(from: completedAt),
                completedAt: completedAt
            )
        }

        let timelineYears = (minimumYear...maximumYear).map { year in
            return BucketTimelineYear(
                year: year,
                completedCount: completedCountsByYear[year, default: 0]
            )
        }

        return BucketListSummaryMetrics(
            achievedCount: achievedCount,
            totalCount: totalCount,
            remainingCount: remainingCount,
            percentageLived: percentageLived,
            thisYearCount: thisYearCount,
            currentYear: currentYear,
            currentMonth: currentMonth,
            timelineWindow: BucketTimelineWindow(
                minimumYear: minimumYear,
                maximumYear: maximumYear,
                defaultStartYear: currentYear,
                visibleYearCount: visibleYearCount
            ),
            timelineMarkers: timelineMarkers,
            timelineYears: timelineYears
        )
    }
}

struct BucketListSectionData: Equatable, Identifiable {
    let category: BucketCategory
    let items: [BucketItem]
    let progressCount: Int
    let totalCount: Int

    var id: BucketCategory { category }

    static func make(items: [BucketItem], filter: BucketListFilter) -> [BucketListSectionData] {
        BucketCategory.allCases.compactMap { category in
            let categoryItems = items.filter { $0.category == category }
            guard !categoryItems.isEmpty else { return nil }

            let visibleItems: [BucketItem]
            let progressCount = categoryItems.filter(\.isCompleted).count
            switch filter {
            case .all:
                visibleItems = orderedItems(categoryItems)
            case .todo:
                visibleItems = orderedItems(categoryItems.filter { !$0.isCompleted })
            }

            guard !visibleItems.isEmpty else { return nil }

            return BucketListSectionData(
                category: category,
                items: visibleItems,
                progressCount: progressCount,
                totalCount: categoryItems.count
            )
        }
    }

    private static func orderedItems(_ items: [BucketItem]) -> [BucketItem] {
        items.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

struct BucketListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @FocusState private var composerFocused: Bool

    @State private var selectedFilter: BucketListFilter = .todo
    @State private var showingComposer = false
    @State private var composerTitle = ""
    @State private var composerCategory: BucketCategory = .travel
    @State private var bucketItemPendingDeletion: BucketItem?
    @State private var bucketItemPendingCompletion: BucketItem?
    @State private var achievedDate = Calendar.current.startOfDay(for: .now)

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        GeometryReader { proxy in
            let layout = BucketLayoutMetrics(screenWidth: proxy.size.width)
            let metrics = BucketListSummaryMetrics.make(items: environment.bucketItems, referenceDate: .now, calendar: calendar)
            let sections = BucketListSectionData.make(items: environment.bucketItems, filter: selectedFilter)

            ScrollView {
                VStack(alignment: .leading, spacing: layout.verticalSpacing) {
                    header(metrics: metrics, layout: layout)
                    summaryCard(metrics: metrics, layout: layout)
                    filterPicker(layout: layout)

                    if sections.isEmpty {
                        emptyState(layout: layout)
                    } else {
                        ForEach(sections) { section in
                            sectionView(section, layout: layout)
                        }
                    }

                    if showingComposer {
                        composerCard(layout: layout)
                    } else {
                        addButton(layout: layout)
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, layout.topPadding)
                .padding(.bottom, layout.bottomPadding)
            }
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            environment.retryPendingBucketSyncIfNeeded()
        }
        .sheet(
            isPresented: Binding(
                get: { bucketItemPendingCompletion != nil },
                set: { isPresented in
                    if !isPresented {
                        bucketItemPendingCompletion = nil
                    }
                }
            )
        ) {
            BucketCompletionDateSheet(
                achievedDate: $achievedDate,
                item: bucketItemPendingCompletion,
                onCancel: {
                    bucketItemPendingCompletion = nil
                },
                onSave: { item, date in
                    Task {
                        do {
                            _ = try await environment.toggleBucketItemCompletion(
                                item,
                                achievedDate: calendar.startOfDay(for: date)
                            )
                            await MainActor.run {
                                bucketItemPendingCompletion = nil
                            }
                        } catch {
                            await MainActor.run {
                                environment.errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            )
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            bucketItemPendingDeletion == nil ? "Delete bucket item" : "Delete \(bucketItemPendingDeletion?.title ?? "item")?",
            isPresented: Binding(
                get: { bucketItemPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        bucketItemPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let item = bucketItemPendingDeletion else { return }
                Task {
                    await environment.deleteBucketItem(item)
                    bucketItemPendingDeletion = nil
                }
            }

            Button("Cancel", role: .cancel) {
                bucketItemPendingDeletion = nil
            }
        } message: {
            Text("This permanently removes the bucket item from your list.")
        }
    }

    private func header(metrics: BucketListSummaryMetrics, layout: BucketLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: layout.headerStackSpacing) {
            HStack(alignment: .center, spacing: 16) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: layout.dotSize, height: layout.dotSize)

                    Text("HabitClaw")
                        .font(AppTheme.serif(size: layout.headerFontSize, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showingComposer = true
                        composerFocused = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: layout.plusIconSize, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: layout.plusButtonSize, height: layout.plusButtonSize)
                        .background(AppTheme.surfaceStrong)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Text(headerSubtitle(metrics: metrics))
                .font(AppTheme.sans(size: layout.bodyFontSize))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func summaryCard(metrics: BucketListSummaryMetrics, layout: BucketLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: layout.cardStackSpacing) {
            VStack(alignment: .leading, spacing: layout.summaryHeaderSpacing) {
                Text("Your Life List")
                    .font(AppTheme.sans(size: layout.labelFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.2)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(metrics.achievedCount)")
                        .font(AppTheme.serif(size: layout.heroNumberFontSize, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("/ \(metrics.totalCount)")
                        .font(AppTheme.sans(size: layout.heroDenominatorFontSize, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Text(summarySubtitle(metrics: metrics))
                    .font(AppTheme.sans(size: layout.bodyFontSize))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            BucketTimelineView(metrics: metrics, layout: layout)

            Divider()
                .overlay(AppTheme.border)

            HStack {
                summaryStat(value: "\(metrics.achievedCount)", label: "Achieved", layout: layout)
                Spacer()
                summaryStat(value: "\(metrics.remainingCount)", label: "To Go", layout: layout)
                Spacer()
                summaryStat(value: "\(metrics.thisYearCount)", label: "This Year", layout: layout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: layout.cardPadding, cornerRadius: layout.cardCornerRadius)
    }

    private func summaryStat(value: String, label: String, layout: BucketLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(AppTheme.serif(size: layout.statNumberFontSize, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(label)
                .font(AppTheme.sans(size: layout.labelFontSize, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(1.1)
        }
    }

    private func filterPicker(layout: BucketLayoutMetrics) -> some View {
        HStack(spacing: layout.segmentInset) {
            ForEach(BucketListFilter.allCases) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(AppTheme.sans(size: layout.segmentFontSize, weight: .medium))
                        .foregroundStyle(selectedFilter == filter ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, layout.segmentVerticalPadding)
                        .background(selectedFilter == filter ? AppTheme.surfaceStrong : .clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(layout.segmentInset)
        .background(Color(red: 0.91, green: 0.89, blue: 0.83))
        .clipShape(Capsule())
    }

    private func sectionView(_ section: BucketListSectionData, layout: BucketLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            HStack {
                Text(section.category.title)
                    .font(AppTheme.sans(size: layout.labelFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.4)

                Spacer()

                Text("\(section.progressCount)/\(section.totalCount)")
                    .font(AppTheme.sans(size: layout.labelFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .tracking(1.0)
            }

            VStack(spacing: layout.rowSpacing) {
                ForEach(section.items) { item in
                    bucketRow(item, layout: layout)
                }
            }
        }
    }

    private func bucketRow(_ item: BucketItem, layout: BucketLayoutMetrics) -> some View {
        HStack(alignment: .center, spacing: layout.rowHorizontalSpacing) {
            Button {
                if item.isCompleted {
                    Task {
                        do {
                            _ = try await environment.toggleBucketItemCompletion(item, achievedDate: nil)
                        } catch {
                            await MainActor.run {
                                environment.errorMessage = error.localizedDescription
                            }
                        }
                    }
                } else {
                    achievedDate = calendar.startOfDay(for: .now)
                    bucketItemPendingCompletion = item
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(item.isCompleted ? AppTheme.accent : .clear)
                        .frame(width: layout.checkCircleSize, height: layout.checkCircleSize)
                        .overlay(
                            Circle()
                                .stroke(item.isCompleted ? AppTheme.accent : AppTheme.border, lineWidth: 2)
                        )

                    if item.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: layout.checkmarkFontSize, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: layout.rowTextSpacing) {
                Text(item.title)
                    .font(AppTheme.serif(size: layout.rowTitleFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary.opacity(item.isCompleted ? 0.7 : 1.0))
                    .strikethrough(item.isCompleted, color: AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(bucketSubtitle(for: item))
                    .font(AppTheme.sans(size: layout.rowSubtitleFontSize))
                    .foregroundStyle(item.isCompleted ? AppTheme.accent : AppTheme.textSecondary)
            }

            Spacer(minLength: 0)

            Button {
                bucketItemPendingDeletion = item
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: layout.removeIconSize, weight: .semibold))
                    .foregroundStyle(AppTheme.border)
                    .frame(width: layout.removeButtonSize, height: layout.removeButtonSize)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(fill: AppTheme.surfaceStrong, padding: layout.cardPadding, cornerRadius: layout.rowCornerRadius)
    }

    private func composerCard(layout: BucketLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: layout.composerSpacing) {
            TextField(
                "",
                text: $composerTitle,
                prompt: Text("Something you want to do...")
                    .font(AppTheme.serif(size: layout.rowTitleFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.border)
            )
            .font(AppTheme.serif(size: layout.rowTitleFontSize, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .focused($composerFocused)

            Divider()
                .overlay(AppTheme.border)

            HStack(spacing: layout.composerButtonSpacing) {
                Menu {
                    ForEach(BucketCategory.prototypeCases) { category in
                        Button(category.title) {
                            composerCategory = category
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(composerCategory.title)
                            .font(AppTheme.sans(size: layout.bodyFontSize, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)

                        Image(systemName: "chevron.down")
                            .font(.system(size: layout.chevronSize, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(minWidth: layout.menuMinWidth, alignment: .leading)
                    .padding(.horizontal, layout.menuHorizontalPadding)
                    .padding(.vertical, layout.controlVerticalPadding)
                    .background(Color(red: 0.96, green: 0.94, blue: 0.90))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .layoutPriority(1)

                Spacer(minLength: 0)

                HStack(spacing: layout.composerButtonSpacing) {
                    Button("Cancel") {
                        composerTitle = ""
                        showingComposer = false
                        composerFocused = false
                    }
                    .font(AppTheme.sans(size: layout.bodyFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: layout.cancelButtonWidth)
                    .padding(.vertical, layout.controlVerticalPadding)
                    .background(AppTheme.surfaceStrong)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
                    .buttonStyle(.plain)

                    Button("Add") {
                        let trimmedTitle = composerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedTitle.isEmpty else { return }

                        Task {
                            do {
                                _ = try await environment.createBucketItem(title: trimmedTitle, category: composerCategory)
                                await MainActor.run {
                                    composerTitle = ""
                                    composerCategory = .travel
                                    showingComposer = false
                                    composerFocused = false
                                }
                            } catch {
                                await MainActor.run {
                                    environment.errorMessage = error.localizedDescription
                                }
                            }
                        }
                    }
                    .font(AppTheme.sans(size: layout.bodyFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: layout.addButtonWidth)
                    .padding(.vertical, layout.controlVerticalPadding)
                    .background(canAddComposerItem ? Color(red: 0.65, green: 0.71, blue: 0.98) : AppTheme.border)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .disabled(!canAddComposerItem)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(layout.cardPadding)
        .background(AppTheme.surfaceStrong)
        .clipShape(RoundedRectangle(cornerRadius: layout.composerCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: layout.composerCornerRadius, style: .continuous)
                .stroke(AppTheme.accent, lineWidth: 1)
        )
    }

    private func addButton(layout: BucketLayoutMetrics) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                showingComposer = true
                composerFocused = true
            }
        } label: {
            Text("+ Add to your list")
                .font(AppTheme.sans(size: layout.bodyFontSize, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, layout.addButtonVerticalPadding)
                .background(AppTheme.surfaceStrong)
                .clipShape(RoundedRectangle(cornerRadius: layout.rowCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.rowCornerRadius, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func emptyState(layout: BucketLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: layout.summaryHeaderSpacing) {
            Text(environment.bucketItems.isEmpty ? "No bucket list items yet" : "Nothing left in this filter")
                .font(AppTheme.serif(size: layout.rowTitleFontSize, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(
                environment.bucketItems.isEmpty
                    ? "Start your life list with a few places, skills, or experiences you want to chase."
                    : "All done here. Time to dream up something new."
            )
            .font(AppTheme.sans(size: layout.bodyFontSize))
            .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: layout.cardPadding, cornerRadius: layout.cardCornerRadius)
    }

    private var canAddComposerItem: Bool {
        !composerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func bucketSubtitle(for item: BucketItem) -> String {
        guard let completedAt = item.completedAt else {
            return "Someday"
        }

        return "Achieved · \(bucketMonthFormatter.string(from: completedAt))"
    }

    private func summarySubtitle(metrics: BucketListSummaryMetrics) -> String {
        if metrics.remainingCount == 0 && metrics.totalCount > 0 {
            return "Every dream on the list - done."
        }

        return "\(metrics.remainingCount) still ahead of you · \(metrics.percentageLived)% lived"
    }

    private func headerSubtitle(metrics: BucketListSummaryMetrics) -> String {
        if metrics.totalCount == 0 {
            return "No bucket list items yet."
        }

        return "\(metrics.achievedCount) of \(metrics.totalCount) bucket list items achieved so far."
    }
}

private struct BucketTimelineView: View {
    let metrics: BucketListSummaryMetrics
    let layout: BucketLayoutMetrics

    @State private var restingStartYear: Int
    @GestureState private var dragTranslation: CGFloat = 0

    init(metrics: BucketListSummaryMetrics, layout: BucketLayoutMetrics) {
        self.metrics = metrics
        self.layout = layout
        _restingStartYear = State(initialValue: metrics.timelineWindow.defaultStartYear)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let visibleStartYear = displayedStartYear(for: width)
            let visibleEndYear = visibleStartYear + metrics.timelineWindow.visibleYearCount - 1
            let markerX = { (fraction: Double, inset: CGFloat) in
                let x = width * CGFloat(fraction)
                return min(max(x, inset), width - inset)
            }
            let nowFraction = fractionForCurrentMonth(in: visibleStartYear)
            let nowIsVisible = visibleStartYear...visibleEndYear ~= metrics.currentYear
            let visibleMarkers = metrics.timelineMarkers.filter { marker in
                let year = Calendar.current.component(.year, from: marker.completedAt)
                return visibleStartYear...visibleEndYear ~= year
            }
            let visibleYears = metrics.timelineYears.filter { year in
                visibleStartYear...visibleEndYear ~= year.year
            }

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: layout.timelineTrackY + 1))
                    path.addLine(to: CGPoint(x: width, y: layout.timelineTrackY + 1))
                }
                .stroke(
                    AppTheme.border.opacity(0.9),
                    style: StrokeStyle(lineWidth: layout.timelineDashLineWidth, lineCap: .round, dash: [4, 4])
                )

                Capsule()
                    .fill(Color(red: 0.94, green: 0.67, blue: 0.70))
                    .frame(width: width * CGFloat(nowFraction), height: layout.timelineTrackHeight)
                    .offset(y: layout.timelineTrackY)

                ForEach(visibleMarkers) { marker in
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: layout.timelineDotSize, height: layout.timelineDotSize)
                        .position(
                            x: markerX(fractionForMarkerMonth(marker.completedAt, in: visibleStartYear), layout.timelineDotInset),
                            y: layout.timelineDotY
                        )
                }

                if nowIsVisible {
                    Circle()
                        .fill(AppTheme.surfaceStrong)
                        .frame(width: layout.timelineNowRingSize, height: layout.timelineNowRingSize)
                        .overlay(
                            Circle()
                                .stroke(AppTheme.accent, lineWidth: layout.timelineNowRingLineWidth)
                        )
                        .position(x: markerX(nowFraction, layout.timelineNowRingSize / 2), y: layout.timelineDotY)
                }

                ForEach(visibleYears) { year in
                    VStack(spacing: 2) {
                        if year.year == metrics.currentYear {
                            Text("Now")
                                .font(AppTheme.sans(size: layout.timelineLabelFontSize, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }

                        Text(year.shortLabel)
                            .font(AppTheme.sans(size: layout.timelineLabelFontSize))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .position(
                        x: markerX(
                            fractionForYear(year.year, in: visibleStartYear),
                            year.year == metrics.currentYear ? layout.timelineCurrentYearInset : layout.timelineYearInset
                        ),
                        y: year.year == metrics.currentYear ? layout.timelineCurrentYearLabelY : layout.timelineYearLabelY
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .updating($dragTranslation) { value, state, _ in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        state = value.translation.width
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        restingStartYear = displayedStartYear(for: width, dragWidth: value.translation.width)
                    }
            )
        }
        .frame(height: layout.timelineHeight)
    }

    private func displayedStartYear(for width: CGFloat, dragWidth: CGFloat? = nil) -> Int {
        let effectiveDrag = dragWidth ?? dragTranslation
        let yearsPerStep = width / CGFloat(max(metrics.timelineWindow.visibleYearCount, 1))
        let yearShift = Int((effectiveDrag / max(yearsPerStep, 1)).rounded())

        // Snap the visible window to whole years as the user drags across the card.
        return metrics.timelineWindow.clampedStartYear(restingStartYear - yearShift)
    }

    private func fractionForCurrentMonth(in visibleStartYear: Int) -> Double {
        let visibleMonthCount = max(metrics.timelineWindow.visibleYearCount * 12, 1)
        let monthsFromStart = (metrics.currentYear - visibleStartYear) * 12 + (metrics.currentMonth - 1)
        let rawFraction = (Double(monthsFromStart) + 0.5) / Double(visibleMonthCount)
        return max(0, min(rawFraction, 1))
    }

    private func fractionForMarkerMonth(_ completedAt: Date, in visibleStartYear: Int) -> Double {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: completedAt)
        let month = calendar.component(.month, from: completedAt)
        let visibleMonthCount = max(metrics.timelineWindow.visibleYearCount * 12, 1)
        let monthsFromStart = (year - visibleStartYear) * 12 + (month - 1)
        let rawFraction = (Double(monthsFromStart) + 0.5) / Double(visibleMonthCount)
        return max(0, min(rawFraction, 1))
    }

    private func fractionForYear(_ year: Int, in visibleStartYear: Int) -> Double {
        let yearIndex = year - visibleStartYear
        let rawFraction = (Double(yearIndex) + 0.5) / Double(max(metrics.timelineWindow.visibleYearCount, 1))
        return max(0, min(rawFraction, 1))
    }
}

private struct BucketLayoutMetrics {
    let screenWidth: CGFloat

    private var scale: CGFloat {
        switch screenWidth {
        case ..<360:
            return 0.82
        case ..<380:
            return 0.87
        case ..<400:
            return 0.92
        case ..<430:
            return 0.97
        default:
            return 1.0
        }
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * scale
    }

    var horizontalPadding: CGFloat { scaled(20) }
    var topPadding: CGFloat { scaled(12) }
    var bottomPadding: CGFloat { scaled(110) }
    var verticalSpacing: CGFloat { scaled(20) }

    var dotSize: CGFloat { 18 }
    var headerStackSpacing: CGFloat { scaled(14) }
    var headerFontSize: CGFloat { 22 }
    var plusIconSize: CGFloat { 16 }
    var plusButtonSize: CGFloat { 38 }

    var cardPadding: CGFloat { scaled(16) }
    var cardCornerRadius: CGFloat { scaled(22) }
    var rowCornerRadius: CGFloat { scaled(20) }
    var composerCornerRadius: CGFloat { scaled(22) }
    var cardStackSpacing: CGFloat { scaled(18) }
    var summaryHeaderSpacing: CGFloat { scaled(10) }

    var labelFontSize: CGFloat { scaled(11) }
    var bodyFontSize: CGFloat { scaled(14) }
    var heroNumberFontSize: CGFloat { scaled(44) }
    var heroDenominatorFontSize: CGFloat { scaled(22) }
    var statNumberFontSize: CGFloat { scaled(24) }
    var sectionSpacing: CGFloat { scaled(12) }
    var rowSpacing: CGFloat { scaled(10) }
    var rowHorizontalSpacing: CGFloat { scaled(14) }
    var rowTextSpacing: CGFloat { scaled(3) }
    var rowTitleFontSize: CGFloat { scaled(18) }
    var rowSubtitleFontSize: CGFloat { scaled(12) }

    var segmentInset: CGFloat { scaled(4) }
    var segmentFontSize: CGFloat { scaled(14) }
    var segmentVerticalPadding: CGFloat { scaled(9) }

    var checkCircleSize: CGFloat { scaled(34) }
    var checkmarkFontSize: CGFloat { scaled(13) }
    var removeIconSize: CGFloat { scaled(13) }
    var removeButtonSize: CGFloat { scaled(28) }

    var composerSpacing: CGFloat { scaled(14) }
    var composerButtonSpacing: CGFloat { scaled(10) }
    var menuMinWidth: CGFloat { scaled(100) }
    var menuHorizontalPadding: CGFloat { scaled(14) }
    var controlVerticalPadding: CGFloat { scaled(11) }
    var cancelButtonWidth: CGFloat { scaled(100) }
    var addButtonWidth: CGFloat { scaled(88) }
    var chevronSize: CGFloat { scaled(13) }
    var addButtonVerticalPadding: CGFloat { scaled(13) }

    var timelineHeight: CGFloat { scaled(58) }
    var timelineTrackHeight: CGFloat { scaled(3) }
    var timelineTrackY: CGFloat { scaled(17) }
    var timelineDashLineWidth: CGFloat { scaled(2) }
    var timelineDotSize: CGFloat { scaled(14) }
    var timelineDotInset: CGFloat { scaled(8) }
    var timelineDotY: CGFloat { scaled(18) }
    var timelineNowRingSize: CGFloat { scaled(26) }
    var timelineNowRingLineWidth: CGFloat { scaled(3) }
    var timelineLabelFontSize: CGFloat { scaled(9.5) }
    var timelineYearInset: CGFloat { scaled(12) }
    var timelineCurrentYearInset: CGFloat { scaled(17) }
    var timelineYearLabelY: CGFloat { scaled(41) }
    var timelineCurrentYearLabelY: CGFloat { scaled(46) }
}

private struct BucketCompletionDateSheet: View {
    @Binding var achievedDate: Date
    let item: BucketItem?
    let onCancel: () -> Void
    let onSave: (BucketItem, Date) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(item?.title ?? "Bucket item")
                    .font(AppTheme.serif(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("When did you achieve this?")
                    .font(AppTheme.sans(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)

                DatePicker("Achieved on", selection: $achievedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(AppTheme.accent)

                Spacer()
            }
            .padding(20)
            .background(AppTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let item else { return }
                        onSave(item, achievedDate)
                    }
                }
            }
        }
    }
}

private let bucketMonthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM yyyy"
    return formatter
}()
