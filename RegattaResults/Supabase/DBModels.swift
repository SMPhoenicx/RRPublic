//
//  DBModels.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/12/26.
//

import Foundation

// MARK: - Event (events table)

struct DBEvent: Codable, Identifiable {
    let id: UUID
    let sourceId: String
    let sourceEventId: String
    let name: String?
    let clubName: String?
    let location: String?
    let startDate: Date?
    let endDate: Date?
    let status: String?
    let pollingMode: String?
    let hotUntil: Date?
    let imageURL: String?
    let boatClassesSyncedAt: Date?
    let documentsSyncedAt: Date?
    let subeventsSyncedAt: Date?
    let registrationsSyncedAt: Date?
    let resultsSyncedAt: Date?
    
    var displayName: String { name ?? "Unnamed Regatta" }
    var isLive: Bool { status == "live" || pollingMode == "auto" }
    var isUpcoming: Bool { status == "upcoming" }
    var isCompleted: Bool { status == "completed" }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceId       = "source_id"
        case sourceEventId  = "source_event_id"
        case name
        case clubName       = "club_name"
        case location
        case startDate      = "start_date"
        case endDate        = "end_date"
        case status
        case pollingMode    = "polling_mode"
        case hotUntil       = "hot_until"
        case imageURL       = "image_url"
        case boatClassesSyncedAt    = "boat_classes_synced_at"
        case documentsSyncedAt      = "documents_synced_at"
        case subeventsSyncedAt      = "subevents_synced_at"
        case registrationsSyncedAt  = "registrations_synced_at"
        case resultsSyncedAt        = "results_synced_at"
    }
    
    func withHotUntil(_ newHotUntil: Date?) -> DBEvent {
        DBEvent(
            id: id, sourceId: sourceId, sourceEventId: sourceEventId,
            name: name, clubName: clubName, location: location,
            startDate: startDate, endDate: endDate, status: status,
            pollingMode: pollingMode, hotUntil: newHotUntil, imageURL: imageURL,
            boatClassesSyncedAt:   boatClassesSyncedAt,
            documentsSyncedAt:     documentsSyncedAt,
            subeventsSyncedAt:     subeventsSyncedAt,
            registrationsSyncedAt: registrationsSyncedAt,
            resultsSyncedAt:       resultsSyncedAt
        )
    }
}

// MARK: - Boat Class

struct DBBoatClass: Codable, Identifiable {
    let id: UUID
    let eventId: UUID
    let sourceClassId: String
    let name: String?
    let shortName: String?
    let boatCount: Int?

    var displayName: String { name ?? shortName ?? "Unknown Class" }

    enum CodingKeys: String, CodingKey {
        case id
        case eventId        = "event_id"
        case sourceClassId  = "source_class_id"
        case name
        case shortName      = "short_name"
        case boatCount      = "boat_count"
    }
}

// MARK: - Results

struct DBResult: Codable, Identifiable {
    let id: UUID
    let eventId: UUID
    let boatClassId: UUID
    let sourceRegId: String?
    let names: [String]
    let sailNumber: String?
    let clubName: String?
    let country: String?
    let boatName: String?
    let handicapPhrf: Int?
    let totalPoints: Double?
    let netPoints: Double?
    let fleetId: String?
    let finishPosition: Int?
    let raceScores: [DBRaceScore]

    enum CodingKeys: String, CodingKey {
        case id
        case eventId        = "event_id"
        case boatClassId    = "boat_class_id"
        case sourceRegId    = "source_reg_id"
        case names
        case sailNumber     = "sail_number"
        case clubName       = "club_name"
        case country
        case boatName       = "boat_name"
        case handicapPhrf   = "handicap_phrf"
        case totalPoints    = "total_points"
        case netPoints      = "net_points"
        case fleetId        = "fleet_id"
        case finishPosition = "finish_position"
        case raceScores     = "race_scores"
    }

    // Custom decoder: tolerates nullable jsonb columns and missing fields so a
    // single bad row doesn't tank the whole query.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self, forKey: .id)
        eventId        = try c.decode(UUID.self, forKey: .eventId)
        boatClassId    = try c.decode(UUID.self, forKey: .boatClassId)
        sourceRegId    = try c.decodeIfPresent(String.self,        forKey: .sourceRegId)
        names          = (try c.decodeIfPresent([String].self,     forKey: .names)) ?? []
        sailNumber     = try c.decodeIfPresent(String.self,        forKey: .sailNumber)
        clubName       = try c.decodeIfPresent(String.self,        forKey: .clubName)
        country        = try c.decodeIfPresent(String.self,        forKey: .country)
        boatName       = try c.decodeIfPresent(String.self,        forKey: .boatName)
        handicapPhrf   = try c.decodeIfPresent(Int.self,           forKey: .handicapPhrf)
        totalPoints    = try c.decodeIfPresent(Double.self,        forKey: .totalPoints)
        netPoints      = try c.decodeIfPresent(Double.self,        forKey: .netPoints)
        fleetId        = try c.decodeIfPresent(String.self,        forKey: .fleetId)
        finishPosition = try c.decodeIfPresent(Int.self,           forKey: .finishPosition)
        raceScores     = (try c.decodeIfPresent([DBRaceScore].self, forKey: .raceScores)) ?? []
    }

    // Convert to the existing display model used throughout the app UI
    func toProcessedCompetitor(divisionName: String? = nil) -> ProcessedCompetitor {
        ProcessedCompetitor(from: self, divisionName: divisionName)
    }
}

