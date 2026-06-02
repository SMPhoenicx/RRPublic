import Foundation
import SocketIO
import Combine

class RegattaSocketManager: ObservableObject {
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var currentSessionId: String?
    private var hasJoinedSession = false
    private var shouldRejoin = false
    private var isLiveSession = false // Track if this is a live session
    private var reconnectAttempts = 0
    private var maxReconnectAttempts = 3
    private var isIntentionallyDisconnecting = false
    
    @Published var currentRegattaData: RegattaResponse?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var error: String?
    @Published var eventInfo: EventInfo?
    @Published var isLoadingEventInfo: Bool = false
    @Published var isLoadingResults: Bool = false
    @Published var canGetResults: Bool = false
    @Published var discoveryResult: APIDiscoveryResponse?
    @Published var originalURL: String?
    @Published var regattaNetworkData: RegattaNetworkResponse?
    @Published var isLoadingRegattaNetwork: Bool = false
    @Published var processedRegattaNetworkData: [String: [ProcessedNetworkCompetitor]]?
    
    enum ConnectionStatus: Equatable {
        case connected
        case disconnected
        case connecting
        case error(String)
        
        static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
            switch (lhs, rhs) {
            case (.connected, .connected),
                 (.disconnected, .disconnected),
                 (.connecting, .connecting):
                return true
            case let (.error(lhsMsg), .error(rhsMsg)):
                return lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }
    
    func getSocket() -> SocketIOClient? {
        return socket
    }
    
    init() {
        setupSocket()
    }
    
    // Set up with SSL
    private func setupSocket() {
        let serverURL = "https://app.regatta-results.com"
        guard let url = URL(string: serverURL) else {
            self.error = "Invalid server URL"
            print("[SocketManager] Invalid server URL: \(serverURL)")
            return
        }
        
        manager = SocketManager(socketURL: url, config: [
            .log(true),
            .compress,
            .forceWebsockets(true),
            .reconnects(true),
            .reconnectAttempts(3),
            .reconnectWait(5),
            .extraHeaders([
                "Origin": "https://app.regatta-results.com",
                "User-Agent": "RegattaApp/1.0"
            ]),
            .path("/socket.io"),
            .secure(true),
            .selfSigned(false)
        ])
        socket = manager?.defaultSocket
        setupEventHandlers()
    }
    
    private func enableReconnection() {
        guard let manager = manager else { return }
        manager.reconnects = true
        print("[SocketManager] Reconnection enabled")
    }
    
    private func enableUnlimitedReconnection() {
        guard manager != nil else { return }
        
        // Disconnect current connection first
        socket?.disconnect()
        
        // Create new manager with unlimited reconnection
        let serverURL = "https://app.regatta-results.com"
        guard let url = URL(string: serverURL) else { return }
        
        self.manager = SocketManager(socketURL: url, config: [
            .log(true),
            .compress,
            .forceWebsockets(true),
            .reconnects(true),
            .reconnectAttempts(-1),
            .reconnectWait(5),
            .extraHeaders(["Origin": "https://app.regatta-results.com"]),
            .path("/socket.io")
        ])
        
        socket = self.manager?.defaultSocket
        setupEventHandlers()
        
        // FIX: Actually connect the new socket
        socket?.connect()
        
        print("[SocketManager] Unlimited reconnection enabled for live session")
    }
    
    private func disableReconnection() {
        guard let manager = manager else { return }
        
        manager.reconnects = false
        reconnectAttempts = 0
        
        print("[SocketManager] Reconnection disabled")
    }
    
    private func setupEventHandlers() {
        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            print("🔌 Socket connected!")
            DispatchQueue.main.async {
                self?.connectionStatus = .connected
                self?.error = nil
                self?.reconnectAttempts = 0 // Reset on successful connection
                
                if let sessionId = self?.currentSessionId {
                    if self?.hasJoinedSession == true && self?.shouldRejoin == true {
                        print("🔄 Rejoining session: \(sessionId)")
                        self?.socket?.emit("join_session", ["session_id": sessionId])
                    }
                }
            }
        }
        
