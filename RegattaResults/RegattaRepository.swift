//
//  RegattaRepository.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/12/26.
//

import Foundation
import Supabase
import Combine
import SwiftUI

@MainActor
class RegattaRepository: ObservableObject {

    // MARK: - Published state

    @Published var upcomingEvents: [DBEvent] = []
    @Published var liveEvents: [DBEvent] = []
    @Published var recentEvents: [DBEvent] = []

    @Published var currentEvent: DBEvent?
    @Published var boatClasses: [DBBoatClass] = []
    @Published var results: [DBBoatClass: [DBResult]] = [:]
    @Published var documents: [DBDocument] = []
    @Published var subevents: [DBSubevent] = []
    @Published var registrations: [DBRegistration] = []
    @Published var todayEvents: [DBEvent] = []

    @Published var isLoading = false
    @Published var error: String?
    
    @Published var defaultSailors: [Sailor] = []
    
    private let supabasePublishKey: String = "sb_publishable_CA1bsUUVO_n7PzlRJKZCCg_E6Qgvf-y"
    private let supabaseURL: String = "https://qijocwtgnvyqadmnasii.supabase.co"
    private var resultsChannel: RealtimeChannelV2?
    
    static let sailorPageSize = 50
    private let enrichmentStepNames = [
        "sync-boat-classes", "sync-documents", "sync-subevents",
        "sync-registrations", "sync-results"
    ]

    // MARK: - Event lists

