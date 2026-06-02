import Foundation
import Combine
import SwiftUI

@MainActor
class APIRetrievalService: ObservableObject {
    // MARK: - Published Properties
    @Published var currentResults: [ProcessedCompetitor] = []
    @Published var isRetrieving: Bool = false
    @Published var lastUpdateTime: Date?
    @Published var errorMessage: String?
    @Published var currentDivisionName: String?
    @Published var allDivisionResults: [String: [ProcessedCompetitor]] = [:]
    @Published var isBulkRetrieving: Bool = false
    @Published var bulkRetrievalProgress: Double = 0.0
    @Published var bulkRetrievalStatus: String = ""
    
    
    // MARK: - Private Properties
    private var retrievalTimer: Timer?
    private var currentTask: Task<Void, Never>?
    private var currentURL: String?
    private let retrievalInterval: TimeInterval = 10.0 // 10 seconds
    private let session = URLSession.shared
    
    private var discoveryResponse: APIDiscoveryResponse?
    
    // Rate limiting protection
    private var requestCount: Int = 0
    private var requestWindowStart: Date = Date()
    
    // MARK: - Public Methods
    
    /// Start continuous retrieval from a specific API URL
    /// - Parameter apiURL: The API URL to retrieve data from
    func startRetrieving(from apiURL: String) {
        print("🚀 Starting API retrieval from: \(apiURL)")
        
        // Stop any existing retrieval
        stopRetrieving()
        
        // Set new URL and start
        currentURL = apiURL
        isRetrieving = true
        errorMessage = nil
        
        // Perform initial fetch immediately
        performSingleFetch()
        
        // Start continuous timer
        startRetrievalTimer()
    }
    
    /// Stop current retrieval
    func stopRetrieving() {
        print("⏹️ Stopping API retrieval")
        
        retrievalTimer?.invalidate()
        retrievalTimer = nil
        currentTask?.cancel()
        currentTask = nil
        currentURL = nil
        isRetrieving = false
    }
    /// Switch to a different API URL (stops current and starts new)
    /// - Parameter newURL: The new API URL to switch to
    func switchToURL(_ newURL: String) {
        startRetrieving(from: newURL)
    }
    
    /// Perform a single fetch without starting continuous retrieval
    /// - Parameter apiURL: The API URL to fetch from once
    func fetchOnce(from apiURL: String) {
        currentURL = apiURL
        performSingleFetch()
    }
    
    /// Check if we're currently retrieving from a specific URL
    /// - Parameter url: URL to check
    /// - Returns: True if currently retrieving from this URL
    func isRetrievingFrom(_ url: String) -> Bool {
        return isRetrieving && currentURL == url
    }
    // MARK: - Private Methods
    
    private func startRetrievalTimer() {
        retrievalTimer = Timer.scheduledTimer(withTimeInterval: retrievalInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performSingleFetch()
            }
        }
    }
    
    private func performSingleFetch() {
        guard let urlString = currentURL,
              let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            return
        }
        
        // Check rate limiting
        if !canMakeRequest() {
            print("⚠️ Rate limit approached, skipping this fetch")
            return
        }
        
        // Cancel any existing task
        currentTask?.cancel()
        
        // Start new fetch task
        currentTask = Task {
            do {
                let results = try await fetchAPIData(from: url)
                
                // Update UI on main thread
                await MainActor.run {
                    self.currentResults = results
                    self.lastUpdateTime = Date()
                    self.errorMessage = nil
                    
                    if let firstResult = results.first {
                        self.currentDivisionName = firstResult.divisionName
                    }
                    
                    print("✅ Successfully fetched \(results.count) competitors")
                }
                
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        self.errorMessage = "Failed to fetch data: \(error.localizedDescription)"
                        print("❌ Fetch error: \(error)")
                    }
                }
            }
        }
    }
    
    private func fetchAPIData(from url: URL) async throws -> [ProcessedCompetitor] {
        // Create request with headers
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30.0
        
        // Track request for rate limiting
        trackRequest()
        
        // Make the request
        let (data, response) = try await session.data(for: request)
        
        // Check response status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        // Parse JSON
        let decoder = JSONDecoder()
        
        do {
            let apiResponse = try decoder.decode(APIResponse.self, from: data)
            
            // Convert to ProcessedCompetitor objects
            let processedCompetitors = apiResponse.scoresByRegistration.map { entry in
                ProcessedCompetitor(from: entry)
            }
            
            return processedCompetitors.sorted { $0.total < $1.total } // Sort by total score
            
        } catch {
            print("🔍 JSON Decoding Error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 Raw JSON: \(String(jsonString.prefix(500)))...")
            }
            throw APIError.decodingError(error)
        }
    }
    
    // MARK: - Rate Limiting
    
    private func canMakeRequest() -> Bool {
        let now = Date()
        
        // Reset counter if window has passed
        if now.timeIntervalSince(requestWindowStart) >= 60.0 {
            requestCount = 0
            requestWindowStart = now
        }
        
        return true
    }
    
    private func trackRequest() {
        let now = Date()
        
        // Reset counter if window has passed
        if now.timeIntervalSince(requestWindowStart) >= 60.0 {
            requestCount = 0
            requestWindowStart = now
        }
        
        requestCount += 1
    }
    
    // MARK: - Cleanup
    
}

// MARK: - Error Types

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Data parsing error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Usage Examples and Helper Methods

extension APIRetrievalService {
    
