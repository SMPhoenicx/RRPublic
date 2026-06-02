//
//  APIModels.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 6/18/25.
//
import SwiftUI
import Foundation
import Combine

struct APIResponse: Codable{
    let scoresByRegistration: [CompetitorEntry]
}

struct CompetitorEntry: Codable, Identifiable {
    let registrationObject: RegistrationObject
    let scoringData: [ScoringData]?
    let total: Int
    let net: Int
    
    var id: String { registrationObject.objectId }
    
    enum CodingKeys: String, CodingKey {
        case registrationObject
        case scoringData = "scoring_data"
        case total, net
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        registrationObject = try container.decode(RegistrationObject.self, forKey: .registrationObject)
        scoringData = try container.decodeIfPresent([ScoringData].self, forKey: .scoringData)
        
        
        // Handle potential doubles for total and net
        if let totalDouble = try? container.decode(Double.self, forKey: .total) {
            total = Int(totalDouble)
        } else {
            total = try container.decode(Int.self, forKey: .total)
        }
        
        if let netDouble = try? container.decode(Double.self, forKey: .net) {
            net = Int(netDouble)
        } else {
            net = try container.decode(Int.self, forKey: .net)
        }
    }
}

struct RegistrationObject: Codable {
    let objectId: String
    let names: [String]
    let boatName: String?
    let club: String?
    let sailNumber: String?
    let country: String?
    let handicapPhrf: Int?
    let subclassesArray: [SubclassObject]?
    
    enum CodingKeys: String, CodingKey {
        case objectId
        case names = "participantNames"
        case boatName
        case club = "clubName"
        case sailNumber
        case country = "sailNumber_country"
        case handicapPhrf = "handicap_phrf"
        case subclassesArray
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objectId = try container.decode(String.self, forKey: .objectId)
        names = try container.decode([String].self, forKey: .names)
        boatName = try container.decodeIfPresent(String.self, forKey: .boatName)
        club = try container.decodeIfPresent(String.self, forKey: .club)
        sailNumber = try container.decodeIfPresent(String.self, forKey: .sailNumber)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        subclassesArray = try container.decodeIfPresent([SubclassObject].self, forKey: .subclassesArray)
        
        // Handle potential double for handicapPhrf
        if let handicapDouble = try? container.decodeIfPresent(Double.self, forKey: .handicapPhrf) {
            handicapPhrf = Int(handicapDouble)
        } else {
            handicapPhrf = try container.decodeIfPresent(Int.self, forKey: .handicapPhrf)
        }
    }
}

struct SubclassObject: Codable {
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case name
    }
}

struct ScoringData: Codable, Identifiable {
    let scoreId: String
    let raceNumber: Int
    let points: Int
    let letterScore: String?
    let throwout: Bool?
    
    var id: String { scoreId }
    
    enum CodingKeys: String, CodingKey {
        case scoreId
        case raceNumber = "race_number"
        case points
        case letterScore
        case throwout
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scoreId = try container.decode(String.self, forKey: .scoreId)
        letterScore = try container.decodeIfPresent(String.self, forKey: .letterScore)
        throwout = try container.decodeIfPresent(Bool.self, forKey: .throwout) ?? false
        
        // Handle potential doubles for raceNumber and points
        if let raceNumberDouble = try? container.decode(Double.self, forKey: .raceNumber) {
            raceNumber = Int(raceNumberDouble)
        } else {
            raceNumber = try container.decode(Int.self, forKey: .raceNumber)
        }
        
        if let pointsDouble = try? container.decode(Double.self, forKey: .points) {
            points = Int(pointsDouble)
        } else {
            points = try container.decode(Int.self, forKey: .points)
        }
    }
}

struct ProcessedCompetitor: Identifiable {
    let id = UUID()
    let stableId: String
    let names: [String]
    let club: String?
    let boatName: String?
    let sailNumber: String?
    let country: String?
    let total: Int
    let net: Int
    let scores: [RaceResult]
    let divisionName: String?
    
    init(from entry: CompetitorEntry) {
        self.stableId = entry.registrationObject.objectId 
        self.names = entry.registrationObject.names
        self.club = entry.registrationObject.club
        self.boatName = entry.registrationObject.boatName
        self.sailNumber = entry.registrationObject.sailNumber
        self.country = entry.registrationObject.country
        self.total = entry.total
        self.net = entry.net
        if let subclassesArray = entry.registrationObject.subclassesArray{
            self.divisionName = subclassesArray.first?.name ?? "None"
        }
        else{
            self.divisionName = "None"
        }
        if let scoringData = entry.scoringData {
            self.scores = scoringData.map { scoringData in
                RaceResult(
                    raceNumber: scoringData.raceNumber,
                    points: scoringData.points,
                    letterScore: scoringData.letterScore,
                    throwout: scoringData.throwout ?? false
                )
            }
        }
        else {
            self.scores = []
        }
    }
}

struct RaceResult: Identifiable {
    let id = UUID()
    let raceNumber: Int
    let points: Int
    let letterScore: String?
    let throwout: Bool
}

//MARK: - Scraper response models
struct APIDiscoveryResponse: Codable, Equatable {
    let status: String
    let apiUrls: [String: APIUrlInfo]
    let combinations: [[DropdownOption]]
    
    enum CodingKeys: String, CodingKey {
        case status
        case apiUrls = "api_urls"
        case combinations
    }
    
    static func == (firstAPI: APIDiscoveryResponse, secondAPI: APIDiscoveryResponse) -> Bool{
        return firstAPI.apiUrls == secondAPI.apiUrls
    }
}

struct APIUrlInfo: Codable, Equatable {
    let url: String
    let params: [String: [String]]
    
    static func == (firstAPI: APIUrlInfo, secondAPI: APIUrlInfo) -> Bool{
        return firstAPI.url == secondAPI.url
    }
}

struct DropdownOption: Codable, Equatable {
    let value: String
    let text: String
    
    static func == (firstAPI: DropdownOption, secondAPI: DropdownOption) -> Bool{
        return firstAPI.value == secondAPI.value
    }
}

enum APISecondError: Error, LocalizedError {
    case invalidURL
    case serverError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .serverError:
            return "Server error occurred"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}
