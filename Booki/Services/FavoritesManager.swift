import Foundation
import SwiftUI
import Combine

/// Manager for storing and retrieving favorite teams using UserDefaults
/// US-039: Add Favorites System
class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()

    private let userDefaultsKey = "favoriteTeams"

    /// Published set of favorite team names
    @Published private(set) var favoriteTeams: Set<String> = []

    private init() {
        loadFavorites()
    }

    /// Check if a team is favorited
    /// - Parameter teamName: The team name to check
    /// - Returns: True if the team is in favorites
    func isFavorite(_ teamName: String) -> Bool {
        favoriteTeams.contains(teamName)
    }

    /// Toggle favorite status for a team
    /// - Parameter teamName: The team name to toggle
    func toggleFavorite(_ teamName: String) {
        if favoriteTeams.contains(teamName) {
            favoriteTeams.remove(teamName)
        } else {
            favoriteTeams.insert(teamName)
        }
        saveFavorites()
    }

    /// Add a team to favorites
    /// - Parameter teamName: The team name to add
    func addFavorite(_ teamName: String) {
        favoriteTeams.insert(teamName)
        saveFavorites()
    }

    /// Remove a team from favorites
    /// - Parameter teamName: The team name to remove
    func removeFavorite(_ teamName: String) {
        favoriteTeams.remove(teamName)
        saveFavorites()
    }

    /// Check if an event has any favorited team
    /// - Parameter event: The event to check
    /// - Returns: True if either home or away team is favorited
    func hasFavoritedTeam(homeTeam: String, awayTeam: String) -> Bool {
        isFavorite(homeTeam) || isFavorite(awayTeam)
    }

    // MARK: - Persistence

    private func loadFavorites() {
        if let savedTeams = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            favoriteTeams = Set(savedTeams)
        }
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteTeams), forKey: userDefaultsKey)
    }
}
