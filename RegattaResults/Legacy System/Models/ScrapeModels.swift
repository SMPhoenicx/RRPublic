import Foundation

// Main response structure matching Flask app output
struct RegattaResponse: Codable, Equatable {
    let sessionId: String
    let results: [String: FleetResults]
    let status: String?
    let timestamp: String?
    let source: String?
    let totalCombinations: Int?
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case results
        case status
        case timestamp
        case source
        case totalCombinations = "total_combinations"
    }
}

// Fleet results structure for the new format
struct FleetResults: Codable, Equatable {
    let fleetResults: [Competitor]
    let metadata: FleetMetadata
    
    enum CodingKeys: String, CodingKey {
        case fleetResults = "fleet_results"
        case metadata
    }
}

// Updated competitor structure matching the new format
struct Competitor: Codable, Identifiable, Equatable {
    let names: [String]
    let club: String
    let boatName: String?
    let sailNumber: String
    let country: String?
    let total: Double?  // Changed to Double to handle floating point
    let net: Double?    // Changed to Double to handle floating point
    let scores: [RaceScore]?
    let name: String?
    // Use sailNumber as ID since it should be unique
    var id: String { sailNumber }
    
    enum CodingKeys: String, CodingKey {
        case names
        case club
        case boatName
        case sailNumber
        case country
        case total
        case net
        case scores
        case name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        names = try container.decode([String].self, forKey: .names)
        club = try container.decode(String.self, forKey: .club)
        sailNumber = try container.decode(String.self, forKey: .sailNumber)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        boatName = try container.decodeIfPresent(String.self, forKey: .boatName)
        // Handle both Int and Double for total/net scores
        do {
            total = try container.decodeIfPresent(Double.self, forKey: .total)
        } catch {
            total = try container.decodeIfPresent(Int.self, forKey: .total).map(Double.init)
        }
        
        do {
            net = try container.decodeIfPresent(Double.self, forKey: .net)
        } catch {
            net = try container.decodeIfPresent(Int.self, forKey: .net).map(Double.init)
        }
        
        scores = try container.decodeIfPresent([RaceScore].self, forKey: .scores)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

// Race score structure
struct RaceScore: Codable, Identifiable, Equatable {
    let raceNumber: Int
    let points: Double
    let letterScore: String?
    let throwout: Bool
    
    var id: Int { raceNumber }
    
    enum CodingKeys: String, CodingKey {
        case raceNumber = "race_number"
        case points
        case letterScore
        case throwout
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        raceNumber = try container.decode(Int.self, forKey: .raceNumber)
        throwout = try container.decode(Bool.self, forKey: .throwout)
        letterScore = try container.decodeIfPresent(String.self, forKey: .letterScore)
        // Handle both Int and Double for points
        if let pointsInt = try? container.decode(Int.self, forKey: .points) {
            points = Double(pointsInt)
        } else {
            points = try container.decode(Double.self, forKey: .points)
        }
    }
}

// Fleet metadata structure
struct FleetMetadata: Codable, Equatable {
    let scrapedAt: String
    let source: String
    let totalCompetitors: Int
    let combination: [DropdownCombination]?
    
    enum CodingKeys: String, CodingKey {
        case scrapedAt = "scraped_at"
        case source
        case totalCompetitors = "total_competitors"
        case combination
    }
}

// Dropdown combination structure
struct DropdownCombination: Codable, Identifiable, Equatable {
    let value: String
    let text: String
    
    var id: String { value }
}


//Main scraper models
struct EventInfo: Codable, Equatable {
    let title: String?
    let date: String?
    let location: String?
    let imageUrl: String?
    let resultsUrl: String?
    let description: String?
    let regattaId: String?
    let pdfDocuments: [NoticeItem]?
    let originalUrl: String
    let registerUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case title, date, location, description
        case imageUrl = "image_url"
        case resultsUrl = "results_url"
        case regattaId = "regatta_id"
        case pdfDocuments = "pdf_documents"
        case originalUrl = "original_url"
        case registerUrl = "register_url"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        title = try container.decodeIfPresent(String.self, forKey: .title)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        resultsUrl = try container.decodeIfPresent(String.self, forKey: .resultsUrl)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        regattaId = try container.decodeIfPresent(String.self, forKey: .regattaId)
        originalUrl = try container.decode(String.self, forKey: .originalUrl)
        pdfDocuments = try container.decodeIfPresent([NoticeItem].self, forKey: .pdfDocuments)
        registerUrl = try container.decodeIfPresent(String.self, forKey: .registerUrl)
    }
    
    static func == (eventOne: EventInfo, eventTwo: EventInfo) -> Bool{
        return eventOne.regattaId == eventTwo.regattaId && eventOne.originalUrl == eventTwo.originalUrl
    }
}

struct NoticeItem: Codable {
    let url: String?
    let name: String
    let uploadDate: String?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case url, name, error
        case uploadDate = "upload_date"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        
        url = try container.decodeIfPresent(String.self, forKey: .url)
        uploadDate = try container.decodeIfPresent(String.self, forKey: .uploadDate)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
    
    // Add a computed property to check if this is a valid document
    var isValid: Bool {
        return url != nil
    }
    
    // Add a computed property for display purposes
    var displayName: String {
        if let error = error {
            return "\(name) (Error: \(error))"
        }
        return name
    }
}
struct EventData: Codable {
    let eventInfo: EventInfo
    let metadata: EventMetadata
    
    enum CodingKeys: String, CodingKey {
        case eventInfo = "event_info"
        case metadata
    }
}

struct EventMetadata: Codable {
    let scrapedAt: String
    let source: String
    let scraperVersion: String
    
    enum CodingKeys: String, CodingKey {
        case scrapedAt = "scraped_at"
        case source
        case scraperVersion = "scraper_version"
    }
}
