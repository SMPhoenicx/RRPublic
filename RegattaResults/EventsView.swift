//
//  EventsView.swift
//  RegattaResults
//
//  The Events tab — browse, search, filter across all 18k+ events.
//  Two-tier filter: Upcoming / Past scope at top, with sub-filters
//  below (time range for upcoming, year chips for past).
//  All queries are server-side with offset pagination (50 per page).
//

import SwiftUI

// MARK: - Filter Models

enum EventTimeScope: String, CaseIterable {
    case all      = "All"
    case live     = "Live"
    case upcoming = "Upcoming"
    case past     = "Past"
}

enum UpcomingFilter: String, CaseIterable {
    case allUpcoming = "All"
    case thisWeek    = "This week"
    case thisMonth   = "This month"
    case following   = "Following"
}

// MARK: - EventsView

struct EventsView: View {
    @EnvironmentObject var repository:  RegattaRepository
    @EnvironmentObject var store:        TrackedEventStore
    @EnvironmentObject var tabManager:   TabManager

    // Filter state
    @State private var timeScope: EventTimeScope   = .all
    @State private var upcomingFilter: UpcomingFilter = .allUpcoming
    @State private var pastYear: Int = Calendar.current.component(.year, from: Date())
    @State private var search: String = ""

    // Data state
    @State private var displayedEvents: [DBEvent]  = []
    @State private var isLoadingEvents             = false
    @State private var isLoadingMore               = false
    @State private var canLoadMore                 = false
    @State private var currentOffset               = 0

    // Detail sheet
    @State private var selectedEvent: DBEvent?     = nil

    private let pageSize = 50

