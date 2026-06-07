import Foundation

/// Saved progress for a single day's puzzle.
struct DailyProgress: Codable {
    var guessIds: [String] = []
    var solved: Bool = false
    var gaveUp: Bool = false
    var counted: Bool = false   // whether this result was already folded into Stats
}

/// Lifetime play statistics.
struct Stats: Codable {
    var gamesPlayed = 0
    var gamesWon = 0
    var currentStreak = 0
    var maxStreak = 0
    var lastCountedDay = Int.min
    var lastWasWin = false
    var guessDistribution: [String: Int] = [:]   // guess count -> games solved in that many

    var winPercent: Int {
        gamesPlayed == 0 ? 0 : Int((Double(gamesWon) / Double(gamesPlayed) * 100).rounded())
    }
    var averageGuesses: Double {
        let total = guessDistribution.reduce(0) { $0 + (Int($1.key) ?? 0) * $1.value }
        let games = guessDistribution.values.reduce(0, +)
        return games == 0 ? 0 : Double(total) / Double(games)
    }
}

/// Thin Codable wrapper around UserDefaults.
enum Persistence {
    private static let defaults = UserDefaults.standard

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    static func progressKey(_ dateKey: String) -> String { "globle.progress.\(dateKey)" }
    static let statsKey = "globle.stats"
}
