//
//  HubTab.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/16/26.
//


//
//  EventHubView.swift
//  RegattaResults
//
//  Results workspace. Opened from TrackedView after an event is loaded.
//  Hosts Results (by class), Documents, and Registered Sailors via a
//  segmented tab row. Starts live Supabase polling on appear; stops on
//  disappear.
//

import SwiftUI

// MARK: - Hub Tab

enum HubTab: String, CaseIterable {
    case results     = "Results"
    case documents   = "Documents"
    case sailors     = "Sailors"
}

// MARK: - EventHubView

struct EventHubView: View {
    let event: DBEvent

    var onClose: () -> Void

    @EnvironmentObject var repository:  RegattaRepository
    @EnvironmentObject var store:        TrackedEventStore
    @EnvironmentObject var notif:    NotificationManager

    @State private var activeTab: HubTab   = .results
    @State private var selectedClass: DBBoatClass? = nil
    @State private var expandedResultId: UUID? = nil
    @State private var showNotice   = false

    // Subscribe state
    @State private var showSubscribeSheet = false
    @State private var showUnsubscribeConfirm = false
    @State private var subscribeTicker: Date = Date()
    @State private var isUnsubscribing = false

    // Refresh state
    @State private var isRefreshing = false
    @State private var refreshError: String? = nil

    // Sailors tab: filter by boat class (nil = all classes)
    @State private var sailorsClassFilter: DBBoatClass? = nil

    // Drives the countdown text; updates every second when subscribed.
    private let subscribeTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AtmosphereBackground()