// MARK: - Race Score

struct DBRaceScore: Codable, Identifiable {
    let scoreId: String?
    let raceNumber: Int?
    let points: Double?
    let rawScore: Double?
    let letterScore: String?
    let throwout: Bool?
    let finishTime: String?
    /// In the Clubspot payload this is a numeric value (corrected seconds, fractional),
    /// not a formatted string — declaring it as `String?` was tanking the entire
    /// results decode.
    let correctedTime: Double?
    let millisecondsElapsed: Int?
    let startData: DBStartData?

    var id: String { scoreId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case scoreId              = "score_id"
        case raceNumber           = "race_number"
        case points
        case rawScore             = "raw_score"
        case letterScore          = "letter_score"
        case throwout
        case finishTime           = "finish_time"
        case correctedTime        = "corrected_time"
        case millisecondsElapsed  = "milliseconds_elapsed"
        case startData            = "start_data"
    }
}

struct DBStartData: Codable {
    let fleetId: String?
    let startTime: String?
    let phrfA: Double?
    let phrfB: Double?
    let wind: Double?

    enum CodingKeys: String, CodingKey {
        case fleetId    = "fleet_id"
        case startTime  = "start_time"
        case phrfA      = "phrf_a"
        case phrfB      = "phrf_b"
        case wind
    }
}

// MARK: - Documents

struct DBDocument: Codable, Identifiable {
    let id: UUID
    let eventId: UUID
    let sourceDocId: String
    let title: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id
        case eventId    = "event_id"
        case sourceDocId = "source_doc_id"
        case title
        case url
    }
}

// MARK: - Subevents

struct DBSubevent: Codable, Identifiable {
    let id: UUID
    let eventId: UUID
    let sourceSubId: String
    let name: String?
    let startTime: Date?
    let endTime: Date?
    let raceNumbers: [Int]
    let disableThrowouts: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case eventId         = "event_id"
        case sourceSubId     = "source_sub_id"
        case name
        case startTime       = "start_time"
        case endTime         = "end_time"
        case raceNumbers     = "race_numbers"
        case disableThrowouts = "disable_throwouts"
    }
}

// MARK: - Registration (registrations table)

/// A sailor entry for an event. Comes from the `registrations` table and
/// represents who *signed up*, regardless of whether they've raced yet.
/// `sourceUserId` is the stable Clubspot `_User` objectId — present for ~45%
/// of registrations (newer regs and known users), used later for the
/// cross-event Sailors feature.
struct DBRegistration: Codable, Identifiable {
    let id: UUID
    let eventId: UUID
    let boatClassId: UUID?          // nullable in DB
    let sourceRegId: String
    let sourceUserId: String?
    let skipperName: String?
    let boatName: String?
    let sailNumber: String?
    let yachtClub: String?
    let participantNames: [String]?
    let registrationStatus: String?
    let country: String?
    let waitlist: Bool?
    let checkInStatus: String?

    /// Best human label for the boat: skipper, else first crew, else "Unknown".
    var primaryName: String {
        if let s = skipperName, !s.isEmpty { return s }
        if let first = participantNames?.first, !first.isEmpty { return first }
        return "Unknown sailor"
    }

    /// All names joined ("Brad Boudreau / David Farrell").
    var displayNames: String {
        if let ps = participantNames, !ps.isEmpty {
            return ps.joined(separator: " / ")
        }
        return primaryName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case eventId            = "event_id"
        case boatClassId        = "boat_class_id"
        case sourceRegId        = "source_reg_id"
        case sourceUserId       = "source_user_id"
        case skipperName        = "skipper_name"
        case boatName           = "boat_name"
        case sailNumber         = "sail_number"
        case yachtClub          = "yacht_club"
        case participantNames   = "participant_names"
        case registrationStatus = "registration_status"
        case country
        case waitlist
        case checkInStatus      = "check_in_status"
    }
}

// MARK: - Extension: DBResult → ProcessedCompetitor

extension ProcessedCompetitor {
    init(from result: DBResult, divisionName: String? = nil) {
        self.stableId    = result.sourceRegId ?? result.id.uuidString
        self.names       = result.names
        self.sailNumber  = result.sailNumber
        self.club        = result.clubName
        self.boatName    = result.boatName
        self.country     = result.country
        self.total       = Int(result.totalPoints ?? 0)
        self.net         = Int(result.netPoints ?? result.totalPoints ?? 0)
        self.divisionName = divisionName
        self.scores      = result.raceScores.compactMap { score in
            guard let raceNum = score.raceNumber else { return nil }
            return RaceResult(
                raceNumber:  raceNum,
                points:      Int(score.points ?? 0),
                letterScore: score.letterScore,
                throwout:    score.throwout ?? false
            )
        }
        .sorted { $0.raceNumber < $1.raceNumber }
    }
}