        socket?.on(clientEvent: .error) { [weak self] data, _ in
            // Don't process errors during intentional disconnection
            guard let self = self, !self.isIntentionallyDisconnecting else { return }
            
            let errorMessage: String
            if let dataArray = data as? [[String: Any]],
               let firstData = dataArray.first,
               let message = firstData["message"] as? String {
                errorMessage = message
            } else if let message = data.first as? String {
                errorMessage = message
            } else {
                errorMessage = "Unknown error occurred"
            }
            print("[SocketManager] ❌ Socket error: \(errorMessage) | Data: \(data)")
            DispatchQueue.main.async {
                self.connectionStatus = .error(errorMessage)
                self.error = errorMessage
            }
        }

        socket?.on(clientEvent: .disconnect) { [weak self] data, _ in
            guard let self = self, !self.isIntentionallyDisconnecting else { return }
            
            print("[SocketManager] ⚡️ Socket disconnected! Data: \(data)")
            DispatchQueue.main.async {
                self.connectionStatus = .disconnected
                
                // For one-time operations, don't attempt to reconnect
                if self.isLiveSession == false {
                    print("[SocketManager] One-time operation completed - not reconnecting")
                    self.disableReconnection()
                }
            }
        }
        
        socket?.on(clientEvent: .reconnectAttempt) { [weak self] data, _ in
            guard let self = self else { return }
            
            self.reconnectAttempts += 1
            print("[SocketManager] 🔁 Reconnect attempt #\(self.reconnectAttempts): \(data)")
            
            // For non-live sessions, limit reconnection attempts
            if !self.isLiveSession && self.reconnectAttempts >= self.maxReconnectAttempts {
                print("[SocketManager] Max reconnection attempts reached for one-time operation")
                DispatchQueue.main.async {
                    self.disableReconnection()
                    self.connectionStatus = .error("Connection failed after \(self.maxReconnectAttempts) attempts")
                }
                return
            }
        }
        
        socket?.on(clientEvent: .ping) { _, _ in
            print("[SocketManager] 🏓 Ping sent to server.")
        }
        
        socket?.on(clientEvent: .pong) { _, _ in
            print("[SocketManager] 🏓 Pong received from server.")
        }
        
        socket?.on(clientEvent: .statusChange) { data, _ in
            print("[SocketManager] Status changed: \(data)")
        }
        
        socket?.on(clientEvent: .reconnect) { _, _ in
            print("[SocketManager] 🔁 Attempting to reconnect...")
        }
        
        socket?.on(clientEvent: .websocketUpgrade) { _, _ in
            print("[SocketManager] 🚀 Websocket upgrade successful.")
        }
        
        socket?.on("joined_session") { [weak self] data, _ in
            print("[SocketManager] ✅ Successfully joined session. Data: \(data)")
            guard let self = self,
                  let url = self.originalURL else {
                print("[SocketManager] ❌ No pending URL to scrape")
                return
            }
        }
        
