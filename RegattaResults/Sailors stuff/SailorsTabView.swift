//
//  SailorsTabView.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/27/26.
//


//
//  SailorsTabView.swift
//  RegattaResults
//
//  The Sailors tab. Replaces the old Settings tab.
//
//  Loading model:
//   • The default "most active" list is preloaded at launch into
//     repository.defaultSailors (via fetchAllHomeData) — shown instantly.
//   • Favorited sailors come from FavoriteSailorStore (UserDefaults) —
//     also instant; their snapshot is refreshed from the server in the
//     background on first appear and on pull-to-refresh.
//   • Typing in the search bar runs a debounced server-side query
//     (search_sailors RPC). Search results paginate with a Load More
//     button, exactly like the Events tab.
//
//  No full-table load, ever. No disk caching of the list — only the
//  small favorites snapshot is persisted.
//

import SwiftUI

struct SailorsTabView: View {
    @EnvironmentObject var repository:  RegattaRepository
    @EnvironmentObject var sailorStore: FavoriteSailorStore
    @EnvironmentObject var store:       TrackedEventStore
    @EnvironmentObject var tabManager:  TabManager

    // Search state
    @State private var search: String = ""
    @State private var searchResults: [Sailor] = []
    @State private var isSearching      = false
    @State private var isLoadingMore    = false
    @State private var canLoadMore      = false
    @State private var searchOffset     = 0

    // Lifecycle
    @State private var hasRefreshedFavorites = false
    @State private var profileSailor: Sailor? = nil