            VStack(spacing: 0) {
                topBar
                subscribeActionRow
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                tabRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Divider().background(Color.glassBorder)

                Group {
                    switch activeTab {
                    case .results:
                        resultsTab
                    case .documents:
                        documentsTab
                    case .sailors:
                        sailorsTab
                    }
                }
            }
        }
        .task {
            store.recordOpen(event)
            await repository.loadEvent(event)
            selectedClass = repository.boatClasses.first
            // Subscribe to live result updates
            if event.isLive {
                await repository.subscribeToResults(for: event.id)
            }
        }
        .onDisappear {
            Task { await repository.unsubscribeFromResults() }
        }
        .onReceive(subscribeTimer) { tick in
            subscribeTicker = tick

            if let until = currentEventDB?.hotUntil, until <= Date() {
                Task { await performUnsubscribe() }
            }
        }
        .sheet(isPresented: $showSubscribeSheet) {
            SubscribeSheet(event: currentEventDB ?? event) { _ in
                // After subscribe, force a tick so the countdown shows immediately.
                subscribeTicker = Date()
            }
            .environmentObject(repository)
            .environmentObject(notif)
        }
        .alert("Unsubscribe?", isPresented: $showUnsubscribeConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Unsubscribe", role: .destructive) {
                Task { await performUnsubscribe() }
            }
        } message: {
            Text("Live results for the regatta you are tracking will stop. You can receive notifications again by subscribing at any time.")
        }
    }

    // MARK: - Subscribe / favorite action row

    /// Prefer the live event from the repository so we see post-subscribe
    /// hot_until updates without refetching the page.
    private var currentEventDB: DBEvent? {
        repository.currentEvent?.id == event.id ? repository.currentEvent : event
    }

    private var isSubscribed: Bool {
        guard let until = currentEventDB?.hotUntil else { return false }
        return until > Date()
    }

    /// "h:mm:ss" remaining until hot_until, or nil if not subscribed.
    /// Reading subscribeTicker here makes this view re-evaluate every second.
    private var subscriptionCountdown: String? {
        _ = subscribeTicker
        guard let until = currentEventDB?.hotUntil else { return nil }
        let remaining = until.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        let total = Int(remaining)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    private var subscribeActionRow: some View {
        HStack(spacing: 10) {
            // Subscribe / Subscribed button — takes the bulk of the row.
            Button {
                if isSubscribed {
                    showUnsubscribeConfirm = true
                } else {
                    showSubscribeSheet = true
                }
            } label: {
                HStack(spacing: 8) {
                    if isUnsubscribing {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        Image(systemName: isSubscribed ? "bolt.fill" : "bolt")
                            .font(.system(size: 13, weight: .bold))
                    }
                    if let countdown = subscriptionCountdown {
                        Text("Subscribed")
                            .font(.system(size: 13, weight: .black))
                            .tracking(-0.1)
                        Text(countdown)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                    } else {
                        Text("Subscribe")
                            .font(.system(size: 13, weight: .black))
                            .tracking(-0.1)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(isSubscribed
                              ? Color.tellAccent
                              : Color.tellCool)
                        .shadow(
                            color: (isSubscribed ? Color.tellAccent : Color.tellCool).opacity(0.30),
                            radius: 10, y: 3
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isUnsubscribing)

            // Favorite — moved here from the top bar.
            Button {
                store.toggleFavorite(event)
            } label: {
                Image(systemName: store.isFavorite(event) ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(store.isFavorite(event) ? .tellAmber : .tellTextMute)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(Color.glassBorder, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Unsubscribe action

    private func performUnsubscribe() async {
        guard let eventId = currentEventDB?.id else { return }
        isUnsubscribing = true
        do {
            try await repository.unsubscribe(
                eventId: eventId,
                deviceToken: notif.apnsToken
            )
        } catch {
            print("[unsubscribe] \(error)")
        }
        isUnsubscribing = false
    }

    // MARK: - Manual refresh

    private func refreshCurrentTab() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil
        let target: RegattaRepository.RefreshTarget = {
            switch activeTab {
            case .results:   return .results
            case .documents: return .documents
            case .sailors:   return .registrations
            }
        }()
        do {
            try await repository.manualRefresh(eventId: event.id, target: target)
        } catch {
            refreshError = error.localizedDescription
            print("[manualRefresh] \(error)")
        }
        isRefreshing = false
    }

    // MARK: - Top bar

    private var topBar: some View {
        GlassStrip(dark: true) {
            VStack(spacing: 0) {
                Spacer().frame(height: 56)
                HStack(alignment: .center, spacing: 12) {
                    // Back
                    Button { onClose() } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.tellText)
                            .frame(width: 36, height: 36)
                            .glassCard(radius: 10)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 1) {
                        if let club = event.clubName {
                            Text(club.uppercased())
                                .font(.system(size: 10, weight: .black))
                                .tracking(1.2)
                                .foregroundColor(.tellTextMute)
                        }
                        Text(event.displayName)
                            .font(.system(size: 18, weight: .black))
                            .tracking(-0.3)
                            .foregroundColor(.tellText)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Live indicator or status pill
                    if event.isLive {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.tellAccent)
                                .frame(width: 6, height: 6)
                                .shadow(color: .tellAccent.opacity(0.7), radius: 4)
                            Text("LIVE")
                                .font(.system(size: 10, weight: .black))
                                .tracking(1.0)
                                .foregroundColor(.tellAccent)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassCard(radius: 8, railColor: .tellAccent, railWidth: 10)
                    }

                    // Refresh button — refreshes the currently-active tab.
                    Button {
                        Task { await refreshCurrentTab() }
                    } label: {
                        Image(systemName: isRefreshing
                              ? "arrow.triangle.2.circlepath.circle.fill"
                              : "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(isRefreshing ? .tellCool : .tellText)
                            .frame(width: 36, height: 36)
                            .glassCard(radius: 10)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(
                                isRefreshing
                                    ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                                    : .default,
                                value: isRefreshing
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Tab row

    private var tabRow: some View {
        HStack(spacing: 8) {
            ForEach(HubTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        activeTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(activeTab == tab ? .tellText : .tellTextMute)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            activeTab == tab
                                ? AnyView(Capsule().fill(Color.white.opacity(0.12)))
                                : AnyView(Color.clear)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Results tab

    @ViewBuilder
    private var resultsTab: some View {
        if repository.isLoading {
            loadingState("Loading results…")
        } else if repository.boatClasses.isEmpty {
            emptyState(icon: "chart.bar", message: "No results yet", sub: "Check back once racing starts")
        } else {
            VStack(spacing: 0) {
                LastUpdatedStrip(
                    label: "Results",
                    syncedAt: currentEventDB?.resultsSyncedAt
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Class picker (if more than one class)
                if repository.boatClasses.count > 1 {
                    classPicker
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                if let cls = selectedClass, let classResults = repository.results[cls] {
                    if classResults.isEmpty {
                        emptyState(icon: "flag", message: "No results posted yet for \(cls.displayName).\nRefresh again.", sub: nil)
                    } else {
                        resultsList(classResults, boatClass: cls)
                    }
                } else {
                    emptyState(icon: "chart.bar", message: "Select a class above", sub: nil)
                }
            }
        }
    }

    private var classPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(repository.boatClasses) { cls in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedClass = cls
                        }
                    } label: {
                        Text(cls.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(selectedClass?.id == cls.id ? .tellText : .tellTextMute)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                selectedClass?.id == cls.id
                                    ? AnyView(Capsule().fill(Color.tellAccent.opacity(0.18)))
                                    : AnyView(Capsule().fill(Color.white.opacity(0.06)))
                            )
                            .overlay(
                                Capsule().stroke(
                                    selectedClass?.id == cls.id
                                        ? Color.tellAccent.opacity(0.5)
                                        : Color.glassBorder,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func resultsList(_ results: [DBResult], boatClass: DBBoatClass) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 6) {
                ForEach(Array(results.enumerated()), id: \.element.id) { idx, result in
                    ResultRow(
                        position: idx + 1,
                        result: result,
                        totalRaces: maxRaceCount(results),
                        isExpanded: expandedResultId == result.id,
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                expandedResultId = expandedResultId == result.id ? nil : result.id
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }

    private func maxRaceCount(_ results: [DBResult]) -> Int {
        results.map { $0.raceScores.count }.max() ?? 0
    }

    // MARK: - Documents tab

    @ViewBuilder
    private var documentsTab: some View {
        if repository.isLoading {
            loadingState("Loading documents…")
        } else if repository.documents.isEmpty {
            emptyState(icon: "doc", message: "No documents posted", sub: "Sailing instructions and notices will appear here")
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    LastUpdatedStrip(
                        label: "Documents",
                        syncedAt: currentEventDB?.documentsSyncedAt
                    )
                    .padding(.bottom, 4)

                    ForEach(repository.documents) { doc in
                        DocumentRow(document: doc)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
        }
    }

    // MARK: - Sailors tab

    @ViewBuilder
    private var sailorsTab: some View {
        if repository.isLoading {
            loadingState("Loading sailors…")
        } else if repository.registrations.isEmpty {
            emptyState(icon: "person.2", message: "No sailors registered yet", sub: nil)
        } else {
            VStack(spacing: 0) {
                LastUpdatedStrip(
                    label: "Sailors",
                    syncedAt: currentEventDB?.registrationsSyncedAt
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Class picker — only show if event has more than one class.
                // "All" is the default; per-class filtering uses the same
                // boat_class_id stored on each registration.
                if repository.boatClasses.count > 1 {
                    sailorsClassPicker
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        // Count strip
                        HStack {
                            Text("\(filteredRegistrations.count) registered")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.tellTextMute)
                                .tracking(0.4)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)

                        if filteredRegistrations.isEmpty {
                            emptyState(
                                icon: "person.2",
                                message: "No sailors in this class",
                                sub: nil
                            )
                            .frame(height: 240)
                        } else {
                            ForEach(filteredRegistrations) { reg in
                                SailorRow(registration: reg)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
            }
        }
    }

    /// Registrations after applying the sailors-tab class filter.
    private var filteredRegistrations: [DBRegistration] {
        guard let filter = sailorsClassFilter else {
            return repository.registrations
        }
        return repository.registrations.filter { $0.boatClassId == filter.id }
    }

    /// "All / <Class A> / <Class B>" pill picker for the sailors tab.
    /// Mirrors the structure of the results-tab class picker but with an
    /// "All" affordance prepended.
    private var sailorsClassPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All classes" pill
                pickerPill(
                    title: "All",
                    isSelected: sailorsClassFilter == nil,
                    action: { sailorsClassFilter = nil }
                )

                ForEach(repository.boatClasses) { cls in
                    pickerPill(
                        title: cls.displayName,
                        isSelected: sailorsClassFilter?.id == cls.id,
                        action: { sailorsClassFilter = cls }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func pickerPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isSelected ? .tellText : .tellTextMute)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected
                        ? AnyView(Capsule().fill(Color.tellAccent.opacity(0.18)))
                        : AnyView(Capsule().fill(Color.white.opacity(0.06)))
                )
                .overlay(
                    Capsule().stroke(
                        isSelected
                            ? Color.tellAccent.opacity(0.5)
                            : Color.glassBorder,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared states

    private func loadingState(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.tellCool)
                .scaleEffect(1.2)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tellTextMute)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(icon: String, message: String, sub: String?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.tellTextMute)
            Text(message)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tellTextDim)
            if let sub {
                Text(sub)
                    .font(.system(size: 13))
                    .foregroundColor(.tellTextMute)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - ResultRow

struct ResultRow: View {
    let position: Int
    let result: DBResult
    let totalRaces: Int
    let isExpanded: Bool
    var onTap: () -> Void = {}

    private var positionColor: Color {
        switch position {
        case 1: return .tellAmber
        case 2: return .tellCool
        case 3: return Color(red: 0.78, green: 0.55, blue: 0.42)
        default: return .tellTextMute
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // ── Compact row (always visible) ──
                HStack(spacing: 10) {
                    // Position
                    Text("\(position)")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundColor(positionColor)
                        .frame(width: 26, alignment: .trailing)

                    // Sail number
                    if let sail = result.sailNumber {
                        Text(sail)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.tellTextMute)
                            .frame(width: 50, alignment: .leading)
                    }
                    else {
                        Spacer()
                            .frame(width: 50)
                    }

                    // Name + boat
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.names.first ?? "—")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.tellText)
                            .lineLimit(1)
                        if let boat = result.boatName {
                            Text(boat)
                                .font(.system(size: 11.5))
                                .foregroundColor(.tellTextMute)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    // Summary: race count + net points
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f", result.netPoints ?? result.totalPoints ?? 0))
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundColor(.tellText)
                        Text("\(result.raceScores.count) race\(result.raceScores.count == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.tellTextMute)
                    }

                    // Chevron
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.tellTextMute)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                // ── Expanded race breakdown ───────────────────
                if isExpanded {
                    Divider().background(Color.glassBorder)

                    VStack(spacing: 0) {
                        // Header row
                        HStack(spacing: 0) {
                            Text("Race")
                                .frame(width: 44, alignment: .leading)
                            Text("Score")
                                .frame(width: 44, alignment: .center)
                            Text("Code")
                                .frame(width: 44, alignment: .center)
                            Spacer()
                        }
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.tellTextMute)
                        .tracking(0.8)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                        ForEach(result.raceScores.sorted(by: { ($0.raceNumber ?? 0) < ($1.raceNumber ?? 0) })) { score in
                            HStack(spacing: 0) {
                                Text("R\(score.raceNumber ?? 0)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.tellText)
                                    .frame(width: 44, alignment: .leading)

                                Text(String(format: "%.0f", score.points ?? 0))
                                    .font(.system(size: 13, weight: .black, design: .monospaced))
                                    .foregroundColor(score.throwout == true ? .tellTextMute : .tellText)
                                    .strikethrough(score.throwout == true)
                                    .frame(width: 44, alignment: .center)

                                if let code = score.letterScore, !code.isEmpty {
                                    Text(code)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.tellAmber)
                                        .frame(width: 44, alignment: .center)
                                } else {
                                    Color.clear.frame(width: 44)
                                }

                                Spacer()

                                if score.throwout == true {
                                    Text("THROWOUT")
                                        .font(.system(size: 8, weight: .black))
                                        .tracking(0.6)
                                        .foregroundColor(.tellTextMute)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.06))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                        }

                        // Totals row
                        Divider().background(Color.glassBorder).padding(.horizontal, 14)
                        HStack {
                            Text("Total")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.tellTextMute)
                            Spacer()
                            if let gross = result.totalPoints, let net = result.netPoints, gross != net {
                                Text(String(format: "%.0f gross", gross))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.tellTextMute)
                                    .strikethrough()
                                Text("→")
                                    .font(.system(size: 10))
                                    .foregroundColor(.tellTextMute)
                            }
                            Text(String(format: "%.0f net", result.netPoints ?? result.totalPoints ?? 0))
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundColor(.tellText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)

                        // Competitor details
                        if result.names.count > 1 || result.clubName != nil {
                            Divider().background(Color.glassBorder).padding(.horizontal, 14)
                            VStack(alignment: .leading, spacing: 4) {
                                if result.names.count > 1 {
                                    Text("Crew: \(result.names.dropFirst().joined(separator: ", "))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.tellTextDim)
                                }
                                if let club = result.clubName {
                                    Text(club)
                                        .font(.system(size: 11))
                                        .foregroundColor(.tellTextDim)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .glassCard(radius: 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DocumentRow

struct DocumentRow: View {
    let document: DBDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundColor(.tellCool)
                .frame(width: 28)

            Text(document.title ?? "Untitled Document")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tellText)
                .lineLimit(2)

            Spacer()

            if document.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.tellTextMute)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(radius: 10)
        .onTapGesture {
            guard let urlStr = document.url, let url = URL(string: urlStr) else { return }
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - LastUpdatedStrip

/// Small inline row showing when a tab's data was last refreshed from
/// Clubspot. Pulls from the event's *_synced_at column. Empty when we
/// have no timestamp yet (event still loading or never synced).
struct LastUpdatedStrip: View {
    let label: String
    let syncedAt: Date?

    @State private var ticker: Date = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.tellTextMute)
            Text(label)
                .font(.system(size: 10, weight: .black))
                .tracking(0.6)
                .foregroundColor(.tellTextMute)
            Text("·")
                .font(.system(size: 10))
                .foregroundColor(.tellTextMute)
            Text(relativeText)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.tellTextDim)
            Spacer()
        }
        .padding(.vertical, 6)
        .onReceive(timer) { ticker = $0 }
    }

    /// Relative phrasing ("3 min ago", "2 h ago"). Re-evaluated whenever
    /// `ticker` changes so the text stays roughly current.
    private var relativeText: String {
        _ = ticker
        guard let synced = syncedAt else { return "never synced" }
        let elapsed = Date().timeIntervalSince(synced)
        if elapsed < 30 { return "just now" }
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        if elapsed < 3600 { return "\(Int(elapsed / 60)) min ago" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600)) h ago" }
        let days = Int(elapsed / 86400)
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }
}

// MARK: - SailorRow

struct SailorRow: View {
    let registration: DBRegistration

    private var initial: String {
        String(registration.primaryName.prefix(1)).uppercased()
    }

    private var bubbleColor: Color {
        // Stable color per sailor based on their source_reg_id
        let seed = registration.sourceRegId.unicodeScalars.first.map { Int($0.value) } ?? 0
        return Color(
            hue: Double(seed % 360) / 360.0,
            saturation: 0.4,
            brightness: 0.55
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            // Initials bubble
            Text(initial)
                .font(.system(size: 14, weight: .black))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(bubbleColor))

            VStack(alignment: .leading, spacing: 2) {
                Text(registration.displayNames)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.tellText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let sail = registration.sailNumber, !sail.isEmpty {
                        Text("#\(sail)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.tellTextMute)
                    }
                    if let boat = registration.boatName, !boat.isEmpty {
                        Text(boat)
                            .font(.system(size: 11))
                            .foregroundColor(.tellTextMute)
                            .lineLimit(1)
                    }
                    if let club = registration.yachtClub, !club.isEmpty {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.tellTextMute)
                        Text(club)
                            .font(.system(size: 11))
                            .foregroundColor(.tellTextMute)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            // Waitlist badge if applicable
            if registration.waitlist == true {
                Text("WAITLIST")
                    .font(.system(size: 8.5, weight: .black))
                    .tracking(0.8)
                    .foregroundColor(.tellAmber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.tellAmber.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassCard(radius: 10)
    }
}
