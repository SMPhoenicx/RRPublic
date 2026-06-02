//
//  TrackedView.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/16/26.
//


//
//  TrackedView.swift
//  RegattaResults
//
//  The Tracked tab. Default state shows favorited events and recently
//  tracked events. A "Scan / Enter URL" button opens ScannerSheet. After
//  a valid URL is submitted (or "Track" is pressed from EventInfoView),
//  the view enters a loading state while RegattaRepository resolves the
//  event, then pushes EventHubView onto the NavigationStack.
//

import SwiftUI

// MARK: - TrackedView

struct TrackedView: View {
    @EnvironmentObject var store:        TrackedEventStore
    @EnvironmentObject var repository:   RegattaRepository
    @EnvironmentObject var tabManager:   TabManager

    // Navigation
    @State private var hubEvent: DBEvent?        = nil   // non-nil → push EventHubView
    @State private var showScanner               = false

    // Loading state (URL submitted, resolving event)
    @State private var isResolving               = false
    @State private var resolvingURL: String      = ""
    @State private var resolveError: String?     = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphereBackground()

                VStack(spacing: 0) {
                    topBar

                    if isResolving {
                        resolvingOverlay
                    } else {
                        mainContent
                    }
                }

                // Push EventHubView as full-screen overlay inside the NavStack
                // so the atmosphere background persists underneath.
                if let event = hubEvent {
                    EventHubView(event: event, onClose: closeHub)
                        .environmentObject(repository)
                        .environmentObject(store)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: hubEvent != nil)
            .animation(.easeInOut(duration: 0.3), value: isResolving)
        }
        .sheet(isPresented: $showScanner) {
            ScannerSheet { url in
                Task { await resolveAndOpen(url: url) }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        // Open-hub requests from EventInfoView's Track / Open Hub button.
        // Using onReceive (not onChange) avoids requiring DBEvent: Equatable
        // AND benefits from @Published republishing the current value to
        // any new subscriber — so this fires correctly even when TrackedView
        // is being instantiated for the first time after the request was
        // already parked on the store.
        .onReceive(store.$pendingHubEvent) { event in
            guard let event else { return }
            // Clear before navigating so a quick second tap can re-trigger.
            _ = store.consumePendingHubEvent()
            withAnimation { hubEvent = event }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        GlassStrip(dark: true) {
            VStack(spacing: 0) {
                Spacer().frame(height: 56)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MY REGATTAS")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.2)
                            .foregroundColor(.tellTextMute)
                        Text("Tracked")
                            .font(.system(size: 24, weight: .black))
                            .tracking(-0.5)
                            .foregroundColor(.tellText)
                    }
                    Spacer()
                    // Scan button
                    Button { showScanner = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 14, weight: .bold))
                            Text("Scan")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.tellText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassCard(radius: 20, railColor: .tellCool, railWidth: 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Main content (default state)

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {

                if store.events.isEmpty {
                    emptyState
                } else {
                    // Favorites section
                    if !store.favorites.isEmpty {
                        TellSectionHeader(
                            title: "Favorites",
                            subtitle: "\(store.favorites.count) event\(store.favorites.count == 1 ? "" : "s")"
                        )
                        VStack(spacing: 8) {
                            ForEach(store.favorites) { tracked in
                                trackedRow(tracked)
                            }
                        }
                        .padding(.bottom, 12)
                    }

                    // Recently tracked
                    let recent = store.recentlyTracked.filter { !$0.isFavorite }
                    if !recent.isEmpty {
                        TellSectionHeader(
                            title: "Recently Tracked",
                            subtitle: "\(recent.count) event\(recent.count == 1 ? "" : "s")",
                            action: recent.count > 5 ? "SEE ALL" : nil,
                            onAction: nil
                        )
                        VStack(spacing: 8) {
                            ForEach(recent.prefix(10)) { tracked in
                                trackedRow(tracked)
                            }
                        }
                    }
                }

                // Error banner
                if let err = resolveError {
                    errorBanner(err)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                Color.clear.frame(height: 120)
            }
        }
    }

    // MARK: - Tracked event row

    private func trackedRow(_ tracked: TrackedEvent) -> some View {
        Button {
            // Fetch latest event from Supabase then open hub
            Task {
                if let event = await repository.fetchEvent(bySourceId: tracked.sourceEventId) {
                    store.track(event, sourceURL: tracked.sourceURL)
                    withAnimation { hubEvent = event }
                } else {
                    // Fallback — open with cached data converted back to DBEvent
                    hubEvent = tracked.asFallbackDBEvent()
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 0) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(
                            hue: Double((tracked.sourceEventId.unicodeScalars.first?.value ?? 200) % 360) / 360.0,
                            saturation: 0.35, brightness: 0.38
                        ))
                        .frame(width: 60, height: 60)
                    Text(tracked.displayName.prefix(2).uppercased())
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.leading, 6).padding(.vertical, 8)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        StatusPill(
                            text: tracked.isLive ? "LIVE" : trackedDateLabel(tracked),
                            tone: tracked.isLive ? .red : .cyan,
                            showPulse: tracked.isLive
                        )
                        if let club = tracked.clubName {
                            Text(club)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.tellTextMute)
                                .lineLimit(1)
                        }
                        Spacer()
                        // Favorite star
                        Button {
                            if let event = latestDBEvent(tracked) {
                                store.toggleFavorite(event)
                            }
                        } label: {
                            Image(systemName: tracked.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 13))
                                .foregroundColor(tracked.isFavorite ? .tellAmber : .tellTextMute)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                    }

                    Text(tracked.displayName)
                        .font(.system(size: 15.5, weight: .black))
                        .foregroundColor(.tellText)
                        .lineLimit(1)
                        .tracking(-0.2)

                    if let loc = tracked.location {
                        Label(loc, systemImage: "location")
                            .font(.system(size: 11.5))
                            .foregroundColor(.tellTextDim)
                            .labelStyle(CompactLabelStyle())
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 10)
            }
            .glassCard(railColor: tracked.isLive ? .tellAccent : .tellCool)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                store.remove(tracked)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Resolving overlay (loading state)

    private var resolvingOverlay: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.tellAccent.opacity(0.10))
                    .frame(width: 80, height: 80)
                Image(systemName: "sailboat.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.tellText)
            }
            VStack(spacing: 8) {
                Text("Finding Regatta")
                    .font(.system(size: 22, weight: .black))
                    .tracking(-0.3)
                    .foregroundColor(.tellText)
                Text(resolvingURL)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tellTextMute)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 40)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [.tellAccent, .tellCool],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * 0.65, height: 3)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                                   value: isResolving)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 60)

            Spacer()

            Button("Cancel") {
                isResolving = false
                resolvingURL = ""
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.tellTextMute)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "flag.slash")
                .font(.system(size: 40))
                .foregroundColor(.tellTextMute)
            Text("No tracked events yet")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.tellTextDim)
            Text("Scan a QR code, enter a URL, or tap Track on any event to start following it.")
                .font(.system(size: 14))
                .foregroundColor(.tellTextMute)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showScanner = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                    Text("Scan or Enter URL")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.tellText)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .glassCard(radius: 20, railColor: .tellCool)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.tellAmber)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.tellText)
            Spacer()
            Button { resolveError = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.tellTextMute)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassCard(radius: 12, railColor: .tellAmber)
    }

    // MARK: - Resolve URL → Event Hub

    func resolveAndOpen(url: String) async {
        isResolving  = true
        resolvingURL = url
        resolveError = nil

        if let event = await repository.fetchEvent(fromURL: url) {
            store.track(event, sourceURL: url)
            isResolving = false
            withAnimation { hubEvent = event }
        } else {
            isResolving  = false
            resolveError = "Couldn't find that regatta in our database. It may not be synced yet."
        }
    }

    // MARK: - Hub close (passed down to EventHubView's back button)

    private func closeHub() {
        withAnimation { hubEvent = nil }
    }

    // MARK: - Helpers

    private func trackedDateLabel(_ t: TrackedEvent) -> String {
        guard let d = t.startDate else { return "TBD" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    /// Reconstruct a lightweight DBEvent from cached TrackedEvent data so the
    /// hub can open without a network round-trip when Supabase is unreachable.
    private func latestDBEvent(_ t: TrackedEvent) -> DBEvent? {
        repository.liveEvents.first { $0.id == t.eventId }
            ?? repository.upcomingEvents.first { $0.id == t.eventId }
    }
}

// MARK: - TrackedEvent → fallback DBEvent

extension TrackedEvent {
    /// Reconstructs a minimal DBEvent from cached TrackedEvent fields.
    /// Used only when a fresh Supabase fetch fails.
    func asFallbackDBEvent() -> DBEvent {
        // We can't synthesise a full DBEvent without all Codable fields, so
        // encode/decode via JSON using only what we have stored.
        let dict: [String: Any?] = [
            "id":               eventId.uuidString,
            "source_id":        "clubspot",
            "source_event_id":  sourceEventId,
            "name":             name,
            "club_name":        clubName,
            "location":         location,
            "start_date":       startDate.map { ISO8601DateFormatter().string(from: $0) },
            "end_date":         endDate.map { ISO8601DateFormatter().string(from: $0) },
            "status":           status,
            "polling_mode":     nil,
            "hot_until":        nil,
            "image_url":        imageURL,
        ]
        let cleaned = dict.compactMapValues { $0 }
        if let data = try? JSONSerialization.data(withJSONObject: cleaned),
           let event = try? JSONDecoder().decode(DBEvent.self, from: data) {
            return event
        }
        // Last resort: this should never happen in practice
        fatalError("TrackedEvent.asFallbackDBEvent: could not construct DBEvent for \(name)")
    }
}
