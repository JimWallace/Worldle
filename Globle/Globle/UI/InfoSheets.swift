import SwiftUI

/// Kid-friendly "how to play" sheet.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String)] = [
        ("🌍", "A secret country is hiding somewhere on Earth."),
        ("⌨️", "Type any country's name, then tap it to make a guess."),
        ("🔥", "Red means BOILING hot — your guess is right next to the secret country!"),
        ("❄️", "Blue means FREEZING cold — you're far, far away."),
        ("🎯", "Follow the warm colors to track down the mystery country."),
        ("🗓️", "Everyone gets the same country each day. Come back tomorrow for a new one!"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(steps, id: \.1) { emoji, text in
                        HStack(alignment: .top, spacing: 14) {
                            Text(emoji).font(.system(size: 34))
                            Text(text)
                                .font(Theme.rounded(18, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(22)
            }
            .background(Theme.background)
            .navigationTitle("How to play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it!") { dismiss() }.font(Theme.rounded(17, weight: .bold))
                }
            }
        }
    }
}

/// Lifetime statistics with a simple guess-count distribution.
struct StatsView: View {
    let stats: Stats
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 0) {
                        cell("\(stats.gamesPlayed)", "Played")
                        cell("\(stats.winPercent)", "Win %")
                        cell("\(stats.currentStreak)", "Streak")
                        cell("\(stats.maxStreak)", "Best")
                    }
                    if !stats.guessDistribution.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Guesses to win").font(Theme.rounded(18, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            distribution
                        }
                    } else {
                        Text("Play your first game to see your stats grow!")
                            .font(Theme.rounded(16, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(22)
            }
            .background(Theme.background)
            .navigationTitle("Your stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(Theme.rounded(17, weight: .bold))
                }
            }
        }
    }

    private var distribution: some View {
        let entries = stats.guessDistribution
            .compactMap { key, value -> (Int, Int)? in Int(key).map { ($0, value) } }
            .sorted { $0.0 < $1.0 }
        let maxValue = max(1, entries.map(\.1).max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(entries, id: \.0) { guesses, count in
                HStack(spacing: 8) {
                    Text("\(guesses)").font(Theme.rounded(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary).frame(width: 28, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(Theme.accent)
                            .frame(width: max(24, geo.size.width * CGFloat(count) / CGFloat(maxValue)))
                            .overlay(alignment: .trailing) {
                                Text("\(count)").font(Theme.rounded(13, weight: .bold))
                                    .foregroundStyle(.black.opacity(0.7)).padding(.trailing, 8)
                            }
                    }
                    .frame(height: 24)
                }
            }
        }
    }

    private func cell(_ value: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(Theme.rounded(26, weight: .heavy)).foregroundStyle(Theme.textPrimary)
            Text(title).font(Theme.rounded(13, weight: .medium)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