        socket?.on("scraper_update") { [weak self] data, _ in
            print("[SocketManager] 📊 Received scraper update raw data: \(data)")
            DispatchQueue.main.async {
                self?.isLoadingResults = false
            }
            let dataArray = data as [Any]
            guard let responseData = dataArray.first as? [String: Any] else {
                print("[SocketManager] ❌ Failed to parse data array")
                DispatchQueue.main.async {
                    self?.error = "Invalid data format received"
                }
                return
            }
            print("[SocketManager] 📝 Processing response data: \(responseData)")
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: responseData)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "invalid JSON"
                print("[SocketManager] 🔄 Attempting to decode JSON: \(jsonString)")
                let decoder = JSONDecoder()
                let response = try decoder.decode(RegattaResponse.self, from: jsonData)
                DispatchQueue.main.async {
                    print("[SocketManager] 🔄 Updating UI with new regatta data")
                    self?.currentRegattaData = response
                    self?.error = nil
                }
            } catch {
                print("[SocketManager] ❌ Decoding error: \(error)")
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        print("[SocketManager] ❌ Missing key: \(key.stringValue) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .typeMismatch(let type, let context):
                        print("[SocketManager] ❌ Type mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                        print("[SocketManager] ❌ Debug: \(context.debugDescription)")
                    case .valueNotFound(let type, let context):
                        print("[SocketManager] ❌ Value not found: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .dataCorrupted(let context):
                        print("[SocketManager] ❌ Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                        print("[SocketManager] ❌ Debug: \(context.debugDescription)")
                    @unknown default:
                        print("[SocketManager] ❌ Unknown decoding error: \(decodingError)")
                    }
                }
                DispatchQueue.main.async {
                    self?.error = "Failed to decode regatta data: \(error.localizedDescription)"
                }
            }
        }
        
        socket?.on("scraper_error") { [weak self] data, _ in
            guard let errorData = data.first as? [String: Any],
                  let errorMessage = errorData["error"] as? String else { return }
            print("[SocketManager] ❌ Received scraper error: \(errorMessage)")
            DispatchQueue.main.async {
                self?.error = errorMessage
            }
        }
        
        socket?.on("event_info") { [weak self] data, ack in
            guard let eventData = data.first as? [String: Any],
                  let eventInfoDict = eventData["event_data"] as? [String: Any],
                  let eventInfo = eventInfoDict["event_info"] as? [String: Any] else {
                print("[SocketManager] ❌ Invalid event info data")
                return
            }
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: eventInfo)
                let decodedEventInfo = try JSONDecoder().decode(EventInfo.self, from: jsonData)
                DispatchQueue.main.async {
                    self?.eventInfo = decodedEventInfo
                    self?.isLoadingEventInfo = false
                    self?.canGetResults = decodedEventInfo.resultsUrl != nil
                    print("[SocketManager] ✅ Event info received: \(decodedEventInfo.title ?? "Unknown")")
                    
                    // For one-time operations, disconnect after receiving data
                    if self?.isLiveSession == false {
                        print("[SocketManager] One-time operation completed - disconnecting")
                        self?.socket?.disconnect()
                    }
                }
            } catch {
                print("[SocketManager] ❌ Failed to decode event info: \(error)")
                DispatchQueue.main.async {
                    self?.error = "Failed to parse event information"
                    self?.isLoadingEventInfo = false
                }
            }
        }
        
        socket?.on("main_scraper_error") { [weak self] data, ack in
            guard let errorData = data.first as? [String: Any],
                  let errorMessage = errorData["error"] as? String else {
                return
            }
            print("[SocketManager] ❌ Main scraper error: \(errorMessage)")
            DispatchQueue.main.async {
                self?.error = errorMessage
                self?.isLoadingEventInfo = false
            }
        }
        
        socket?.on("regatta_network_update") { [weak self] data, _ in
            print("[SocketManager] 📊 Received regatta network update raw data: \(data)")
            DispatchQueue.main.async {
                self?.isLoadingRegattaNetwork = false
            }
            
            let dataArray = data as [Any]
            guard let responseData = dataArray.first as? [String: Any] else {
                print("[SocketManager] ❌ Failed to parse regatta network data array")
                DispatchQueue.main.async {
                    self?.error = "Invalid regatta network data format received"
                }
                return
            }
            
            print("[SocketManager] 📝 Processing regatta network response data: \(responseData)")
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: responseData)
                let decoder = JSONDecoder()
                let response = try decoder.decode(RegattaNetworkResponse.self, from: jsonData)
                
                // Process the data to ProcessedNetworkCompetitor format
                let processedData = self?.processRegattaNetworkData(response)
                
                DispatchQueue.main.async {
                    print("[SocketManager] 🔄 Updating UI with processed regatta network data")
                    self?.regattaNetworkData = response
                    self?.processedRegattaNetworkData = processedData
                    self?.error = nil
                }
            } catch {
                print("[SocketManager] ❌ Regatta Network decoding error: \(error)")
                DispatchQueue.main.async {
                    self?.error = "Failed to decode regatta network data: \(error.localizedDescription)"
                }
            }
        }

        socket?.on("regatta_network_error") { [weak self] data, _ in
            guard let errorData = data.first as? [String: Any],
                  let errorMessage = errorData["error"] as? String else { return }
            print("[SocketManager] ❌ Received regatta network error: \(errorMessage)")
            DispatchQueue.main.async {
                self?.error = errorMessage
                self?.isLoadingRegattaNetwork = false
            }
        }
    }
    
    func connect(withSessionId sessionId: String) {
        print("🔌 Connecting with session ID: \(sessionId)")
        currentSessionId = sessionId
        connectionStatus = .connecting
        socket?.connect()
    }
    
    private func createSession(url: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let serverURL = URL(string: "https://app.regatta-results.com/start") else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])))
            return
        }
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["url": url]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = json["session_id"] as? String else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])))
                }
                return
            }
            DispatchQueue.main.async {
                self?.currentSessionId = sessionId
                completion(.success(sessionId))
            }
        }.resume()
    }
    
    func startScraping(url: String) {
        print("📝 Creating session for URL: \(url)")
        originalURL = url
        isLoadingEventInfo = true
        canGetResults = false
        shouldRejoin = false
        isLiveSession = false // One-time operation
        
        // One-time operations use the default limited reconnection (3 attempts)
        
        createSession(url: url) { [weak self] result in
            switch result {
            case .success(let sessionId):
                print("✅ Session created: \(sessionId)")
                self?.currentSessionId = sessionId
                self?.socket?.emit("join_session", ["session_id": sessionId])
                self?.hasJoinedSession = true

            case .failure(let error):
                print("❌ Failed to create session: \(error)")
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                    self?.isLoadingEventInfo = false
                }
            }
        }
    }
    
    func refreshData() {
        if let url = originalURL {
            scrapeEventInfoHTTP(url: url)
        }
        else {
            print("No URL present")
        }
    }
    
    func scrapeEventInfoHTTP(url: String) {
        // HTTP request - no socket connection needed
        isLoadingEventInfo = true
        canGetResults = false
        error = nil
        originalURL = url
        guard !url.isEmpty, URL(string: url) != nil else {
            print("❌ Invalid or empty URL provided")
            self.error = "Invalid URL provided"
            self.isLoadingEventInfo = false
            return
        }
        
        guard let endpoint = URL(string: "https://app.regatta-results.com/scrape-event-info") else {
            self.error = "Invalid server URL"
            self.isLoadingEventInfo = false
            return
        }
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["url": url]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoadingEventInfo = false
                
                if let error = error {
                    print("❌ HTTP request failed: \(error)")
                    self?.error = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    print("❌ No data received")
                    self?.error = "No data received from server"
                    return
                }
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    
                    if let status = json?["status"] as? String, status == "success",
                       let eventData = json?["event_data"] as? [String: Any],
                       let eventInfo = eventData["event_info"] as? [String: Any] {
                        
                        // Parse the event info
                        let jsonEventData = try JSONSerialization.data(withJSONObject: eventInfo)
                        let decodedEventInfo = try JSONDecoder().decode(EventInfo.self, from: jsonEventData)
                        
                        self?.eventInfo = decodedEventInfo
                        self?.canGetResults = decodedEventInfo.resultsUrl != nil
                        self?.error = nil
                        
                        print("✅ Event info received via HTTP: \(decodedEventInfo.title ?? "Unknown")")
                        
                    } else if let errorMessage = json?["error"] as? String {
                        print("❌ Clubspot Server error: \(errorMessage)")
                        self?.error = errorMessage
                    } else {
                        print("❌ Invalid response format")
                        self?.error = "Invalid response format"
                    }
                    
                } catch {
                    print("❌ JSON parsing error: \(error)")
                    self?.error = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func startResultsScraping() {
        guard let resultsUrl = eventInfo?.resultsUrl else {
            error = "No results URL available"
            return
        }
        
        print("📊 Starting results scraping for URL: \(resultsUrl)")
        isLoadingResults = true
        shouldRejoin = true
        isLiveSession = true // Live session - needs continuous reconnection
        
        // For live sessions, enable unlimited reconnection
        enableUnlimitedReconnection()
        
        guard let serverURL = URL(string: "https://app.regatta-results.com/start-results") else {
            error = "Invalid server URL"
            isLoadingResults = false
            return
        }
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["results_url": resultsUrl]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                    self?.isLoadingResults = false
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = json["session_id"] as? String else {
                DispatchQueue.main.async {
                    self?.error = "Invalid response from server"
                    self?.isLoadingResults = false
                }
                return
            }
            
            DispatchQueue.main.async {
                // Join the new results session
                self?.socket?.emit("join_session", ["session_id": sessionId])
                print("✅ Results scraping started: \(sessionId)")
                self?.currentSessionId = sessionId
                self?.hasJoinedSession = true
            }
        }.resume()
    }
    
    @MainActor
    func discoverAPIs(for url: String) async throws {
        isLoadingResults = true
        shouldRejoin = false
        isLiveSession = false // One-time operation
        
        guard let endpoint = URL(string: "https://app.regatta-results.com/discover-only") else {
            isLoadingResults = false
            throw APISecondError.invalidURL
        }
        
        let requestBody = ["url": url]
        let jsonData = try JSONEncoder().encode(requestBody)
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APISecondError.serverError
        }
        
        discoveryResult = try JSONDecoder().decode(APIDiscoveryResponse.self, from: data)
    }
    
    func disconnect() {
        isIntentionallyDisconnecting = true
        
        if let sessionId = currentSessionId {
            socket?.emit("leave_session", ["session_id": sessionId])
        }
        
        disableReconnection()
        socket?.disconnect()
        socket?.removeAllHandlers()
        
        currentSessionId = nil
        originalURL = nil
        eventInfo = nil
        currentRegattaData = nil
        discoveryResult = nil
        regattaNetworkData = nil
        processedRegattaNetworkData = nil
        isLoadingEventInfo = false
        isLoadingResults = false
        isLoadingRegattaNetwork = false
        canGetResults = false
        hasJoinedSession = false
        shouldRejoin = false
        isLiveSession = false
        reconnectAttempts = 0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.connectionStatus = .disconnected
            self.isIntentionallyDisconnecting = false
        }
    }
    
    deinit {
        socket?.disconnect()
    }
    
    func saveState() {
        let state = SocketState(
            currentSessionId: currentSessionId,
            hasJoinedSession: hasJoinedSession,
            shouldRejoin: shouldRejoin,
            currentRegattaData: currentRegattaData,
            eventInfo: eventInfo,
            canGetResults: canGetResults,
            discoveryResult: discoveryResult,
            originalURL: originalURL,
            isLiveSession: isLiveSession,
            regattaNetworkData: regattaNetworkData,
            isLoadingRegattaNetwork: isLoadingRegattaNetwork,
            processedRegattaNetworkData: processedRegattaNetworkData
        )
        
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: "socketState")
        }
    }

    func loadState() {
        guard let data = UserDefaults.standard.data(forKey: "socketState"),
              let state = try? JSONDecoder().decode(SocketState.self, from: data) else {
            return
        }
        
        currentSessionId = state.currentSessionId
        hasJoinedSession = state.hasJoinedSession
        shouldRejoin = state.shouldRejoin
        currentRegattaData = state.currentRegattaData
        eventInfo = state.eventInfo
        canGetResults = state.canGetResults
        discoveryResult = state.discoveryResult
        originalURL = state.originalURL
        isLiveSession = state.isLiveSession
        regattaNetworkData = state.regattaNetworkData
        isLoadingRegattaNetwork = state.isLoadingRegattaNetwork
        processedRegattaNetworkData = state.processedRegattaNetworkData
    }
    
    func clearState() {
        
        UserDefaults.standard.removeObject(forKey: "socketState")
        UserDefaults.standard.synchronize()
        
        error = nil
        currentSessionId = nil
        originalURL = nil
        hasJoinedSession = false
        shouldRejoin = false
        isLiveSession = false
    }
}

