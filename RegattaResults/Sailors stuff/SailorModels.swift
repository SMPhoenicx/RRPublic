//
//  SailorModels.swift
//  RegattaResults
//
//  Models for the Sailors feature. Backed by two Supabase tables:
//    • sailors        — one row per distinct Clubspot user (93k rows)
//    • sailor_entries — one row per registration (320k rows)
//
//  The Sailors tab never loads the full sailors table. It shows a
//  small "most active" default page (preloaded at launch), favorited
//  sailors (persisted locally), and live server-side search results.
//  A sailor's full entry history loads on demand when their profile
//  is opened.
//

import Foundation
import SwiftUI

// MARK: - Sailor (sailors table)

/// A distinct competitor aggregated across every event they've sailed.
/// Identity-level data only — the per-event history lives in `SailorEntry`.
struct Sailor: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let sourceId: String
    let sourceUserId: String
    let displayName: String?
    let normalizedName: String?
    let primarySailNumber: String?
    let primaryClub: String?
    let country: String?
    let eventCount: Int
    let isSharedAccount: Bool
    let distinctNameCount: Int
    let firstSeenAt: Date?
    let lastSeenAt: Date?

    /// Best human label, never empty.
    var name: String {
        if let n = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        return "Unknown Sailor"
    }

    /// Two-letter monogram for the avatar tile.
    var monogram: String {
        let parts = name
            .split(separator: " ")
            .filter { $0.first?.isLetter == true }
        if let first = parts.first?.first, let last = parts.dropFirst().first?.first {
            return "\(first)\(last)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceId          = "source_id"
        case sourceUserId      = "source_user_id"
        case displayName       = "display_name"
        case normalizedName    = "normalized_name"
        case primarySailNumber = "primary_sail_number"
        case primaryClub       = "primary_club"
        case country
        case eventCount        = "event_count"
        case isSharedAccount   = "is_shared_account"
        case distinctNameCount = "distinct_name_count"
        case firstSeenAt       = "first_seen_at"
        case lastSeenAt        = "last_seen_at"
    }

    // Tolerant decoder: a single malformed row shouldn't tank the whole list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(UUID.self, forKey: .id)
        sourceId          = (try? c.decode(String.self, forKey: .sourceId)) ?? "clubspot"
        sourceUserId      = (try? c.decode(String.self, forKey: .sourceUserId)) ?? ""
        displayName       = try c.decodeIfPresent(String.self, forKey: .displayName)
        normalizedName    = try c.decodeIfPresent(String.self, forKey: .normalizedName)
        primarySailNumber = try c.decodeIfPresent(String.self, forKey: .primarySailNumber)
        primaryClub       = try c.decodeIfPresent(String.self, forKey: .primaryClub)
        country           = try c.decodeIfPresent(String.self, forKey: .country)
        eventCount        = (try? c.decode(Int.self, forKey: .eventCount)) ?? 0
        isSharedAccount   = (try? c.decode(Bool.self, forKey: .isSharedAccount)) ?? false
        distinctNameCount = (try? c.decode(Int.self, forKey: .distinctNameCount)) ?? 0
        firstSeenAt       = try c.decodeIfPresent(Date.self, forKey: .firstSeenAt)
        lastSeenAt        = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
    }
}

// MARK: - SailorEntry (sailor_entries table + joined event)

/// One row per registration. When fetched for a profile it carries the
/// joined event's name / date / status so the profile list is a single
/// query. Result fields are nil until results exist for that event.
struct SailorEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let sailorId: UUID
    let eventId: UUID
    let sourceRegId: String
    let boatClassId: UUID?
    let boatClassName: String?
    let sailNumber: String?
    let finishPosition: Int?
    let fleetSize: Int?
    let netPoints: Double?
    let raceCount: Int?
    let statusAtSync: String?
    let updatedAt: Date?

    // Joined from `events` (present when fetched via fetchSailorProfile).
    let eventName: String?
    let eventStartDate: Date?
    let eventEndDate: Date?
    let eventStatus: String?

    /// Display name for the event row, never empty.
    var displayEventName: String {
        if let n = eventName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        return "Unnamed Regatta"
    }

    /// Whether this entry has a usable finishing result.
    var hasResult: Bool {
        finishPosition != nil && fleetSize != nil
    }

    /// "3rd of 24" style placing string, or nil if no result yet.
    var placingText: String? {
        guard let pos = finishPosition, let size = fleetSize else { return nil }
        return "\(pos.ordinalString) of \(size)"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sailorId       = "sailor_id"
        case eventId        = "event_id"
        case sourceRegId    = "source_reg_id"
        case boatClassId    = "boat_class_id"
        case boatClassName  = "boat_class_name"
        case sailNumber     = "sail_number"
        case finishPosition = "finish_position"
        case fleetSize      = "fleet_size"
        case netPoints      = "net_points"
        case raceCount      = "race_count"
        case statusAtSync   = "status_at_sync"
        case updatedAt      = "updated_at"
    }

    /// Nested shape of the `events` join: `select("*, events(name,...)")`.
    private struct JoinedEvent: Codable {
        let name: String?
        let startDate: Date?
        let endDate: Date?
        let status: String?
        enum CodingKeys: String, CodingKey {
            case name
            case startDate = "start_date"
            case endDate   = "end_date"
            case status
        }
    }
    
    private enum JoinKeys: String, CodingKey { case events }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self, forKey: .id)
        sailorId       = try c.decode(UUID.self, forKey: .sailorId)
        eventId        = try c.decode(UUID.self, forKey: .eventId)
        sourceRegId    = (try? c.decode(String.self, forKey: .sourceRegId)) ?? ""
        boatClassId    = try c.decodeIfPresent(UUID.self,   forKey: .boatClassId)
        boatClassName  = try c.decodeIfPresent(String.self, forKey: .boatClassName)
        sailNumber     = try c.decodeIfPresent(String.self, forKey: .sailNumber)
        finishPosition = try c.decodeIfPresent(Int.self,    forKey: .finishPosition)
        fleetSize      = try c.decodeIfPresent(Int.self,    forKey: .fleetSize)
        netPoints      = try c.decodeIfPresent(Double.self, forKey: .netPoints)
        raceCount      = try c.decodeIfPresent(Int.self,    forKey: .raceCount)
        statusAtSync   = try c.decodeIfPresent(String.self, forKey: .statusAtSync)
        updatedAt      = try c.decodeIfPresent(Date.self,   forKey: .updatedAt)

        let joinContainer = try decoder.container(keyedBy: JoinKeys.self)
        let joined = try joinContainer.decodeIfPresent(JoinedEvent.self, forKey: .events)
        eventName      = joined?.name
        eventStartDate = joined?.startDate
        eventEndDate   = joined?.endDate
        eventStatus    = joined?.status
    }
}

