import Foundation
import SwiftUI

// MARK: - Models
struct UpcomingRegattaResponse: Codable {
    let success: Bool
    let regattas: [UpcomingRegatta]
    let count: Int
    let timestamp: String
    let source: String
}
struct UpcomingRegatta: Codable, Identifiable {
    let objectId: String //used for link to the regatta
    let name: String?
    let clubName: String?
    let clubObjectId: String
    let location: String?
    let city: String?
    let state: String?
    let country: String?
    let zip: String?
    let street: String?
    let startDate: String
    let endDate: String
    let lastChanceDate: String?
    let clubTimezone: String
    let clubBurgeeURL: String?
    let imageURL: String?
    let lastScraped: String
    let ttl: Int
    let createdAt: String
    let updatedAt: String
    
    var id: String { objectId }
    
    var lastChanceDateFormatted: Date? {
        guard let lastChanceDate = lastChanceDate else { return nil }
        return ISO8601DateFormatter().date(from: lastChanceDate)
    }
    
    var startDateFormatted: Date? {
            let iso8601Full = ISO8601DateFormatter()
            iso8601Full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601Full.date(from: startDate) {
                return date
            }
            
            iso8601Full.formatOptions = [.withInternetDateTime]
            return iso8601Full.date(from: startDate)
        }

        var endDateFormatted: Date? {
            let iso8601Full = ISO8601DateFormatter()
            iso8601Full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601Full.date(from: endDate) {
                return date
            }
            
            iso8601Full.formatOptions = [.withInternetDateTime]
            return iso8601Full.date(from: endDate)
        }
        
        var isUpcoming: Bool {
            guard let startDate = startDateFormatted else { return false }
            
            // Compare dates in UTC to avoid timezone issues
            let now = Date()
            let calendar = Calendar.current
            var utcCalendar = calendar
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            
            // Compare just the date components
            let startComponents = utcCalendar.dateComponents([.year, .month, .day], from: startDate)
            let nowComponents = utcCalendar.dateComponents([.year, .month, .day], from: now)
            
            guard let startDateOnly = utcCalendar.date(from: startComponents),
                  let nowDateOnly = utcCalendar.date(from: nowComponents) else {
                return startDate > now
            }
            
            return startDateOnly > nowDateOnly
        }
    
    var isActive: Bool {
        // Must have at least a start date
        guard let startDate = startDateFormatted else { return false }
        
        // Set up UTC calendar for date comparison
        let now = Date()
        let calendar = Calendar.current
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        
        // Get date components
        let startComponents = utcCalendar.dateComponents([.year, .month, .day], from: startDate)
        let nowComponents = utcCalendar.dateComponents([.year, .month, .day], from: now)
        
        guard let startDateOnly = utcCalendar.date(from: startComponents),
              let nowDateOnly = utcCalendar.date(from: nowComponents) else {
            return false
        }
        
        // Case 1: Only start date (no end date)
        if endDateFormatted == nil {
            // Active only on the start date
            return startDateOnly == nowDateOnly
        }
        
        // Case 2: Both start and end dates
        if let endDate = endDateFormatted {
            let endComponents = utcCalendar.dateComponents([.year, .month, .day], from: endDate)
            guard let endDateOnly = utcCalendar.date(from: endComponents) else {
                // If end date parsing fails, treat like case 1
                return startDateOnly == nowDateOnly
            }
            
            // Active if today is between start and end dates (inclusive)
            return nowDateOnly >= startDateOnly && nowDateOnly <= endDateOnly
        }
        
        return false
    }
    
    // Helper computed properties for safe display
    var displayName: String {
        name ?? "Regatta Name TBD"
    }
    
    var displayClubName: String {
        clubName ?? "Club TBD"
    }
    
    var displayLocation: String {
        location ?? "Location TBD"
    }
    
    var displayCity: String {
        city ?? "City TBD"
    }
    
    var displayState: String {
        state ?? "State TBD"
    }
    
    var displayCityState: String {
        let cityState = [city, state].compactMap { $0 }.filter { !$0.isEmpty }
        return cityState.isEmpty ? "Location TBD" : cityState.joined(separator: ", ")
    }
    
    var displayFullLocation: String {
        let parts = [displayClubName, displayCityState].filter { $0 != "Club TBD" && $0 != "Location TBD" }
        return parts.isEmpty ? "Location TBD" : parts.joined(separator: " • ")
    }
}

// MARK: - Service
class RegattaService: ObservableObject {
    @Published var regattas: [UpcomingRegatta] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    
    private let baseURL = "https://twuhf4b83h.execute-api.us-east-2.amazonaws.com/prod/events"
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 3600
    
    private var currentTask: Task<Void, Never>?
    
    init() {
        startPeriodicUpdates()
    }
    
    deinit {
        stopPeriodicUpdates()
    }
    
    // MARK: - Public Methods
    @MainActor
    func fetchRegattas() async {
            // Cancel any existing fetch task
            currentTask?.cancel()
            
            currentTask = Task {
                isLoading = true
                errorMessage = nil
                
                do {
                    // Check for cancellation before proceeding
                    try Task.checkCancellation()
                    
                    guard let url = URL(string: baseURL) else {
                        throw RegattaError.invalidURL
                    }
                    
                    let (data, response) = try await URLSession.shared.data(from: url)
                    
                    // Check for cancellation after network call
                    try Task.checkCancellation()
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw RegattaError.invalidResponse
                    }
                    
                    let regattaResponse = try JSONDecoder().decode(UpcomingRegattaResponse.self, from: data)
                    
                    if regattaResponse.success {
                        let upcomingCount = regattaResponse.regattas.filter { $0.isUpcoming }.count
                        print("🔮 Upcoming regattas: \(upcomingCount)")
                        
                        self.regattas = regattaResponse.regattas
                        self.lastUpdated = Date()
                    } else {
                        throw RegattaError.apiError("API returned success: false")
                    }
                    
                } catch {
                    // Don't set error message if task was cancelled
                    if !Task.isCancelled {
                        self.errorMessage = error.localizedDescription
                        print("Error fetching regattas: \(error)")
                    }
                }
                
                isLoading = false
            }
            
            await currentTask?.value
        }
    
    func refreshRegattas() async {
        await fetchRegattas()
    }
    
    // MARK: - Filtering Methods
    func upcomingRegattas() -> [UpcomingRegatta] {
        return regattas
    }
    
    func regattasByLocation(containing searchText: String) -> [UpcomingRegatta] {
        guard !searchText.isEmpty else { return regattas }
        return regattas.filter {
            ($0.location?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.city?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.state?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.clubName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.name?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    // MARK: - Timer Management
    private func startPeriodicUpdates() {
        // Initial fetch
        Task {
            await fetchRegattas()
        }
        
        // Set up timer for periodic updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchRegattas()
            }
        }
    }
    
    private func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // Force immediate update (useful for pull-to-refresh)
    func forceUpdate() async {
        await fetchRegattas()
    }
}

// MARK: - Error Handling
enum RegattaError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let message):
            return "API Error: \(message)"
        }
    }
}
