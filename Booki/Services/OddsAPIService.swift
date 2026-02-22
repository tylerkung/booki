import Foundation
import SwiftUI

// MARK: - US-001, US-003, US-004, US-008, US-012: Odds API Service

/// Errors that can occur when communicating with The Odds API
enum OddsAPIError: Error, LocalizedError, @unchecked Sendable {
    case invalidAPIKey
    case rateLimitExceeded
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)
    case noAPIKey
    case quotaExhausted

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key. Please check your settings."
        case .rateLimitExceeded:
            return "API rate limit exceeded. Please try again later."
        case .serverError(let code):
            return "Server error (code \(code)). Please try again later."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .noAPIKey:
            return "No API key configured. Please add your API key in Settings."
        case .quotaExhausted:
            return "API quota exhausted. Your quota resets monthly."
        }
    }
}

/// Service for communicating with The Odds API
@MainActor
@Observable
final class OddsAPIService {

    // MARK: - Constants

    private static let baseURL = "https://api.the-odds-api.com"

    // MARK: - Published Properties (US-012: Quota Tracking)

    var quotaRemaining: Int?
    var quotaUsed: Int?

    // MARK: - Stored Settings (use functions to avoid @Observable synthesis conflicts)

    private func getAPIKey() -> String {
        UserDefaults.standard.string(forKey: "oddsAPIKey") ?? ""
    }
    private func setAPIKey(_ value: String) {
        UserDefaults.standard.set(value, forKey: "oddsAPIKey")
    }
    private func getPreferredBookmaker() -> String {
        UserDefaults.standard.string(forKey: "oddsAPIBookmaker") ?? "draftkings"
    }
    private func setPreferredBookmaker(_ value: String) {
        UserDefaults.standard.set(value, forKey: "oddsAPIBookmaker")
    }
    private func getStoredQuotaRemaining() -> Int {
        UserDefaults.standard.object(forKey: "oddsAPIQuotaRemaining") == nil ? -1 : UserDefaults.standard.integer(forKey: "oddsAPIQuotaRemaining")
    }
    private func setStoredQuotaRemaining(_ value: Int) {
        UserDefaults.standard.set(value, forKey: "oddsAPIQuotaRemaining")
    }
    private func getStoredQuotaUsed() -> Int {
        UserDefaults.standard.object(forKey: "oddsAPIQuotaUsed") == nil ? -1 : UserDefaults.standard.integer(forKey: "oddsAPIQuotaUsed")
    }
    private func setStoredQuotaUsed(_ value: Int) {
        UserDefaults.standard.set(value, forKey: "oddsAPIQuotaUsed")
    }

    // MARK: - Sport Availability Cache (US-002)

    private var cachedActiveSportKeys: Set<String>?
    private var sportCacheTimestamp: Date?
    private static let sportCacheDuration: TimeInterval = 3600 // 1 hour

    // MARK: - Singleton

    static let shared = OddsAPIService()

    private init() {
        // Load persisted quota values
        let remaining = getStoredQuotaRemaining()
        if remaining >= 0 {
            quotaRemaining = remaining
        }
        let used = getStoredQuotaUsed()
        if used >= 0 {
            quotaUsed = used
        }
    }

    // MARK: - Configuration

    var hasAPIKey: Bool {
        !getAPIKey().isEmpty
    }

    var currentBookmaker: String {
        getPreferredBookmaker()
    }

    func updateAPIKey(_ key: String) {
        setAPIKey(key)
    }

    func updateBookmaker(_ bookmaker: String) {
        setPreferredBookmaker(bookmaker)
    }

    // MARK: - US-003: Fetch Available Sports

    /// Fetches the list of available sports from the API
    /// This endpoint is free and doesn't count against quota
    func fetchSports() async throws -> [OddsSport] {
        guard hasAPIKey else {
            throw OddsAPIError.noAPIKey
        }

        let url = URL(string: "\(Self.baseURL)/v4/sports/?apiKey=\(getAPIKey())")!
        let (data, response) = try await performRequest(url: url)

        // Parse quota headers (even though this endpoint is free)
        parseQuotaHeaders(response: response)

        do {
            let decoder = JSONDecoder()
            let sports = try decoder.decode([OddsSport].self, from: data)
            // Filter to only active sports
            return sports.filter { $0.active }
        } catch {
            throw OddsAPIError.decodingError(error)
        }
    }