// MARK: - Profile status label

/// How a sailor's entry should be labelled on their profile, derived from
/// the joined event status (an entry with no finishPosition is either an
/// upcoming registration or a still-live event).
enum EntryResultState {
    case registered      // upcoming event, no result yet
    case provisional     // live event, results in progress
    case finalized       // completed event with a result
    case pending         // completed event but no result row (stale / not scored)

    var label: String {
        switch self {
        case .registered:  return "Registered"
        case .provisional: return "Provisional"
        case .finalized:   return "Final"
        case .pending:     return "Pending"
        }
    }
}

extension SailorEntry {
    var resultState: EntryResultState {
        switch eventStatus {
        case "upcoming": return .registered
        case "live":     return hasResult ? .provisional : .registered
        default:         return hasResult ? .finalized : .pending
        }
    }
}

// MARK: - Int ordinal helper

extension Int {
    /// 1 -> "1st", 2 -> "2nd", 11 -> "11th", etc.
    var ordinalString: String {
        let ones = self % 10
        let tens = (self / 10) % 10
        let suffix: String
        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1:  suffix = "st"
            case 2:  suffix = "nd"
            case 3:  suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(self)\(suffix)"
    }
}

// MARK: - FavoriteSailor model
struct FavoriteSailor: Codable, Identifiable, Equatable {
    let id: UUID                 // == Sailor.id (Supabase UUID)
    var displayName: String?
    var primarySailNumber: String?
    var primaryClub: String?
    var country: String?
    var eventCount: Int
    var isSharedAccount: Bool
    var favoritedAt: Date

    init(from sailor: Sailor) {
        self.id                = sailor.id
        self.displayName       = sailor.displayName
        self.primarySailNumber = sailor.primarySailNumber
        self.primaryClub       = sailor.primaryClub
        self.country           = sailor.country
        self.eventCount        = sailor.eventCount
        self.isSharedAccount   = sailor.isSharedAccount
        self.favoritedAt       = Date()
    }

    /// Refresh the display snapshot from a freshly-fetched sailor,
    /// preserving the original favorited timestamp.
    mutating func refresh(from sailor: Sailor) {
        displayName       = sailor.displayName
        primarySailNumber = sailor.primarySailNumber
        primaryClub       = sailor.primaryClub
        country           = sailor.country
        eventCount        = sailor.eventCount
        isSharedAccount   = sailor.isSharedAccount
    }
}

// MARK: - FavoriteSailorStore

@MainActor
final class FavoriteSailorStore: ObservableObject {

    /// Favorited sailors, newest-favorited first.
    @Published private(set) var favorites: [FavoriteSailor] = []

    private let defaultsKey = "favoriteSailors.v1"

    init() { load() }

    // MARK: - Queries

    var favoriteIds: [UUID] { favorites.map { $0.id } }

    func isFavorite(_ sailorId: UUID) -> Bool {
        favorites.contains { $0.id == sailorId }
    }

    func isFavorite(_ sailor: Sailor) -> Bool {
        isFavorite(sailor.id)
    }

    /// Favorites sorted for display: most events first, then name.
    var sortedForDisplay: [FavoriteSailor] {
        favorites.sorted {
            if $0.eventCount != $1.eventCount { return $0.eventCount > $1.eventCount }
            return ($0.displayName ?? "") < ($1.displayName ?? "")
        }
    }

    // MARK: - Mutations

    func toggleFavorite(_ sailor: Sailor) {
        if let idx = favorites.firstIndex(where: { $0.id == sailor.id }) {
            favorites.remove(at: idx)
        } else {
            favorites.insert(FavoriteSailor(from: sailor), at: 0)
        }
        save()
    }

    func remove(_ sailorId: UUID) {
        favorites.removeAll { $0.id == sailorId }
        save()
    }

    /// Replace the display snapshots of favorites with freshly-fetched
    /// sailor rows. Any favorite whose id is absent from `fresh` is left
    /// as-is (the sailor row may simply not have been returned).
    func applyRefresh(_ fresh: [Sailor]) {
        let byId = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })
        for idx in favorites.indices {
            if let updated = byId[favorites[idx].id] {
                favorites[idx].refresh(from: updated)
            }
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data   = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([FavoriteSailor].self, from: data)
        else { return }
        favorites = stored
    }
}
