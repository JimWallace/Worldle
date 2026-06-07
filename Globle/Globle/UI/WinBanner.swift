import SwiftUI

/// Shown once the puzzle is solved or given up: celebration, the answer, quick stats and sharing.
struct WinBanner: View {
    @ObservedObject var game: GameState

    var body: some View {
        VStack(spacing: 14) {
            Text(game.solved ? "You did it! 🎉" : "So close! 🌍")
                .font(Theme.rounded(28, weight: .heavy))
                .foregroundStyle(game.solved ? Theme.win : Theme.accent)

            VStack(spacing: 4) {
                Text(game.target.flag).font(.system(size: 56))
                Text(game.target.name)
                    .font(Theme.rounded(24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.rounded(16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                game.focus = game.target
            } label: {
                Label("Show me on the globe", systemImage: "globe")
                    .font(Theme.rounded(16, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            statsRow

            ShareLink(item: shareText) {
                Label("Share result", systemImage: "square.and.arrow.up")
                    .font(Theme.rounded(16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)

            Text("A brand-new mystery country arrives tomorrow!")
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 18)
    }

    private var subtitle: String {
        game.solved
            ? "Solved in \(game.guesses.count) \(game.guesses.count == 1 ? "guess" : "guesses")!"
            : "That was today's mystery country."
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat("Played", "\(game.stats.gamesPlayed)")
            stat("Win %", "\(game.stats.winPercent)")
            stat("Streak", "\(game.stats.currentStreak)")
            stat("Best", "\(game.stats.maxStreak)")
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.rounded(22, weight: .heavy)).foregroundStyle(Theme.textPrimary)
            Text(title).font(Theme.rounded(12, weight: .medium)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var shareText: String {
        let squares = game.guesses.map { country -> String in
            country.id == game.target.id ? "🎯" : Self.square(forKm: game.distanceKm(to: country))
        }.joined()
        let header = "🌍 Globle • \(game.dateKey)"
        let line = game.solved ? "Found in \(game.guesses.count) 🔍" : "Maybe next time!"
        return "\(header)\n\(line)\n\(squares)"
    }

    private static func square(forKm km: Double) -> String {
        switch km {
        case ..<1000:  return "🟥"
        case ..<2500:  return "🟧"
        case ..<4500:  return "🟨"
        case ..<7000:  return "🟩"
        case ..<10000: return "🟦"
        default:       return "⬜"
        }
    }
}
