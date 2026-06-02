//
//  HomePageView.swift
//  RegattaResults
//
//  Telltale Home — hero card (random event starting today or live),
//  quick actions, Today section, Following section.
//

import SwiftUI

// MARK: - HomePageView

struct HomePageView: View {
    @EnvironmentObject var repository: RegattaRepository
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var store: TrackedEventStore

    @AppStorage("userName") private var userName: String = ""

    @State private var selectedEvent: DBEvent?

    // Today's events fetched server-side so we don't depend on the
    @State private var randomHero: DBEvent? = nil

    // MARK: Derived groupings

    /// The hero card event: first live event, else a random event starting
    /// today (picked once per view lifecycle).
    private var heroEvent: DBEvent? {
        return randomHero
    }

    /// Events starting today minus the hero.
    private var otherTodayEvents: [DBEvent] {
        let heroId = heroEvent?.id
        let combined = repository.todayEvents
        // Deduplicate (live events may also be in todayEvents)
        var seen = Set<UUID>()
        return combined.filter { ev in
            guard seen.insert(ev.id).inserted else { return false }
            return ev.id != heroId
        }
    }

    /// Followed events — tracked/favorited, excluding the hero.
    private var followingEvents: [DBEvent] {
        let combined = repository.liveEvents + repository.upcomingEvents + repository.todayEvents
        var seen = Set<UUID>()
        return combined
            .filter { ev in
                guard seen.insert(ev.id).inserted else { return false }
                return store.isFavorite(ev) && ev.id != heroEvent?.id
            }
            .prefix(5)
            .map { $0 }
    }

    private var monthEventCount: Int {
        let cal = Calendar.current
        return repository.upcomingEvents.filter {
            guard let s = $0.startDate else { return false }
            return cal.isDate(s, equalTo: Date(), toGranularity: .month)
        }.count
    }

