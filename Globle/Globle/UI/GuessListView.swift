import SwiftUI

/// The list of guesses, ranked hottest-first like Globle, each with its closeness color.
struct GuessListView: View {
    @ObservedObject var game: GameState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !game.guesses.isEmpty {
                Text("Your guesses (\(game.guesses.count))")
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(game.rankedGuesses) { country in
                row(for: country)
            }
        }
    }

    private func row(for country: Country) -> some View {
        let km = game.distanceKm(to: country)
        let warmth = Warmth.label(forDistanceKm: km)
        let isClosest = country.id == game.closestGuess?.id && !game.isOver
        return Button {
            game.focus = country
        } label: {
            HStack(spacing: 12) {
                Text(country.flag).font(.system(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    Text(country.name)
                        .font(Theme.rounded(18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(distanceText(km))
                        .font(Theme.rounded(13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("\(warmth.emoji) \(warmth.text)")
                    .font(Theme.rounded(15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(game.color(for: country))
                    .frame(width: 26, height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.25), lineWidth: 1))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isClosest ? Theme.accent : Theme.panelStroke, lineWidth: isClosest ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func distanceText(_ km: Double) -> String {
        if km < 1 { return "That's the one!" }
        return "\(Int(km.rounded())) km from the mystery country"
    }
}
