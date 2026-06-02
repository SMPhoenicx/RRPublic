//
//  TrackedEvent.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/16/26.
//
//

import Foundation
import SwiftUI

// MARK: - TrackedEvent model

struct TrackedEvent: Codable, Identifiable, Equatable {
    let id: UUID                    // local identifier
    let eventId: UUID               // DBEvent.id (Supabase UUID)
    let sourceEventId: String       // DBEvent.sourceEventId (Clubspot objectId etc)
    let sourceURL: String           // the scanned/entered URL, or canonical URL
    let name: String
    let clubName: String?
    let location: String?
    let startDate: Date?
    let endDate: Date?
    let imageURL: String?
    let status: String?

    var isFavorite: Bool
    var trackedAt: Date             // first time tracked
    var lastOpenedAt: Date          // last time Event Hub was opened

    // Convenience
    var displayName: String { name.isEmpty ? "Unnamed Regatta" : name }
    var isLive: Bool { status == "live" }

    // Initialise from a DBEvent at tracking time
    init(from event: DBEvent, sourceURL: String = "") {
        self.id             = UUID()
        self.eventId        = event.id
        self.sourceEventId  = event.sourceEventId
        self.sourceURL      = sourceURL.isEmpty
                                ? "https://theclubspot.com/regatta/\(event.sourceEventId)"
                                : sourceURL
        self.name           = event.displayName
        self.clubName       = event.clubName
        self.location       = event.location
        self.startDate      = event.startDate
        self.endDate        = event.endDate
        self.imageURL       = event.imageURL
        self.status         = event.status
        self.isFavorite     = false
        self.trackedAt      = Date()
        self.lastOpenedAt   = Date()
    }
}

// MARK: - TrackedEventStore

class TrackedEventStore: ObservableObject {

    /// All tracked events, newest-opened first.
    @Published private(set) var events: [TrackedEvent] = []

    /// Set when an event should be opened in EventHubView the next time
    /// TrackedView subscribes. Used to deliver a "go to hub" intent across
    /// the tab switch initiated by EventInfoView's Track / Open Hub button.
    ///
    /// Why a published property instead of NotificationCenter: TrackedView
    /// is not instantiated until the Tracked tab becomes active. A
    /// NotificationCenter post fires synchronously and is lost if no one is
    /// subscribed yet. Combine's @Published publisher (`store.$pendingHubEvent`)
    /// re-delivers the current value to new subscribers on subscription, so
    /// TrackedView picks it up on its first appearance.
    @Published var pendingHubEvent: DBEvent? = nil

    private let defaultsKey = "trackedEvents.v1"

    init() { load() }

    // MARK: - Queries

    var favorites: [TrackedEvent] {
        events.filter { $0.isFavorite }
    }

    var recentlyTracked: [TrackedEvent] {
        // Everything, sorted by last opened. Favorites can also appear here.
        events.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    func isTracked(_ event: DBEvent) -> Bool {
        events.contains { $0.eventId == event.id }
    }

    func isFavorite(_ event: DBEvent) -> Bool {
        events.first { $0.eventId == event.id }?.isFavorite ?? false
    }

    func trackedEvent(for event: DBEvent) -> TrackedEvent? {
        events.first { $0.eventId == event.id }
    }

    // MARK: - Mutations

    /// Add an event to the tracked list (if not already present) and record
    /// that it was just opened. Returns the TrackedEvent for immediate use.
    @discardableResult
    func track(_ event: DBEvent, sourceURL: String = "") -> TrackedEvent {
        if let idx = events.firstIndex(where: { $0.eventId == event.id }) {
            // Already tracked — just update lastOpenedAt
            events[idx].lastOpenedAt = Date()
            // Refresh mutable metadata that can change (status, dates)
            events[idx] = TrackedEvent(refreshing: events[idx], from: event, sourceURL: sourceURL)
            save()
            return events[idx]
        } else {
            let te = TrackedEvent(from: event, sourceURL: sourceURL)
            events.insert(te, at: 0)
            save()
            return te
        }
    }

    func recordOpen(_ event: DBEvent) {
        guard let idx = events.firstIndex(where: { $0.eventId == event.id }) else { return }
        events[idx].lastOpenedAt = Date()
        save()
    }

    func toggleFavorite(_ event: DBEvent) {
        if let idx = events.firstIndex(where: { $0.eventId == event.id }) {
            events[idx].isFavorite.toggle()
        } else {
            // Favoriting auto-tracks
            var te = TrackedEvent(from: event)
            te.isFavorite = true
            events.insert(te, at: 0)
        }
        save()
    }

    func remove(_ trackedEvent: TrackedEvent) {
        events.removeAll { $0.id == trackedEvent.id }
        save()
    }

    /// Request that TrackedView open the given event's hub on its next render.
    /// Pairs with `consumePendingHubEvent()` on the receiving side.
    func requestOpenHub(_ event: DBEvent) {
        pendingHubEvent = event
    }

    /// Atomically read and clear the pending hub event. Returns the value
    /// that was pending (or nil) and nils out the store property.
    func consumePendingHubEvent() -> DBEvent? {
        let pending = pendingHubEvent
        pendingHubEvent = nil
        return pending
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data   = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([TrackedEvent].self, from: data)
        else { return }
        events = stored
    }
}

// MARK: - TrackedEvent refresh helper
// Updates mutable fields (status, dates) while preserving tracking metadata.

extension TrackedEvent {
    init(refreshing old: TrackedEvent, from event: DBEvent, sourceURL: String) {
        self.id            = old.id
        self.eventId       = old.eventId
        self.sourceEventId = old.sourceEventId
        self.sourceURL     = sourceURL.isEmpty ? old.sourceURL : sourceURL
        self.name          = event.displayName
        self.clubName      = event.clubName
        self.location      = event.location
        self.startDate     = event.startDate
        self.endDate       = event.endDate
        self.imageURL      = event.imageURL
        self.status        = event.status
        self.isFavorite    = old.isFavorite
        self.trackedAt     = old.trackedAt
        self.lastOpenedAt  = Date()
    }
}
