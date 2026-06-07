import Foundation
import SwiftUI
import UIKit

/// The brain of the game: owns today's mystery country, the player's guesses,
/// win/give-up state, persistence and lifetime stats.
@MainActor
final class GameState: ObservableObject {
    @Published private(set) var guesses: [Country] = []
    @Published private(set) var solved = false
    @Published private(set) var gaveUp = false
    @Published private(set) var stats: Stats
    /// Set briefly after each guess so the globe knows to spin to it; cleared by the view.
    @Published var focus: Country?

    let store: CountryStore
    let target: Country
    let dateKey: String
    private let engine: ProximityEngine

    var isOver: Bool { solved || gaveUp }
    var guessedIds: Set<String> { Set(guesses.map(\.id)) }

    init(store: CountryStore = .shared, date: Date = Date()) {
        self.store = store
        self.dateKey = DailyPuzzle.dateKey(for: date)
        // Fall back to the first country only if data is somehow empty (shouldn't happen).
        self.target = DailyPuzzle.target(from: store.targets, on: date)
            ?? store.all.first!
        self.engine = ProximityEngine(target: target)
        self.stats = Persistence.load(Stats.self, key: Persistence.statsKey) ?? Stats()

        if let saved = Persistence.load(DailyProgress.self, key: Persistence.progressKey(dateKey)) {
            self.guesses = saved.guessIds.compactMap { store.country(id: $0) }
            self.solved = saved.solved
            self.gaveUp = saved.gaveUp
        }
    }

    // MARK: - Distances & colors (cached via the engine)

    func distanceKm(to country: Country) -> Double { engine.distanceKm(to: country) }
    func color(for country: Country) -> Color { Color(uiColor: Warmth.color(forDistanceKm: distanceKm(to: country))) }
    func warmth(for country: Country) -> (text: String, emoji: String) { Warmth.label(forDistanceKm: distanceKm(to: country)) }

    /// Guesses sorted hottest-first, the way Globle ranks them.
    var rankedGuesses: [Country] {
        guesses.sorted { distanceKm(to: $0) < distanceKm(to: $1) }
    }

    /// The closest guess so far (nil before the first guess).
    var closestGuess: Country? { rankedGuesses.first }

    // MARK: - Playing

    @discardableResult
    func makeGuess(_ country: Country) -> Bool {
        guard !isOver, !guessedIds.contains(country.id) else { return false }
        guesses.append(country)
        focus = country
        if country.id == target.id {
            solved = true
            recordResult(won: true)
        }
        saveProgress()
        return true
    }

    func giveUp() {
        guard !isOver else { return }
        gaveUp = true
        recordResult(won: false)
        focus = target
        saveProgress()
    }

    /// A gentle hint becomes available after several guesses.
    var hintAvailable: Bool { guesses.count >= 6 && !isOver }
    var hintText: String {
        let first = target.name.first.map(String.init)?.uppercased() ?? "?"
        let continent = target.continent.isEmpty ? "somewhere on Earth" : target.continent
        return "It starts with “\(first)” and is in \(continent)."
    }

    // MARK: - Persistence

    private func saveProgress() {
        let already = Persistence.load(DailyProgress.self, key: Persistence.progressKey(dateKey))?.counted ?? false
        let progress = DailyProgress(guessIds: guesses.map(\.id), solved: solved,
                                     gaveUp: gaveUp, counted: already || isOver)
        Persistence.save(progress, key: Persistence.progressKey(dateKey))
    }

    private func recordResult(won: Bool) {
        // Guard against counting the same day twice across relaunches.
        if let saved = Persistence.load(DailyProgress.self, key: Persistence.progressKey(dateKey)),
           saved.counted { return }

        let day = DailyPuzzle.dayNumber()
        stats.gamesPlayed += 1
        if won {
            stats.gamesWon += 1
            if stats.lastCountedDay == day - 1 && stats.lastWasWin {
                stats.currentStreak += 1
            } else {
                stats.currentStreak = 1
            }
            stats.maxStreak = max(stats.maxStreak, stats.currentStreak)
            let key = String(guesses.count)
            stats.guessDistribution[key, default: 0] += 1
        } else {
            stats.currentStreak = 0
        }
        stats.lastCountedDay = day
        stats.lastWasWin = won
        Persistence.save(stats, key: Persistence.statsKey)
    }
}