    /// Active search term, trimmed; nil when the bar is empty.
    private var activeTerm: String? {
        let t = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private var isSearchActive: Bool { activeTerm != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphereBackground()
                
                VStack(spacing: 0) {
                    TellTopBar(subtitle: "Browse", title: "Sailors")
                    
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            searchBar
                            
                            if isSearchActive {
                                searchResultsSection
                            } else {
                                favoritesSection
                                defaultListSection
                            }
                        }
                        .padding(.bottom, 100)
                    }
                    .refreshable {
                        await refreshAll()
                    }
                }
            }
            // Debounced search — re-runs whenever the term changes.
            .task(id: search) {
                await runSearch()
            }
            // Refresh the favorites snapshot once, in the background.
            .task {
                guard !hasRefreshedFavorites else { return }
                hasRefreshedFavorites = true
                await refreshFavorites()
            }
            .navigationDestination(for: Sailor.self) { sailor in
                SailorProfileView(sailor: sailor)
                    .environmentObject(repository)
                    .environmentObject(sailorStore)
                    .environmentObject(store)
                    .environmentObject(tabManager)
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.tellTextMute)
                .font(.system(size: 15))
            TextField("Search by name or sail number…", text: $search)
                .font(.system(size: 15))
                .foregroundColor(.tellText)
                .tint(.tellAccent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
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

    // MARK: - Favorites section

    @ViewBuilder
    private var favoritesSection: some View {
        if !sailorStore.favorites.isEmpty {
            TellSectionHeader(
                title: "Favorites",
                subtitle: "\(sailorStore.favorites.count) sailor\(sailorStore.favorites.count == 1 ? "" : "s")"
            )

            ForEach(sailorStore.sortedForDisplay) { fav in
                NavigationLink(value: Sailor(favorite: fav)) {
                    SailorHubRow(
                        name: fav.displayName,
                        sailNumber: fav.primarySailNumber,
                        club: fav.primaryClub,
                        country: fav.country,
                        eventCount: fav.eventCount,
                        isShared: fav.isSharedAccount,
                        isFavorite: true
                    )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Default "most active" list

    @ViewBuilder
    private var defaultListSection: some View {
        TellSectionHeader(
            title: sailorStore.favorites.isEmpty ? "Sailors" : "Most Active",
            subtitle: "Most events sailed"
        )

        if repository.defaultSailors.isEmpty {
            sailorLoadingSkeleton
        } else {
            ForEach(repository.defaultSailors) { sailor in
                sailorButton(sailor)
            }
        }
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResultsSection: some View {
        TellSectionHeader(
            title: "Results",
            subtitle: isSearching ? "Searching…"
                                  : "\(searchResults.count) match\(searchResults.count == 1 ? "" : "es")"
        )

        if isSearching && searchResults.isEmpty {
            sailorLoadingSkeleton
        } else if searchResults.isEmpty {
            searchEmptyState
        } else {
            ForEach(searchResults) { sailor in
                sailorButton(sailor)
            }

            if isLoadingMore {
                ProgressView()
                    .tint(.tellCool)
                    .padding(.vertical, 16)
            } else if canLoadMore {
                loadMoreButton
            }
        }
    }

    // MARK: - Reusable sailor button

    private func sailorButton(_ sailor: Sailor) -> some View {
        NavigationLink(value: sailor) {
            SailorHubRow(
                name: sailor.displayName,
                sailNumber: sailor.primarySailNumber,
                club: sailor.primaryClub,
                country: sailor.country,
                eventCount: sailor.eventCount,
                isShared: sailor.isSharedAccount,
                isFavorite: sailorStore.isFavorite(sailor)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    // MARK: - Load more

    private var loadMoreButton: some View {
        Button {
            Task { await loadMoreSearchResults() }
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

    private var sailorLoadingSkeleton: some View {
        VStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 72)
                    .padding(.horizontal, 16)
                    .shimmer()
            }
        }
        .padding(.top, 4)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 38))
                .foregroundColor(.tellTextMute)
            Text("No sailors found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tellTextDim)
            Text("Try a different name or sail number")
                .font(.system(size: 14))
                .foregroundColor(.tellTextMute)
        }
        .padding(.top, 50)
        .padding(.bottom, 30)
    }

    // MARK: - Data actions

    /// Debounced search. SwiftUI restarts this task on every `search`
    /// change; the sleep lets rapid typing cancel in-flight queries
    /// before they hit the network.
    private func runSearch() async {
        guard let term = activeTerm else {
            // Bar cleared — drop results, default list shows instead.
            searchResults = []
            isSearching   = false
            canLoadMore   = false
            return
        }

        // Debounce: 300ms. If the user types again the task is cancelled.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }

        isSearching  = true
        searchOffset = 0

        let results = await repository.searchSailors(term: term, offset: 0)
        guard !Task.isCancelled else { return }

        searchResults = results
        searchOffset  = results.count
        canLoadMore   = results.count >= RegattaRepository.sailorPageSize
        isSearching   = false
    }

    private func loadMoreSearchResults() async {
        guard let term = activeTerm, !isLoadingMore else { return }
        isLoadingMore = true

        let more = await repository.searchSailors(term: term, offset: searchOffset)
        searchResults.append(contentsOf: more)
        searchOffset += more.count
        canLoadMore   = more.count >= RegattaRepository.sailorPageSize
        isLoadingMore = false
    }

    /// Pull-to-refresh: refresh both the default list and the favorites
    /// snapshot. (If a search is active, also re-run the search.)
    private func refreshAll() async {
        async let defaults: () = repository.loadDefaultSailors()
        async let favs: ()     = refreshFavorites()
        _ = await (defaults, favs)
        if isSearchActive { await runSearch() }
    }

    /// Re-fetch the favorited sailors by id and update their snapshots.
    private func refreshFavorites() async {
        let ids = sailorStore.favoriteIds
        guard !ids.isEmpty else { return }
        let fresh = await repository.fetchSailors(ids: ids)
        guard !fresh.isEmpty else { return }
        sailorStore.applyRefresh(fresh)
    }

    /// Open a profile from a favorite snapshot. We construct a lightweight
    /// Sailor from the snapshot so the sheet opens instantly; the profile
    /// view itself re-fetches the authoritative sailor + entries.
    private func openProfile(fromFavorite fav: FavoriteSailor) {
        profileSailor = Sailor(favorite: fav)
    }
}

// MARK: - Sailor from favorite snapshot

extension Sailor {
    /// Build a placeholder Sailor from a stored favorite, so a profile
    /// sheet can open without a round trip. SailorProfileView refreshes
    /// the real row on appear.
    init(favorite f: FavoriteSailor) {
        self.id                = f.id
        self.sourceId          = "clubspot"
        self.sourceUserId      = ""
        self.displayName       = f.displayName
        self.normalizedName    = f.displayName?.lowercased()
        self.primarySailNumber = f.primarySailNumber
        self.primaryClub       = f.primaryClub
        self.country           = f.country
        self.eventCount        = f.eventCount
        self.isSharedAccount   = f.isSharedAccount
        self.distinctNameCount = 0
        self.firstSeenAt       = nil
        self.lastSeenAt        = nil
    }
}

struct SailorHubRow: View {
    let name: String?
    let sailNumber: String?
    let club: String?
    let country: String?
    let eventCount: Int
    let isShared: Bool
    let isFavorite: Bool

    private var displayName: String {
        if let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        return "Unknown Sailor"
    }

    private var monogram: String {
        let parts = displayName
            .split(separator: " ")
            .filter { $0.first?.isLetter == true }
        if let first = parts.first?.first, let last = parts.dropFirst().first?.first {
            return "\(first)\(last)".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    /// Stable per-sailor hue for the monogram tile.
    private var tileHue: Double {
        let scalar = displayName.unicodeScalars.first?.value ?? 200
        return Double(scalar % 360) / 360.0
    }

    private var eventCountText: String {
        "\(eventCount) event\(eventCount == 1 ? "" : "s")"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Monogram tile
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hue: tileHue, saturation: 0.35, brightness: 0.38))
                    .frame(width: 52, height: 52)

                Text(monogram)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.leading, 8)
            .padding(.vertical, 8)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.tellText)
                        .lineLimit(1)
                        .tracking(-0.2)

                    if isShared {
                        StatusPill(text: "Club", tone: .ghost)
                    }
                }

                HStack(spacing: 10) {
                    if let sail = sailNumber, !sail.isEmpty {
                        Label(sail, systemImage: "number")
                            .lineLimit(1)
                    }
                    if let club = club, !club.isEmpty {
                        Label(club, systemImage: "flag")
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundColor(.tellTextDim)
                .labelStyle(CompactLabelStyle())

                Text(eventCountText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.tellTextMute)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .padding(.vertical, 10)

            Spacer(minLength: 0)

            // Favorite indicator
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.tellAmber)
                    .padding(.trailing, 14)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.tellTextMute)
                    .padding(.trailing, 14)
            }
        }
        .glassCard(railColor: .tellCool)
        .padding(.horizontal, 16)
    }
}
