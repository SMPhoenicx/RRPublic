//
//  RegattaNetworkModels.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 7/27/25.
//

import Foundation

// MARK: - Main Regatta Response
struct RegattaNetworkResponse: Codable, Equatable {
    let eventInfo: NetworkEventInfo?
    let divisions: [Division]
    let metadata: RegattaMetadata
    
    enum CodingKeys: String, CodingKey {
        case eventInfo = "event_info"
        case divisions
        case metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        eventInfo = try container.decodeIfPresent(NetworkEventInfo.self, forKey: .eventInfo)
        divisions = try container.decodeIfPresent([Division].self, forKey: .divisions) ?? []
        metadata = try container.decode(RegattaMetadata.self, forKey: .metadata)
    }
    
    static func == (responseOne: RegattaNetworkResponse, responseTwo: RegattaNetworkResponse) -> Bool{
        return responseOne.divisions[0] == responseOne.divisions[0]
    }
}

// MARK: - Event Info
struct NetworkEventInfo: Codable {
    let logoUrl: String?
    let title: String
    let clubName: String
    let dates: String?
    
    enum CodingKeys: String, CodingKey {
        case logoUrl = "logo_url"
        case title
        case clubName = "club_name"
        case dates
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        logoUrl = try container.decodeIfPresent(String.self, forKey: .logoUrl)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        clubName = try container.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        dates = try container.decodeIfPresent(String.self, forKey: .dates)
    }
}

// MARK: - Division
struct Division: Codable, Identifiable, Equatable {
    let id = UUID() // For SwiftUI ForEach
    let name: String
    let boatCount: Int
    let racesScored: Int
    let lastUpdated: String
    let results: [NetworkRaceResult]
    let metadata: DivisionMetadata?
    
    enum CodingKeys: String, CodingKey {
        case name
        case boatCount = "boat_count"
        case racesScored = "races_scored"
        case lastUpdated = "last_updated"
        case results
        case metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        boatCount = try container.decodeIfPresent(Int.self, forKey: .boatCount) ?? 0
        racesScored = try container.decodeIfPresent(Int.self, forKey: .racesScored) ?? 0
        lastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated) ?? ""
        results = try container.decodeIfPresent([NetworkRaceResult].self, forKey: .results) ?? []
        metadata = try container.decodeIfPresent(DivisionMetadata.self, forKey: .metadata)
    }
    static func == (divOne: Division, divTwo: Division) -> Bool{
        return divOne.id == divTwo.id
    }
}

// MARK: - Race Result
struct NetworkRaceResult: Codable, Identifiable {
    let id = UUID() // For SwiftUI ForEach
    let position: Int
    let sailNumber: String
    let boatName: String
    let skipper: String
    let raceResults: String
    let totalPoints: String
    
    enum CodingKeys: String, CodingKey {
        case position
        case sailNumber = "sail_number"
        case boatName = "boat_name"
        case skipper
        case raceResults = "race_results"
        case totalPoints = "total_points"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        sailNumber = try container.decodeIfPresent(String.self, forKey: .sailNumber) ?? ""
        boatName = try container.decodeIfPresent(String.self, forKey: .boatName) ?? ""
        skipper = try container.decodeIfPresent(String.self, forKey: .skipper) ?? ""
        raceResults = try container.decodeIfPresent(String.self, forKey: .raceResults) ?? ""
        totalPoints = try container.decodeIfPresent(String.self, forKey: .totalPoints) ?? ""
    }
}

// MARK: - Division Metadata
struct DivisionMetadata: Codable {
    let extractedAt: String
    
    enum CodingKeys: String, CodingKey {
        case extractedAt = "extracted_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        extractedAt = try container.decodeIfPresent(String.self, forKey: .extractedAt) ?? ""
    }
}

// MARK: - Regatta Metadata
struct RegattaMetadata: Codable {
    let scrapedAt: String
    let sourceUrl: String
    let totalDivisions: Int
    let scraperType: String
    
    enum CodingKeys: String, CodingKey {
        case scrapedAt = "scraped_at"
        case sourceUrl = "source_url"
        case totalDivisions = "total_divisions"
        case scraperType = "scraper_type"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        scrapedAt = try container.decodeIfPresent(String.self, forKey: .scrapedAt) ?? ""
        sourceUrl = try container.decodeIfPresent(String.self, forKey: .sourceUrl) ?? ""
        totalDivisions = try container.decodeIfPresent(Int.self, forKey: .totalDivisions) ?? 0
        scraperType = try container.decodeIfPresent(String.self, forKey: .scraperType) ?? ""
    }
}

struct ProcessedNetworkCompetitor: Identifiable, Codable, Equatable {
    let id = UUID()
    let stableId: String
    let position: Int
    let sailNumber: String
    let boatName: String
    let skipper: String
    let totalPoints: Double
    let raceResults: [NetworkRaceScore]
    
    enum CodingKeys: String, CodingKey {
            case stableId, position, sailNumber, boatName, skipper, totalPoints, raceResults
            // Note: id is excluded from coding keys since UUID() generates a new one each time
        }
    init(from networkResult: NetworkRaceResult) {
        self.position = networkResult.position
        self.sailNumber = networkResult.sailNumber
        self.boatName = networkResult.boatName
        self.skipper = networkResult.skipper
        self.stableId = "\(networkResult.sailNumber)-\(networkResult.skipper)"
        
        // Parse total points
        if let points = Double(networkResult.totalPoints) {
            self.totalPoints = points
        } else {
            self.totalPoints = 0
        }
        
        // Parse race results string
        self.raceResults = Self.parseRaceResults(networkResult.raceResults)
    }
    
    private static func parseRaceResults(_ resultsString: String) -> [NetworkRaceScore] {
        let components = resultsString.components(separatedBy: "-").filter { !$0.isEmpty }
        var raceScores: [NetworkRaceScore] = []
        
        for (index, component) in components.enumerated() {
            let raceNumber = index + 1
            
            if component.contains("/") {
                // Handle codes like "6/DNF", "6/DNS", etc.
                let parts = component.components(separatedBy: "/")
                if parts.count >= 2 {
                    let pointsString = parts[0]
                    let code = parts[1]
                    let points = Double(pointsString) ?? 0
                    
                    raceScores.append(NetworkRaceScore(
                        raceNumber: raceNumber,
                        points: points,
                        letterScore: code,
                        throwout: false
                    ))
                }
            } else {
                // Regular numeric score
                let points = Double(component) ?? 0
                raceScores.append(NetworkRaceScore(
                    raceNumber: raceNumber,
                    points: points,
                    letterScore: nil,
                    throwout: false
                ))
            }
        }
        
        return raceScores
    }
    
    static func == (compOne: ProcessedNetworkCompetitor, compTwo: ProcessedNetworkCompetitor) -> Bool{
        return compOne.id == compTwo.id
    }
}

struct NetworkRaceScore: Identifiable, Codable {
    let id = UUID()
    let raceNumber: Int
    let points: Double
    let letterScore: String?
    let throwout: Bool
    enum CodingKeys: String, CodingKey {
            case raceNumber, points, letterScore, throwout
        }
}
