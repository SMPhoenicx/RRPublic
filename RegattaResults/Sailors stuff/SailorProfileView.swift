//
//  SailorProfileView.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/27/26.
//


//
//  SailorProfileView.swift
//  RegattaResults
//
//  A sailor's profile, opened as a sheet from the Sailors tab. Shows
//  identity (name, sail number, club) and their full entry history —
//  every event they registered for, with placing when results exist.
//
//  Loading: the entry history (sailor_entries joined to events) is the
//  one potentially-large sailor query, so it loads on demand here, in
//  a .task. The sailor passed in may be a lightweight placeholder built
//  from a favorite snapshot, so we also refresh the authoritative
//  sailor row on appear.
//

import SwiftUI

struct SailorProfileView: View {
    let sailor: Sailor

    @EnvironmentObject var repository:  RegattaRepository
    @EnvironmentObject var sailorStore: FavoriteSailorStore
    @EnvironmentObject var store: TrackedEventStore
    @EnvironmentObject var tabManager: TabManager
    
    @Environment(\.dismiss) private var dismiss

    @State private var liveSailor: Sailor
    @State private var entries: [SailorEntry] = []
    @State private var isLoading = true
    @State private var selectedEvent: DBEvent? = nil
    @State private var isLoadingEvent = false

    init(sailor: Sailor) {
        self.sailor = sailor
        _liveSailor = State(initialValue: sailor)
    }

    private var isFavorite: Bool { sailorStore.isFavorite(liveSailor.id) }