    var body: some View {
        ZStack {
            AtmosphereBackground()

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if let hero = heroEvent {
                            heroCard(for: hero)
                                .padding(.horizontal, 16)
                                .padding(.top, 10)
                        }

                        quickActions
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        
                        if !followingEvents.isEmpty {
                            TellSectionHeader(
                                title: "Favorites",
                                subtitle: "Up to 10 events for quick access",
                                action: "MANAGE",
                                onAction: { tabManager.switchTo(.tracked) }
                            )
                            .padding(.top, 8)

                            VStack(spacing: 8) {
                                ForEach(followingEvents.prefix(10)) { ev in
                                    Button { selectedEvent = ev } label: {
                                        TellEventRow(event: ev)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else if otherTodayEvents.isEmpty && heroEvent == nil {
                            emptyState
                        }
                        
                        if !otherTodayEvents.isEmpty {
                            TellSectionHeader(
                                title: "Today",
                                subtitle: "\(otherTodayEvents.count + (heroEvent != nil ? 1 : 0)) event\(otherTodayEvents.count + (heroEvent != nil ? 1 : 0) == 1 ? "" : "s") starting today",
                                action: "SEE ALL",
                                onAction: { tabManager.switchTo(.events) }
                            )
                            .padding(.top, 4)

                            VStack(spacing: 8) {
                                ForEach(otherTodayEvents) { ev in
                                    Button { selectedEvent = ev } label: {
                                        TellEventRow(event: ev)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Color.clear.frame(height: 120) // tab bar clearance
                    }
                }
            }
        }
        .onAppear {
            if randomHero == nil {
                randomHero = repository.todayEvents.randomElement()
            }
        }
        .refreshable {
            await repository.fetchAllHomeData()
            randomHero = repository.todayEvents.randomElement()
        }
        .sheet(item: $selectedEvent) { event in
            EventInfoView(event: event)
                .environmentObject(store)
                .environmentObject(repository)
                .environmentObject(tabManager)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        GlassStrip(dark: true) {
            VStack(spacing: 0) {
                Spacer().frame(height: 56)
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("WELCOME BACK")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.2)
                            .foregroundColor(.tellTextMute)
                        Text(userName.isEmpty ? "Sailor" : userName)
                            .font(.system(size: 24, weight: .black))
                            .tracking(-0.5)
                            .foregroundColor(.tellText)
                    }
                    Spacer()
                    NavigationLink {
                        SettingsTabView()
                    } label: {
                        avatarView
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
    }

    private var avatarView: some View {
        let initials: String = {
            let parts = userName.split(separator: " ").prefix(2)
            let letters = parts.compactMap { $0.first }
            return letters.isEmpty ? "?" : String(letters).uppercased()
        }()
        return Text(initials)
            .font(.system(size: 13, weight: .black))
            .foregroundColor(.white)
            .frame(width: 38, height: 38)
            .background(
                LinearGradient(
                    colors: [.tellAccent, Color(red: 0.63, green: 0.20, blue: 0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.30), lineWidth: 0.5))
    }

    // MARK: - Hero Card

    private func heroCard(for event: DBEvent) -> some View {
        let isLive = event.status == "live"

        return Button {
            selectedEvent = event
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Photo (or gradient fallback)
                if let imageURL = event.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        heroGradient(for: event)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                } else {
                    heroGradient(for: event)
                        .frame(height: 200)
                }

                
                // Top-left status pill
                VStack {
                    HStack(alignment: .top) {
                        if isLive {
                            liveBadge
                        } else {
                            featuredBadge
                        }
                        Spacer()
                        if store.isFavorite(event) {
                            followingChip
                        }
                    }
                    .padding(14)
                    Spacer()
                }

                // Bottom overlapping info card
                heroInfoCard(for: event)
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 14)
        }
        .buttonStyle(.plain)
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
                .shadow(color: .white.opacity(0.9), radius: 3)
            Text("LIVE NOW")
                .font(.system(size: 10, weight: .black))
                .tracking(1.2)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.tellAccent)
        .clipShape(Capsule())
        .shadow(color: .tellAccent.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    private var featuredBadge: some View {
        Text("FEATURED")
            .font(.system(size: 10, weight: .black))
            .tracking(1.2)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.50))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    private var followingChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "star.fill")
                .font(.system(size: 11))
                .foregroundColor(.tellAmber)
            Text("Following")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.tellText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.42))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    private func heroInfoCard(for event: DBEvent) -> some View {
        let railColor: Color = event.status == "live" ? .tellAccent : .tellCool
        return VStack(alignment: .leading, spacing: 0) {
            if let club = event.clubName {
                Text(club.uppercased())
                    .font(.system(size: 10.5, weight: .black))
                    .tracking(1.4)
                    .foregroundColor(.tellTextDim)
            }
            Text(event.displayName)
                .font(.system(size: 21, weight: .black))
                .tracking(-0.4)
                .foregroundColor(.tellText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 4)

            Divider()
                .background(Color.white.opacity(0.10))
                .padding(.vertical, 10)

            HStack(spacing: 10) {
                heroStat(
                    label: event.status == "live" ? "STATUS" : "STARTS",
                    value: event.status == "live" ? "Live" : startsInText(event.startDate)
                )
                Divider().frame(height: 28).background(Color.white.opacity(0.10))
                heroStat(label: "DATE", value: heroDate(event))
                if let loc = shortLocation(event.location) {
                    Divider().frame(height: 28).background(Color.white.opacity(0.10))
                    heroStat(label: "WHERE", value: loc)
                }
                Spacer(minLength: 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.04, green: 0.07, blue: 0.13).opacity(0.55))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(railColor)
                .frame(height: 2)
                .padding(.horizontal, 8)
                .shadow(color: railColor.opacity(0.4), radius: 6, x: 0, y: 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func heroStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .black))
                .tracking(1.2)
                .foregroundColor(.tellTextMute)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(.tellText)
                .lineLimit(1)
        }
    }

    private var openButton: some View {
        HStack(spacing: 5) {
            Text("Open")
                .font(.system(size: 12, weight: .black))
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .heavy))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.tellAccent)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .tellAccent.opacity(0.45), radius: 8, x: 0, y: 4)
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            quickAction(
                icon: "qrcode.viewfinder",
                accent: .tellCool,
                label: "Scan QR",
                sub: "pull regatta",
                onTap: { tabManager.switchTo(.tracked) }
            )
            quickAction(
                icon: "calendar",
                accent: .tellAmber,
                label: "\(monthEventCount) event\(monthEventCount == 1 ? "" : "s")",
                sub: "this month",
                onTap: { tabManager.switchTo(.events) }
            )
        }
    }

    private func quickAction(icon: String, accent: Color, label: String, sub: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.tellText)
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundColor(.tellTextMute)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sailboat.fill")
                .font(.system(size: 38))
                .foregroundColor(.tellTextMute)
            Text("No regattas to show yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tellTextDim)
            Text("Pull to refresh")
                .font(.system(size: 13))
                .foregroundColor(.tellTextMute)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Helpers

    private func heroGradient(for event: DBEvent) -> some View {
        let seed = Double((event.sourceEventId.unicodeScalars.first?.value ?? 200) % 60)
        let hue = seed / 360.0 + 0.55
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.50, brightness: 0.42),
                Color(hue: hue + 0.06, saturation: 0.40, brightness: 0.22),
                Color(hue: hue + 0.10, saturation: 0.30, brightness: 0.14),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private func heroDate(_ event: DBEvent) -> String {
        guard let start = event.startDate else { return "TBD" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        if let end = event.endDate, !Calendar.current.isDate(start, inSameDayAs: end) {
            let f2 = DateFormatter(); f2.dateFormat = "MMM d"
            return "\(f.string(from: start))–\(f2.string(from: end))"
        }
        return f.string(from: start)
    }

    private func startsInText(_ date: Date?) -> String {
        guard let date else { return "TBD" }
        let now = Date()
        if date < now { return "Today" }
        let days = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return "\(days)d"
        case 7...13: return "Next wk"
        default: return "\(days / 7)w"
        }
    }

    private func shortLocation(_ loc: String?) -> String? {
        guard let loc else { return nil }
        return String(loc.split(separator: ",").first ?? Substring(loc))
    }
}