    func fetchUpcomingEvents() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let events: [DBEvent] = try await supabase
                .from("events")
                .select()
                .eq("source_id", value: "clubspot")
                .eq("status", value: "upcoming")
                .order("start_date", ascending: true)
                .limit(50)
                .execute()
                .value
            upcomingEvents = events
        } catch {
            self.error = error.localizedDescription
        }
    }

    func fetchLiveEvents() async {
        do {
            let events: [DBEvent] = try await supabase
                .from("events")
                .select()
                .eq("source_id", value: "clubspot")
                .eq("status", value: "live")
                .order("start_date", ascending: false)
                .execute()
                .value
            liveEvents = events
        } catch {
            self.error = error.localizedDescription
        }
    }

    func fetchRecentEvents(limit: Int = 20) async {
        do {
            let events: [DBEvent] = try await supabase
                .from("events")
                .select()
                .eq("source_id", value: "clubspot")
                .eq("status", value: "completed")
                .order("end_date", ascending: false)
                .limit(limit)
                .execute()
                .value
            recentEvents = events
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Browse / filtered fetch (Events tab)

    /// Flexible server-side query for the Events browse tab. Supports
    /// status filtering (one OR many statuses), date ranges (for
    /// "This week"/"This month"/year), tracked-event-ID filtering
    /// ("Following"), full-text search, and offset-based pagination.
    /// Returns results without storing them on a published property —
    /// the View owns its own display list.
    func fetchFilteredEvents(
        statuses: [String]? = nil,
        dateFrom: String?   = nil,
        dateTo: String?     = nil,
        eventIds: [String]? = nil,
        searchTerm: String? = nil,
        ascending: Bool     = true,
        limit: Int          = 50,
        offset: Int         = 0
    ) async -> [DBEvent] {
        do {
            var query = supabase
                .from("events")
                .select()
                .eq("source_id", value: "clubspot")

            if let statuses, !statuses.isEmpty {
                if statuses.count == 1 {
                    query = query.eq("status", value: statuses[0])
                } else {
                    query = query.in("status", values: statuses)
                }
            }
            if let dateFrom {
                query = query.gte("start_date", value: dateFrom)
            }
            if let dateTo {
                query = query.lt("start_date", value: dateTo)
            }
            if let eventIds {
                query = query.in("id", value: eventIds)
            }
            if let searchTerm, !searchTerm.isEmpty {
                // Sanitize: strip commas/dots that break PostgREST OR syntax
                let safe = searchTerm
                    .replacingOccurrences(of: ",", with: " ")
                    .replacingOccurrences(of: ".", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                if !safe.isEmpty {
                    query = query.or(
                        "name.ilike.%\(safe)%,club_name.ilike.%\(safe)%,location.ilike.%\(safe)%"
                    )
                }
            }

            let events: [DBEvent] = try await query
                .order("start_date", ascending: ascending)
                .range(from: offset, to: offset + limit - 1)
                .execute()
                .value

            return events
        } catch {
            print("[fetchFilteredEvents] error: \(error)")
            self.error = error.localizedDescription
            return []
        }
    }

    // MARK: - QR scan / URL lookup

    /// Called when user scans a QR code. Extracts regatta ID from URL and looks it up.
    func fetchEvent(fromURL urlString: String) async -> DBEvent? {
        guard let regattaId = extractRegattaId(from: urlString) else {
            self.error = "Couldn't parse regatta ID from URL"
            return nil
        }
        return await fetchEvent(bySourceId: regattaId)
    }

    func fetchEvent(bySourceId sourceEventId: String) async -> DBEvent? {
        do {
            let event: DBEvent = try await supabase
                .from("events")
                .select()
                .eq("source_event_id", value: sourceEventId)
                .single()
                .execute()
                .value
            return event
        } catch {
            // Not found — could trigger on-demand fallback here if needed
            self.error = "Event not found: \(sourceEventId)"
            return nil
        }
    }

    // MARK: - Event detail

    /// Load everything for a single event. Call when user opens an event.
    func loadEvent(_ event: DBEvent) async {
        currentEvent = event
        isLoading = true
        defer { isLoading = false }


        // Load in parallel
        async let classesTask  = fetchBoatClasses(for: event.id)
        async let docsTask     = fetchDocuments(for: event.id)
        async let subeventsTask = fetchSubevents(for: event.id)
        async let regsTask     = fetchRegistrations(for: event.id)

        let (classes, docs, subs, regs) = await (classesTask, docsTask, subeventsTask, regsTask)

        boatClasses   = classes
        documents     = docs
        subevents     = subs
        registrations = regs

        // Load results for each class
        var resultMap: [DBBoatClass: [DBResult]] = [:]
        for bc in classes {
            let classResults = await fetchResults(for: event.id, classId: bc.id)
            resultMap[bc] = classResults
        }
        results = resultMap

        #if DEBUG
        print("[loadEvent] \(event.displayName): \(classes.count) classes, " +
              "\(regs.count) registrations, \(docs.count) docs, " +
              "results=\(resultMap.values.reduce(0) { $0 + $1.count })")
        #endif
    }

    func fetchBoatClasses(for eventId: UUID) async -> [DBBoatClass] {
        do {
            return try await supabase
                .from("boat_classes")
                .select()
                .eq("event_id", value: eventId.uuidString)
                .order("name", ascending: true)
                .execute()
                .value
        } catch {
            print("[fetchBoatClasses] event=\(eventId) error: \(error)")
            self.error = error.localizedDescription
            return []
        }
    }

    func fetchResults(for eventId: UUID, classId: UUID) async -> [DBResult] {
        do {
            let results: [DBResult] = try await supabase
                .from("results")
                .select()
                .eq("event_id", value: eventId.uuidString)
                .eq("boat_class_id", value: classId.uuidString)
                .execute()
                .value

            // Sort by net points ascending (lower = better)
            return results.sorted { ($0.netPoints ?? $0.totalPoints ?? 999) < ($1.netPoints ?? $1.totalPoints ?? 999) }
        } catch {
            print("[fetchResults] event=\(eventId) class=\(classId) error: \(error)")
            self.error = error.localizedDescription
            return []
        }
    }

    func fetchDocuments(for eventId: UUID) async -> [DBDocument] {
        do {
            return try await supabase
                .from("documents")
                .select()
                .eq("event_id", value: eventId.uuidString)
                .order("title", ascending: true)
                .execute()
                .value
        } catch {
            print("[fetchDocuments] event=\(eventId) error: \(error)")
            return []
        }
    }

    func fetchSubevents(for eventId: UUID) async -> [DBSubevent] {
        do {
            return try await supabase
                .from("subevents")
                .select()
                .eq("event_id", value: eventId.uuidString)
                .execute()
                .value
        } catch {
            print("[fetchSubevents] event=\(eventId) error: \(error)")
            return []
        }
    }

    /// Fetches all registrations for an event. Used to populate the Sailors tab.
    /// Returns a flat list sorted by skipper name (alphabetical) so the tab
    /// reads naturally; the view can re-group by class if it wants to.
    func fetchRegistrations(for eventId: UUID) async -> [DBRegistration] {
        do {
            let regs: [DBRegistration] = try await supabase
                .from("registrations")
                .select()
                .eq("event_id", value: eventId.uuidString)
                .execute()
                .value

            return regs.sorted { a, b in
                a.primaryName.localizedCaseInsensitiveCompare(b.primaryName) == .orderedAscending
            }
        } catch {
            print("[fetchRegistrations] event=\(eventId) error: \(error)")
            self.error = error.localizedDescription
            return []
        }
    }

    // MARK: - Live result subscriptions

    /// Subscribe to real-time result changes for a live event.
    /// Supabase pushes updates when the sync-results function writes new data.
    func subscribeToResults(for eventId: UUID) async {
        await unsubscribeFromResults()

        resultsChannel = supabase.realtimeV2.channel("results-\(eventId)")

        let changes = await resultsChannel!.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "results",
            filter: "event_id=eq.\(eventId.uuidString)"
        )

        do {
            try await resultsChannel!.subscribeWithError()
        }
        catch{
            print("\(error)")
        }

        // Listen for any insert/update on results for this event
        Task {
            for await _ in changes {
                // Re-fetch results for all classes on any change
                if let event = currentEvent {
                    var updated: [DBBoatClass: [DBResult]] = [:]
                    for bc in boatClasses {
                        updated[bc] = await fetchResults(for: event.id, classId: bc.id)
                    }
                    await MainActor.run { self.results = updated }
                }
            }
        }
    }

    func unsubscribeFromResults() async {
        if let channel = resultsChannel {
            await supabase.realtimeV2.removeChannel(channel)
            resultsChannel = nil
        }
    }

    // MARK: - Helpers

    /// Extracts the regatta objectId from a Clubspot URL.
    /// Handles: theclubspot.com/regatta/hIuirZ3o51
    ///          racing.theclubspot.com/regatta/hIuirZ3o51
    ///          results.theclubspot.com/clubspot-results-v4/hIuirZ3o51
    private func extractRegattaId(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let components = url.pathComponents
        // Look for the component after "regatta" or the last path component for results URLs
        if let idx = components.firstIndex(of: "regatta"), idx + 1 < components.count {
            return components[idx + 1]
        }
        if url.host?.contains("results.theclubspot.com") == true {
            return components.last
        }
        return nil
    }
    
    func fetchAllHomeData() async {
        async let live: () = fetchLiveEvents()
        async let upcoming: () = fetchUpcomingEvents()
        async let sailors: () = loadDefaultSailors()
        
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday)!
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        
        async let today = fetchFilteredEvents(
            dateFrom: df.string(from: startOfToday),
            dateTo: df.string(from: startOfTomorrow),
            limit: 50
        )
        
        _ = await (live, upcoming, sailors)
        self.todayEvents = await today
    }
    
    func addEvent(
        sourceEventId: String,
        progressHandler: @escaping (AddEventProgress) -> Void
    ) async throws -> DBEvent {
        let url = URL(string: "\(supabaseURL)/functions/v1/add-event")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabasePublishKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["source_event_id": sourceEventId])

        // Total steps: lookup, fetch_clubspot, upsert, + 5 enrichments = 8.
        // If event already exists, fetch_clubspot and upsert are skipped so
        // the server will send 6 steps. We handle this by tracking completedSteps.
        let totalSteps = 8
        var completedSteps = 0
        var currentEventName: String? = nil

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = SSEStreamDelegate { line in
                guard line.hasPrefix("data: "),
                      let data = line.dropFirst(6).data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }

                let stepName = json["step"] as? String ?? ""
                let status   = json["status"] as? String ?? ""
                let isRunning = status == "running"

                if !isRunning { completedSteps += 1 }
                if let name = json["name"] as? String { currentEventName = name }

                let step: AddEventStep
                switch stepName {
                case "lookup":          step = .lookup
                case "fetch_clubspot":  step = .fetchClubspot
                case "upsert":          step = .upsert
                case "complete":        step = .complete
                case "error":           step = .failed(json["error"] as? String ?? "Unknown error")
                default:
                    if self.enrichmentStepNames.contains(stepName) {
                        step = .enrichment(stepName)
                    } else {
                        step = .failed("Unknown step: \(stepName)")
                    }
                }

                let progress = AddEventProgress(
                    step: step,
                    isRunning: isRunning,
                    eventName: currentEventName,
                    totalSteps: totalSteps,
                    completedSteps: completedSteps
                )

                DispatchQueue.main.async { progressHandler(progress) }

                // Complete — decode the event and resolve the continuation
                if stepName == "complete", let eventJSON = json["event"] as? [String: Any],
                   let eventData = try? JSONSerialization.data(withJSONObject: eventJSON) {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    if let event = try? decoder.decode(DBEvent.self, from: eventData) {
                        continuation.resume(returning: event)
                    } else {
                        continuation.resume(throwing: NSError(domain: "AddEvent", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to decode event from response"]))
                    }
                }

                // Error from function
                if stepName == "error" || (stepName == "fetch_clubspot" && status == "error") {
                    let msg = json["error"] as? String ?? "Unknown error"
                    continuation.resume(throwing: NSError(domain: "AddEvent", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: msg]))
                }
            } onComplete: {
                // Stream closed without a complete event — shouldn't happen normally
                continuation.resume(throwing: NSError(domain: "AddEvent", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Stream ended without completing"]))
            }

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: request)
            task.resume()
        }
    }

    //MARK: sailor stuff
    /// Preload the default "most active sailors" page. Called from
    /// fetchAllHomeData() during the launch splash so the Sailors tab
    /// opens instantly. Cheap: 50 small rows.
    func loadDefaultSailors() async {
        let sailors = await searchSailors(term: nil, offset: 0)
        await MainActor.run { self.defaultSailors = sailors }
    }

    /// Server-side sailor search via the `search_sailors` RPC.
    ///
    /// - Parameters:
    ///   - term:   free text. nil/empty → default "most active" page.
    ///             A name prefix matches `normalized_name`; a numeric
    ///             token additionally matches `primary_sail_number`.
    ///   - offset: pagination offset (multiples of sailorPageSize).
    /// - Returns: up to `sailorPageSize` sailors. Empty on error.
    func searchSailors(term: String?, offset: Int) async -> [Sailor] {
        let cleaned = term?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let sailors: [Sailor] = try await supabase
                .rpc("search_sailors", params: [
                    "search_term":   (cleaned?.isEmpty == false ? cleaned! : ""),
                    "result_limit":  String(Self.sailorPageSize),
                    "result_offset": String(offset)
                ])
                .execute()
                .value
            return sailors
        } catch {
            print("[searchSailors] term=\(term ?? "nil") offset=\(offset) error: \(error)")
            await MainActor.run { self.error = error.localizedDescription }
            return []
        }
    }

    /// Fetch specific sailors by id — used to refresh the favorites
    /// snapshot. One round trip regardless of how many favorites.
    func fetchSailors(ids: [UUID]) async -> [Sailor] {
        guard !ids.isEmpty else { return [] }
        do {
            let sailors: [Sailor] = try await supabase
                .from("sailors")
                .select()
                .in("id", values: ids.map { $0.uuidString })
                .execute()
                .value
            return sailors
        } catch {
            print("[fetchSailors] ids=\(ids.count) error: \(error)")
            await MainActor.run { self.error = error.localizedDescription }
            return []
        }
    }

    /// Fetch a single sailor by id (e.g. opening a profile from a
    /// favorite snapshot, to get the freshest aggregate counts).
    func fetchSailor(id: UUID) async -> Sailor? {
        do {
            let sailor: Sailor = try await supabase
                .from("sailors")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
            return sailor
        } catch {
            print("[fetchSailor] id=\(id) error: \(error)")
            return nil
        }
    }

    /// Fetch a sailor's full entry history — every `sailor_entries` row
    /// joined to its event for name/date/status. Ordered newest event
    /// first. This is the one potentially-large sailor query, so it's
    /// only ever called on demand when a profile opens.
    func fetchSailorProfile(sailorId: UUID) async -> [SailorEntry] {
        do {
            let entries: [SailorEntry] = try await supabase
                .from("sailor_entries")
                .select("*, events(name, start_date, end_date, status)")
                .eq("sailor_id", value: sailorId.uuidString)
                .execute()
                .value

            // Sort newest event first; entries with no event date sink.
            return entries.sorted { a, b in
                switch (a.eventStartDate, b.eventStartDate) {
                case let (l?, r?): return l > r
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return a.displayEventName < b.displayEventName
                }
            }
        } catch {
            print("[fetchSailorProfile] sailor=\(sailorId) error: \(error)")
            await MainActor.run { self.error = error.localizedDescription }
            return []
        }
    }
    
    // MARK: - Subscribe / unsubscribe

    func subscribe(
            eventId: UUID,
            hours: Int,
            deviceToken: String?,
            notifyOnResults: Bool
    ) async throws -> Date {
        struct Params: Encodable {
            let target_event_id: String
            let duration_hours: Int
            let p_device_token: String?
            let p_notify_on_results: Bool
        }
        let resp: Date = try await supabase
            .rpc("subscribe_to_event", params: Params(
                target_event_id:     eventId.uuidString,
                duration_hours:      hours,
                p_device_token:      deviceToken,
                p_notify_on_results: notifyOnResults
            ))
            .execute()
            .value
        
        await MainActor.run {
            if var e = self.currentEvent, e.id == eventId {
                e = e.withHotUntil(resp)
                self.currentEvent = e
            }
        }
        return resp
    }
     
    func unsubscribe(eventId: UUID, deviceToken: String?) async throws {
        struct Params: Encodable {
            let target_event_id: String
            let p_device_token: String?
        }
        _ = try await supabase
            .rpc("unsubscribe_from_event", params: Params(
                target_event_id: eventId.uuidString,
                p_device_token:  deviceToken
            ))
            .execute()
        
        await MainActor.run {
            if var e = self.currentEvent, e.id == eventId {
                e = e.withHotUntil(nil)
                self.currentEvent = e
            }
        }
    }

    // MARK: - Manual single-enrichment refresh

    /// What gets refreshed when the user taps the "Refresh" button on
    /// a hub tab. Identifies the edge function slug to invoke.
    enum RefreshTarget {
        case results
        case documents
        case registrations
        case boatClasses
        case subevents
        case all

        var functionSlugs: [String] {
            switch self {
            case .results:       return ["sync-results"]
            case .documents:     return ["sync-documents"]
            case .registrations: return ["sync-registrations"]
            case .boatClasses:   return ["sync-boat-classes"]
            case .subevents:     return ["sync-subevents"]
            case .all:           return ["sync-boat-classes", "sync-subevents",
                                         "sync-documents", "sync-registrations",
                                         "sync-results"]
            }
        }
    }

    /// Invoke the relevant sync edge function(s) for an event on demand.
    /// Each function fetches from Clubspot, upserts the DB, and bumps
    /// its own `*_synced_at`. After the calls return, reload local data
    /// so the UI reflects what the sync wrote.
    ///
    /// Uses supabase.functions.invoke so URL/key are derived from the
    /// already-configured client rather than duplicating them here.
    func manualRefresh(eventId: UUID, target: RefreshTarget) async throws {
        // Sequential because Clubspot is rate-sensitive and the existing
        // sync-regattas fan-out is sequential for the same reason.
        for slug in target.functionSlugs {
            try await supabase.functions.invoke(
                slug,
                options: FunctionInvokeOptions(
                    method: .post,
                    query: [URLQueryItem(name: "event_id", value: eventId.uuidString)]
                )
            )
        }

        // After the sync(s) succeed, reload the matching local view.
        await reloadAfterRefresh(eventId: eventId, target: target)
    }

    /// After a manual refresh completes server-side, pull the new rows
    /// (and the refreshed event with its bumped synced_at fields) into
    /// our @Published state.
    private func reloadAfterRefresh(eventId: UUID, target: RefreshTarget) async {
        // Always re-fetch the event row so synced_at timestamps update.
        if let refreshed = await fetchSingleEvent(id: eventId) {
            await MainActor.run {
                if self.currentEvent?.id == eventId {
                    self.currentEvent = refreshed
                }
            }
        }

        // Then the specific data the user asked to refresh.
        let slugs = Set(target.functionSlugs)
        if slugs.contains("sync-boat-classes") {
            let bc = await fetchBoatClasses(for: eventId)
            await MainActor.run { self.boatClasses = bc }
        }
        if slugs.contains("sync-documents") {
            let docs = await fetchDocuments(for: eventId)
            await MainActor.run { self.documents = docs }
        }
        if slugs.contains("sync-registrations") {
            let regs = await fetchRegistrations(for: eventId)
            await MainActor.run { self.registrations = regs }
        }
        if slugs.contains("sync-results") {
            // Results live keyed by boat class, so re-fetch all classes
            // (cheap) and rebuild the results map.
            let classes = boatClasses.isEmpty
                ? await fetchBoatClasses(for: eventId)
                : boatClasses
            var resultMap: [DBBoatClass: [DBResult]] = [:]
            for bc in classes {
                resultMap[bc] = await fetchResults(for: eventId, classId: bc.id)
            }
            await MainActor.run {
                self.boatClasses = classes
                self.results = resultMap
            }
        }
    }

    /// Fetch one event row by id with all columns (including synced_at fields).
    func fetchSingleEvent(id: UUID) async -> DBEvent? {
        do {
            let e: DBEvent = try await supabase
                .from("events")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
            return e
        } catch {
            print("[fetchSingleEvent] \(id) error: \(error)")
            return nil
        }
    }
    
    func registerDeviceToken(
           token: String,
           environment: String,
           appVersion: String?
    ) async throws {
        struct Params: Encodable {
            let p_device_token: String
            let p_environment: String
            let p_app_version: String?
        }
        _ = try await supabase
            .rpc("register_device_token", params: Params(
                p_device_token: token,
                p_environment:  environment,
                p_app_version:  appVersion
            ))
            .execute()
    }
}