    // MARK: - US-002: Fetch Active Sport Keys (Cached)

    /// Returns the set of sport keys that currently have upcoming/live events.
    /// Uses the free /v4/sports endpoint and caches results for 1 hour.
    func fetchActiveSportKeys() async throws -> Set<String> {
        // Return cached value if still valid
        if let cached = cachedActiveSportKeys,
           let timestamp = sportCacheTimestamp,
           Date().timeIntervalSince(timestamp) < Self.sportCacheDuration {
            return cached
        }

        let activeSports = try await fetchSports()
        let keys = Set(activeSports.map { $0.key })

        cachedActiveSportKeys = keys
        sportCacheTimestamp = Date()

        return keys
    }

    // MARK: - US-004: Fetch Events with Odds

    /// Fetches upcoming events with betting odds for a specific sport
    /// - Parameter sport: The sport key (e.g., "basketball_nba")
    /// - Returns: Array of events with odds from the preferred bookmaker
    func fetchOdds(sport: String) async throws -> [OddsEvent] {
        guard hasAPIKey else {
            throw OddsAPIError.noAPIKey
        }

        // Check if quota is exhausted
        if let remaining = quotaRemaining, remaining <= 0 {
            throw OddsAPIError.quotaExhausted
        }

        var components = URLComponents(string: "\(Self.baseURL)/v4/sports/\(sport)/odds/")!
        components.queryItems = [
            URLQueryItem(name: "apiKey", value: getAPIKey()),
            URLQueryItem(name: "regions", value: "us"),
            URLQueryItem(name: "markets", value: "h2h,spreads,totals,alternate_spreads,alternate_totals"),
            URLQueryItem(name: "oddsFormat", value: "american")
        ]

        let (data, response) = try await performRequest(url: components.url!)
        parseQuotaHeaders(response: response)

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([OddsEvent].self, from: data)
        } catch {
            throw OddsAPIError.decodingError(error)
        }
    }

    // MARK: - US-008: Fetch Scores

    /// Fetches scores for completed games
    /// - Parameters:
    ///   - sport: The sport key (e.g., "basketball_nba")
    ///   - daysFrom: Number of days back to fetch scores (1-3)
    /// - Returns: Array of completed game scores
    func fetchScores(sport: String, daysFrom: Int = 1) async throws -> [OddsScore] {
        guard hasAPIKey else {
            throw OddsAPIError.noAPIKey
        }

        // Check if quota is exhausted
        if let remaining = quotaRemaining, remaining <= 0 {
            throw OddsAPIError.quotaExhausted
        }

        let clampedDays = min(max(daysFrom, 1), 3)

        var components = URLComponents(string: "\(Self.baseURL)/v4/sports/\(sport)/scores/")!
        components.queryItems = [
            URLQueryItem(name: "apiKey", value: getAPIKey()),
            URLQueryItem(name: "daysFrom", value: String(clampedDays))
        ]

        let (data, response) = try await performRequest(url: components.url!)
        parseQuotaHeaders(response: response)

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let scores = try decoder.decode([OddsScore].self, from: data)
            // Filter to only completed games
            return scores.filter { $0.completed }
        } catch {
            throw OddsAPIError.decodingError(error)
        }
    }

    // MARK: - Private Methods

    private func performRequest(url: URL) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OddsAPIError.networkError(NSError(domain: "OddsAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
            }

            // Handle HTTP errors
            switch httpResponse.statusCode {
            case 200:
                return (data, httpResponse)
            case 401:
                throw OddsAPIError.invalidAPIKey
            case 429:
                throw OddsAPIError.rateLimitExceeded
            case 500...599:
                throw OddsAPIError.serverError(httpResponse.statusCode)
            default:
                throw OddsAPIError.serverError(httpResponse.statusCode)
            }
        } catch let error as OddsAPIError {
            throw error
        } catch {
            throw OddsAPIError.networkError(error)
        }
    }

    // MARK: - US-012: Quota Tracking

    private func parseQuotaHeaders(response: HTTPURLResponse) {
        if let remainingString = response.value(forHTTPHeaderField: "x-requests-remaining"),
           let remaining = Int(remainingString) {
            quotaRemaining = remaining
            setStoredQuotaRemaining(remaining)
        }

        if let usedString = response.value(forHTTPHeaderField: "x-requests-used"),
           let used = Int(usedString) {
            quotaUsed = used
            setStoredQuotaUsed(used)
        }
    }
}