    var body: some View {
        ZStack {
            AtmosphereBackground()
            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        statsStrip

                        if isLoading {
                            loadingSkeleton
                        } else if entries.isEmpty {
                            emptyState
                        } else {
                            historySection
                        }
                    }
                    .padding(.bottom, 52)
                }
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventInfoView(event: event)
                .environmentObject(store)
                .environmentObject(repository)
                .environmentObject(tabManager)
        }
        .task {
            await loadProfile()
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        GlassStrip(dark: true) {
            VStack(spacing: 0) {
                Spacer().frame(height: 20)
                HStack{
                    Button { dismiss() } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.tellText)
                            .frame(width: 36, height: 36)
                            .glassCard(radius: 10)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding()
                HStack(alignment: .center) {
                    // Monogram
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(hue: tileHue, saturation: 0.38, brightness: 0.42))
                            .frame(width: 60, height: 60)
                        Text(liveSailor.monogram)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(liveSailor.name)
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(.tellText)
                                .tracking(-0.4)
                                .lineLimit(2)
                            if liveSailor.isSharedAccount {
                                StatusPill(text: "Club", tone: .ghost)
                            }
                        }

                        HStack(spacing: 10) {
                            if let sail = liveSailor.primarySailNumber, !sail.isEmpty {
                                Label(sail, systemImage: "number")
                            }
                            if let club = liveSailor.primaryClub, !club.isEmpty {
                                Label(club, systemImage: "flag").lineLimit(1)
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.tellTextDim)
                        .labelStyle(CompactLabelStyle())
                    }
                    .padding(.leading, 4)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

                // Action row
                HStack(spacing: 10) {
                    Button {
                        sailorStore.toggleFavorite(liveSailor)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                            Text(isFavorite ? "Favorited" : "Favorite")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(isFavorite ? .tellAmber : .tellText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(isFavorite ? Color.tellAmber.opacity(0.16)
                                                 : Color.white.opacity(0.07))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11)
                                        .stroke(isFavorite ? Color.tellAmber.opacity(0.5)
                                                           : Color.glassBorder,
                                                lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Stats strip

    private var statsStrip: some View {
        HStack(spacing: 10) {
            statCard(value: "\(liveSailor.eventCount)", label: "Events")
            statCard(value: "\(podiumCount)",          label: "Podiums")
            statCard(value: bestFinishText,            label: "Best Finish")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.tellText)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(0.8)
                .foregroundColor(.tellTextMute)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassCard(radius: 12)
    }

    // MARK: - History section

    private var historySection: some View {
        VStack(spacing: 0) {
            TellSectionHeader(
                title: "Race History",
                subtitle: "\(entries.count) entr\(entries.count == 1 ? "y" : "ies")"
            )

            ForEach(entries) { entry in
                Button {
                    Task { await openEvent(for: entry) }
                } label: {
                    SailorEntryRow(entry: entry)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Loading / empty

    private var loadingSkeleton: some View {
        VStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 70)
                    .padding(.horizontal, 16)
                    .shimmer()
            }
        }
        .padding(.top, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sailboat")
                .font(.system(size: 38))
                .foregroundColor(.tellTextMute)
            Text("No race history")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tellTextDim)
            Text("This sailor has no recorded entries yet")
                .font(.system(size: 14))
                .foregroundColor(.tellTextMute)
        }
        .padding(.top, 50)
    }

    // MARK: - Derived stats

    private var podiumCount: Int {
        entries.filter { ($0.finishPosition ?? 99) <= 3 && $0.hasResult }.count
    }

    private var bestFinishText: String {
        let positions = entries.compactMap { $0.hasResult ? $0.finishPosition : nil }
        guard let best = positions.min() else { return "—" }
        return best.ordinalString
    }

    private var tileHue: Double {
        let scalar = liveSailor.name.unicodeScalars.first?.value ?? 200
        return Double(scalar % 360) / 360.0
    }

    // MARK: - Loading

    private func loadProfile() async {
        isLoading = true

        // Refresh the authoritative sailor row (the passed-in one may be
        // a favorite-snapshot placeholder) in parallel with the history.
        async let freshSailor = repository.fetchSailor(id: sailor.id)
        async let history     = repository.fetchSailorProfile(sailorId: sailor.id)

        let (fetched, entries) = await (freshSailor, history)
        if let fetched { self.liveSailor = fetched }
        self.entries  = entries
        self.isLoading = false
    }
    
    private func openEvent(for entry: SailorEntry) async {
        guard !isLoadingEvent else { return }
        isLoadingEvent = true
        let results = await repository.fetchFilteredEvents(
            eventIds: [entry.eventId.uuidString],
            limit: 1
        )
        if let event = results.first {
            selectedEvent = event
        }
        isLoadingEvent = false
    }
}

// MARK: - Sailor entry row

private struct SailorEntryRow: View {
    let entry: SailorEntry

    private var dateText: String {
        guard let date = entry.eventStartDate else { return "Date TBD" }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    private var stateTone: StatusTone {
        switch entry.resultState {
        case .registered:  return .amber
        case .provisional: return .red
        case .finalized:   return .cyan
        case .pending:     return .ghost
        }
    }

    /// Accent color for a podium placing.
    private var placingColor: Color {
        switch entry.finishPosition {
        case 1:  return .tellAmber
        case 2:  return .tellCool
        case 3:  return .tellGreen
        default: return .tellText
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Placing block
            VStack(spacing: 1) {
                if let pos = entry.finishPosition, entry.hasResult {
                    Text("\(pos)")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(placingColor)
                    if let size = entry.fleetSize {
                        Text("of \(size)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.tellTextMute)
                    }
                } else {
                    Image(systemName: "hourglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.tellTextMute)
                }
            }
            .frame(width: 52)
            .padding(.leading, 6)
            .padding(.vertical, 10)

            // Event info
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayEventName)
                    .font(.system(size: 14.5, weight: .black))
                    .foregroundColor(.tellText)
                    .lineLimit(2)
                    .tracking(-0.2)

                HStack(spacing: 8) {
                    Text(dateText)
                    if let bc = entry.boatClassName, !bc.isEmpty {
                        Text("·")
                        Text(bc).lineLimit(1)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundColor(.tellTextDim)

                HStack(spacing: 8) {
                    StatusPill(text: entry.resultState.label, tone: stateTone)
                    if let pts = entry.netPoints, entry.hasResult {
                        Text("\(pts.clean) pts")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.tellTextMute)
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 10)

            Spacer(minLength: 0)
        }
        .glassCard(railColor: stateTone == .red ? .tellAccent : .tellCool)
        .padding(.horizontal, 16)
    }
}

// MARK: - Double display helper

private extension Double {
    /// Drops a trailing ".0" so 40.0 -> "40", 40.5 -> "40.5".
    var clean: String {
        truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(self))
            : String(self)
    }
}