// MARK: - DBBoatClass Hashable (needed for Dictionary keys)

extension DBBoatClass: Hashable {
    static func == (lhs: DBBoatClass, rhs: DBBoatClass) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}


enum AddEventStep: Equatable {
    case lookup
    case fetchClubspot
    case upsert
    case enrichment(String)   // function name e.g. "sync-boat-classes"
    case complete
    case failed(String)
}

struct AddEventProgress {
    let step: AddEventStep
    let isRunning: Bool        // true = step started, false = step finished
    let eventName: String?     // populated once Clubspot fetch completes
    let totalSteps: Int        // always 8 (lookup + fetch + upsert + 5 enrichments)
    let completedSteps: Int
}

// MARK: - URLSession SSE delegate

private class SSEStreamDelegate: NSObject, URLSessionDataDelegate {
    private let onLine: (String) -> Void
    private let onComplete: () -> Void
    private var buffer = ""
    private var didComplete = false

    init(onLine: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        self.onLine = onLine
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text
        // SSE lines are delimited by \n\n
        let parts = buffer.components(separatedBy: "\n\n")
        buffer = parts.last ?? ""
        for part in parts.dropLast() {
            for line in part.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { onLine(trimmed) }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !didComplete else { return }
        didComplete = true
        onComplete()
    }
}