// In the SocketState struct, add this property:
struct SocketState: Codable {
    let currentSessionId: String?
    let hasJoinedSession: Bool
    let shouldRejoin: Bool
    
    let currentRegattaData: RegattaResponse?
    let eventInfo: EventInfo?
    let canGetResults: Bool
    let discoveryResult: APIDiscoveryResponse?
    let originalURL: String?
    let isLiveSession: Bool
    
    let regattaNetworkData: RegattaNetworkResponse?
    let isLoadingRegattaNetwork: Bool
    let processedRegattaNetworkData: [String: [ProcessedNetworkCompetitor]]?
}

// MARK: - Regatta Network Functions
extension RegattaSocketManager {
    
    // MARK: - Single Scrape (HTTP)
    func scrapeRegattaNetworkHTTP(url: String) {
        // HTTP request - no socket connection needed
        isLoadingRegattaNetwork = true
        error = nil
        originalURL = url
        
        guard let endpoint = URL(string: "https://app.regatta-results.com/scrape-regatta-network") else {
            self.error = "Invalid server URL"
            self.isLoadingRegattaNetwork = false
            return
        }
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["url": url]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoadingRegattaNetwork = false
                
                if let error = error {
                    print("❌ HTTP request failed: \(error)")
                    self?.error = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    print("❌ No data received")
                    self?.error = "No data received from server"
                    return
                }
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    
                    // In the scrapeRegattaNetworkHTTP function, replace the success case with:
                    if let status = json?["status"] as? String, status == "success",
                       let regattaData = json?["regatta_data"] as? [String: Any] {
                        
                        // Parse the regatta network data
                        let jsonRegattaData = try JSONSerialization.data(withJSONObject: regattaData)
                        let decodedRegattaData = try JSONDecoder().decode(RegattaNetworkResponse.self, from: jsonRegattaData)
                        
                        // Process the data to ProcessedNetworkCompetitor format
                        let processedData = self?.processRegattaNetworkData(decodedRegattaData)
                        
                        self?.regattaNetworkData = decodedRegattaData  // Keep original
                        self?.processedRegattaNetworkData = processedData  // Add processed
                        self?.error = nil
                        
                        
                    } else if let errorMessage = json?["error"] as? String {
                        print("❌ Server error: \(errorMessage)")
                        self?.error = errorMessage
                    } else {
                        print("❌ Invalid response format")
                        self?.error = "Invalid response format"
                    }
                    
                } catch {
                    print("❌ JSON parsing error: \(error)")
                    self?.error = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    // MARK: - Live Scraping (WebSocket)
    func startRegattaNetworkLiveScraping(url: String) {
        print("📊 Starting Regatta Network live scraping for URL: \(url)")
        isLoadingRegattaNetwork = true
        shouldRejoin = true
        isLiveSession = true
        originalURL = url
        
        // Enable unlimited reconnection for live sessions
        enableUnlimitedReconnection()
        
        // Wait a moment for socket to initialize, then proceed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.createRegattaNetworkSession(url: url)
        }
    }