    /// Get statistics about current results
    var resultStats: (totalCompetitors: Int, lastUpdate: String) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        
        return (
            totalCompetitors: currentResults.count,
            lastUpdate: lastUpdateTime.map { formatter.string(from: $0) } ?? "Never"
        )
    }
    
    /// Get competitors for a specific race number
    /// - Parameter raceNumber: The race number to filter by
    /// - Returns: Array of competitors who have results for that race
    func competitorsForRace(_ raceNumber: Int) -> [ProcessedCompetitor] {
        return currentResults.filter { competitor in
            competitor.scores.contains { $0.raceNumber == raceNumber }
        }
    }
    
    /// Get all race numbers present in current results
    var availableRaceNumbers: [Int] {
        let allRaceNumbers = currentResults.flatMap { competitor in
            competitor.scores.map { $0.raceNumber }
        }
        return Array(Set(allRaceNumbers)).sorted()
    }
}

// MARK: - Enhanced Properties for Bulk Retrieval
extension APIRetrievalService {
    /// Retrieve all division results once at the beginning
    /// - Parameters:
    ///   - urls: Dictionary of division keys to API URL info
    ///   - combinations: The dropdown combinations from discovery
    func retrieveAll(from discovery: APIDiscoveryResponse) async {
        storeDiscoveryResponse(discovery)
        let urls = discovery.apiUrls
        let combinations = discovery.combinations
        print("🔄 Starting bulk retrieval from \(urls.count) URLs")
        
        await MainActor.run {
            isBulkRetrieving = true
            bulkRetrievalProgress = 0.0
            bulkRetrievalStatus = "Starting bulk retrieval..."
            allDivisionResults.removeAll()
        }
        
        let totalURLs = urls.count
        var completedURLs = 0
        
        for (divisionKey, urlInfo) in urls {
            // Update progress
            await MainActor.run {
                bulkRetrievalStatus = "Fetching \(getDivisionName(from: divisionKey, combinations: combinations))..."
                bulkRetrievalProgress = Double(completedURLs) / Double(totalURLs)
            }
            
            do {
                // Fetch data for this URL
                let url = URL(string: urlInfo.url)!
                let results = try await fetchAPIData(from: url)
                
                // Store results with a readable division name
                let divisionName = getDivisionName(from: divisionKey, combinations: combinations)
                
                await MainActor.run {
                    allDivisionResults[divisionName] = results
                    print("✅ Successfully fetched \(results.count) competitors for \(divisionName)")
                }
                
            } catch {
                print("❌ Failed to fetch data for division \(divisionKey): \(error)")
                await MainActor.run {
                    // Store empty results for failed divisions
                    let divisionName = getDivisionName(from: divisionKey, combinations: combinations)
                    allDivisionResults[divisionName] = []
                }
            }
            
            completedURLs += 1
        }
        
        await MainActor.run {
            isBulkRetrieving = false
            bulkRetrievalProgress = 1.0
            bulkRetrievalStatus = "Bulk retrieval completed"
            print("🎉 Bulk retrieval completed: \(allDivisionResults.count) divisions loaded")
        }
    }
    
    /// Get a readable division name from the combination key
    private func getDivisionName(from key: String, combinations: [[DropdownOption]]) -> String {
        // Try to parse the JSON key back to dropdown options
        guard let data = key.data(using: .utf8),
              let dropdownOptions = try? JSONDecoder().decode([DropdownOption].self, from: data) else {
            return key.isEmpty ? "Main Results" : "Division \(key.hashValue)"
        }
        
        if dropdownOptions.isEmpty {
            return "Main Results"
        }
        
        // Create readable name from dropdown options
        let divisionName = dropdownOptions.map { $0.text }.joined(separator: " | ")
        return divisionName
    }
    
    /// Get results for a specific division name
    /// - Parameter divisionName: The division name to get results for
    /// - Returns: Array of competitors for that division, or empty array if not found
    func getResultsForDivision(_ divisionName: String) -> [ProcessedCompetitor] {
        return allDivisionResults[divisionName] ?? []
    }
    
    /// Get all available division names
    var availableDivisions: [String] {
        return Array(allDivisionResults.keys).sorted()
    }
    
    /// Check if we have results for a specific division
    /// - Parameter divisionName: Division name to check
    /// - Returns: True if we have results for this division
    func hasResultsForDivision(_ divisionName: String) -> Bool {
        return allDivisionResults[divisionName] != nil && !allDivisionResults[divisionName]!.isEmpty
    }
    
    /// Switch to continuous retrieval for a specific division
    /// - Parameter divisionName: Division to start continuous retrieval for
    func startContinuousRetrievalForDivision(_ divisionName: String) {
        // Find the URL for this division from our stored results
        guard let discoveryResponse = self.discoveryResponse else {
            print("❌ No discovery response stored")
            return
        }
        
        // Find the matching URL info for this division
        for (key, urlInfo) in discoveryResponse.apiUrls {
            let keyDivisionName = getDivisionName(from: key, combinations: discoveryResponse.combinations)
            if keyDivisionName == divisionName {
                startRetrieving(from: urlInfo.url)
                return
            }
        }
        
        print("❌ Could not find URL for division: \(divisionName)")
    }
    
    /// Store discovery response for later reference
    /// - Parameter response: The discovery response to store
    func storeDiscoveryResponse(_ response: APIDiscoveryResponse) {
        self.discoveryResponse = response
    }
}

// MARK: - Enhanced Usage Examples

extension APIRetrievalService {
    
    /// Get statistics about all divisions
    var allDivisionStats: [(name: String, competitorCount: Int)] {
        return allDivisionResults.map { (name, competitors) in
            (name: name, competitorCount: competitors.count)
        }.sorted { $0.name < $1.name }
    }
    
    /// Get the division with the most competitors
    var largestDivision: (name: String, count: Int)? {
        return allDivisionResults.max { $0.value.count < $1.value.count }
            .map { (name: $0.key, count: $0.value.count) }
    }
    
    /// Clear all stored results
    func clearAllResults() {
        allDivisionResults.removeAll()
        currentResults.removeAll()
        discoveryResponse = nil
    }
}