    // Years to offer as chips — current year down to 2019 (covers all
    // years with meaningful event counts in the Clubspot data).
    private var availablePastYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((2019...current).reversed())
    }

    /// Composite key that changes whenever the active filter or search
    /// changes. SwiftUI's `.task(id:)` cancels the old fetch and starts
    /// a fresh one whenever this value changes.
    private var filterStateId: String {
        switch timeScope {
        case .all:      return "all-\(search)"
        case .live:     return "live-\(search)"
        case .upcoming: return "upcoming-\(upcomingFilter.rawValue)-\(search)"
        case .past:     return "past-\(pastYear)-\(search)"
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AtmosphereBackground()

            VStack(spacing: 0) {
                TellTopBar(subtitle: "Browse", title: "Events")

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        searchBar
                        scopeToggle
                        subFilterChips

                        eventsSection

                        if canLoadMore && !isLoadingEvents {
                            loadMoreButton
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .task(id: filterStateId) {
            await loadEvents(reset: true)
        }
        .sheet(item: $selectedEvent) { event in
            EventInfoView(event: event)
                .environmentObject(store)
                .environmentObject(repository)
                .environmentObject(tabManager)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.tellTextMute)
                .font(.system(size: 15))
            TextField("Search events, clubs, locations…", text: $search)
                .font(.system(size: 15))
                .foregroundColor(.tellText)
                .tint(.tellAccent)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.tellTextMute)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassCard(radius: 12)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    // MARK: - Scope toggle (Upcoming / Past)

    private var scopeToggle: some View {
        HStack(spacing: 8) {
            ForEach(EventTimeScope.allCases, id: \.self) { scope in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        timeScope = scope
                    }
                } label: {
                    Text(scope.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(timeScope == scope ? .tellText : .tellTextMute)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(
                            timeScope == scope
                                ? AnyView(Capsule().fill(Color.white.opacity(0.14)))
                                : AnyView(Capsule().fill(Color.white.opacity(0.04)))
                        )
                        .overlay(
                            Capsule().stroke(
                                timeScope == scope ? Color.glassBorder : Color.clear,
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    // MARK: - Sub-filter chips

    private var subFilterChips: some View {
        Group {
            if timeScope == .all || timeScope == .live {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        switch timeScope {
                        case .upcoming:
                            ForEach(UpcomingFilter.allCases, id: \.self) { f in
                                FilterChip(label: f.rawValue, isOn: upcomingFilter == f) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        upcomingFilter = f
                                    }
                                }
                            }
                        case .past:
                            ForEach(availablePastYears, id: \.self) { year in
                                FilterChip(label: "\(year)", isOn: pastYear == year) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        pastYear = year
                                    }
                                }
                            }
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Events list

    private var eventsSection: some View {
        LazyVStack(spacing: 0) {
            // Count header
            HStack {
                Text("\(displayedEvents.count)\(canLoadMore ? "+" : "") event\(displayedEvents.count == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.tellText)
                Text("· \(filterDescription)")
                    .font(.system(size: 14))
                    .foregroundColor(.tellTextMute)
                Spacer()
                Text("Date \(timeScope == .upcoming || timeScope == .live ? "↑" : "↓")")
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.tellAccent)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 12)

            if isLoadingEvents && displayedEvents.isEmpty {
                loadingState
            } else if displayedEvents.isEmpty {
                emptyState
            } else {
                ForEach(displayedEvents) { event in
                    Button { selectedEvent = event } label: {
                        TellEventRow(event: event)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                }

                if isLoadingMore {
                    ProgressView()
                        .tint(.tellCool)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    /// Human-readable description of the active filter, shown next to the count.
    private var filterDescription: String {
        switch timeScope {
        case .all:      return "all events"
        case .live:     return "happening now"
        case .upcoming: return upcomingFilter.rawValue.lowercased()
        case .past:     return "\(pastYear)"
        }
    }

    // MARK: - Load more button

    private var loadMoreButton: some View {
        Button {
            Task { await loadEvents(reset: false) }
        } label: {
            HStack(spacing: 8) {
                Text("Load more")
                    .font(.system(size: 14, weight: .bold))
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.tellCool)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassCard(radius: 12)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Loading / empty states

    private var loadingState: some View {
        VStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 84)
                    .padding(.horizontal, 16)
                    .shimmer()
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sailboat")
                .font(.system(size: 40))
                .foregroundColor(.tellTextMute)
            Text("No events found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tellTextDim)
            Text("Try a different filter or search term")
                .font(.system(size: 14))
                .foregroundColor(.tellTextMute)
        }
        .padding(.top, 60)
    }

    // MARK: - Data loading

    /// Builds query parameters from the current filter state and fetches
    /// events from the server. `reset: true` clears the list (filter change);
    /// `reset: false` appends (pagination).
    private func loadEvents(reset: Bool) async {
        // "Following" with no tracked events → short-circuit
        if timeScope == .upcoming && upcomingFilter == .following && store.events.isEmpty {
            displayedEvents = []
            return
        }

        if reset {
            currentOffset = 0
            isLoadingEvents = true
        } else {
            isLoadingMore = true
        }

        let params = buildQueryParams()
        let searchTerm = search.isEmpty ? nil : search

        let newEvents = await repository.fetchFilteredEvents(
            statuses:   params.statuses,
            dateFrom:   params.dateFrom,
            dateTo:     params.dateTo,
            eventIds:   params.eventIds,
            searchTerm: searchTerm,
            ascending:  params.ascending,
            limit:      pageSize,
            offset:     currentOffset
        )

        if reset {
            displayedEvents = newEvents
        } else {
            displayedEvents.append(contentsOf: newEvents)
        }

        canLoadMore    = newEvents.count >= pageSize
        currentOffset += newEvents.count
        isLoadingEvents = false
        isLoadingMore   = false
    }

    // MARK: - Query parameter builder

    private struct QueryParams {
        var statuses: [String]?
        var dateFrom: String?
        var dateTo: String?
        var eventIds: [String]?
        var ascending: Bool
    }

    private func buildQueryParams() -> QueryParams {
        switch timeScope {
        case .all:
            return QueryParams(
                statuses: ["upcoming", "live", "completed"],
                ascending: false
            )

        case .live:
            return QueryParams(statuses: ["live"], ascending: true)

        case .upcoming:
            switch upcomingFilter {
            case .thisWeek:
                let (start, end) = weekRange()
                return QueryParams(dateFrom: start, dateTo: end, ascending: true)

            case .thisMonth:
                let (start, end) = monthRange()
                return QueryParams(dateFrom: start, dateTo: end, ascending: true)

            case .allUpcoming:
                return QueryParams(statuses: ["upcoming", "live"], ascending: true)

            case .following:
                let ids = store.events.map { $0.eventId.uuidString }
                return QueryParams(eventIds: ids, ascending: false)
            }

        case .past:
            return QueryParams(
                statuses: ["completed"],
                dateFrom: "\(pastYear)-01-01",
                dateTo:   "\(pastYear + 1)-01-01",
                ascending: false
            )
        }
    }

    // MARK: - Date helpers

    private func weekRange() -> (String, String) {
        let cal = Calendar.current
        let interval = cal.dateInterval(of: .weekOfYear, for: Date())!
        return (dateString(interval.start), dateString(interval.end))
    }

    private func monthRange() -> (String, String) {
        let cal = Calendar.current
        let interval = cal.dateInterval(of: .month, for: Date())!
        return (dateString(interval.start), dateString(interval.end))
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone  = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    private func formattedDate(_ start: Date, to end: Date?) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        guard let end, !Calendar.current.isDate(start, inSameDayAs: end) else { return f.string(from: start) }
        let f2 = DateFormatter(); f2.dateFormat = "MMM d"
        return "\(f.string(from: start))–\(f2.string(from: end))"
    }
}

// MARK: - Shimmer modifier (loading skeleton)

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.07), .clear],
                    startPoint: .init(x: phase - 0.3, y: 0),
                    endPoint: .init(x: phase, y: 0)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1.3
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}