    private func createRegattaNetworkSession(url: String) {
        guard let serverURL = URL(string: "https://app.regatta-results.com/start") else {
            error = "Invalid server URL"
            isLoadingRegattaNetwork = false
            return
        }
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "url": url,
            "scraper_type": "regatta_network",
            "run_once": false
        ] as [String: Any]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                    self?.isLoadingRegattaNetwork = false
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = json["session_id"] as? String else {
                DispatchQueue.main.async {
                    self?.error = "Invalid response from server"
                    self?.isLoadingRegattaNetwork = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self?.currentSessionId = sessionId
                self?.hasJoinedSession = true
                
                // Only emit join_session after we have a connected socket
                if self?.socket?.status == .connected {
                    self?.socket?.emit("join_session", ["session_id": sessionId])
                    print("✅ Regatta Network live scraping started: \(sessionId)")
                } else {
                    // Wait for connection then join
                    self?.socket?.once(clientEvent: .connect) { _, _ in
                        self?.socket?.emit("join_session", ["session_id": sessionId])
                        print("✅ Regatta Network live scraping started: \(sessionId)")
                    }
                }
            }
        }.resume()
    }
    
    private func processRegattaNetworkData(_ response: RegattaNetworkResponse) -> [String: [ProcessedNetworkCompetitor]] {
        var processedDivisions: [String: [ProcessedNetworkCompetitor]] = [:]
        
        for division in response.divisions {
            let processedCompetitors = division.results.map { result in
                ProcessedNetworkCompetitor(from: result)
            }
            processedDivisions[division.name] = processedCompetitors
        }
        
        return processedDivisions
    }
    
    // MARK: - Stop Regatta Network Scraping
    func stopRegattaNetworkScraping() {
        guard let sessionId = currentSessionId else {
            print("❌ No active session to stop")
            return
        }
        
        print("🛑 Stopping Regatta Network scraping for session: \(sessionId)")
        
        guard let stopURL = URL(string: "https://app.regatta-results.com/stop") else {
            error = "Invalid server URL"
            return
        }
        
        var request = URLRequest(url: stopURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        let body = ["session_id": sessionId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error stopping scraping: \(error)")
                    self?.error = error.localizedDescription
                } else {
                    print("✅ Successfully stopped Regatta Network scraping")
                    self?.disconnect() // Clean disconnect
                }
            }
        }.resume()
    }
    
    // MARK: - Refresh Regatta Network Data
    func refreshRegattaNetworkData() {
        if let url = originalURL {
            scrapeRegattaNetworkHTTP(url: url)
        } else {
            print("❌ No URL present for refresh")
            error = "No URL available to refresh"
        }
    }
    
    // MARK: - Clear Regatta Network Data
    func clearRegattaNetworkData() {
        regattaNetworkData = nil
        isLoadingRegattaNetwork = false
        // Don't clear error or originalURL as they might be used by other functions
    }
}
