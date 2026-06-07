import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var game = GameState()
    @State private var showHelp = false
    @State private var showStats = false
    @State private var showHint = false
    @State private var showConfetti = false
    @State private var confirmGiveUp = false

    /// Gold so the revealed answer pops on the globe.
    private let revealColor = UIColor(red: 1.0, green: 0.84, blue: 0.27, alpha: 1)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    header
                    globe(height: max(260, geo.size.height * 0.46))
                    ScrollView(showsIndicators: false) { content }
                        .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 14)

                if showConfetti {
                    ConfettiView().transition(.opacity)
                }
            }
        }
        .sheet(isPresented: $showHelp) { HelpView() }
        .sheet(isPresented: $showStats) { StatsView(stats: game.stats) }
        .onChange(of: game.solved) { solved in if solved { celebrate() } }
        .onAppear { if !hasSeenHelp { showHelp = true; hasSeenHelp = true } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("🌍 Globle")
                    .font(Theme.rounded(26, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(todayString)
                    .font(Theme.rounded(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { showStats = true } label: { Image(systemName: "chart.bar.fill") }
                .accessibilityLabel("Stats")
            Button { showHelp = true } label: { Image(systemName: "questionmark.circle.fill") }
                .accessibilityLabel("How to play")
        }
        .font(.system(size: 26))
        .foregroundStyle(Theme.accent)
        .padding(.top, 4)
    }

    // MARK: - Globe

    private func globe(height: CGFloat) -> some View {
        GlobeView(countries: game.store.all,
                  fills: fills,
                  reveal: reveal,
                  focus: game.focus,
                  onFocusHandled: { game.focus = nil })
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.panelStroke, lineWidth: 1)
            )
            .overlay(alignment: .bottom) { statusPill.padding(.bottom, 10) }
    }

    private var statusPill: some View {
        Group {
            if let closest = game.closestGuess, !game.isOver {
                let warmth = game.warmth(for: closest)
                Text("Closest: \(closest.flag) \(warmth.emoji) \(warmth.text)")
            } else if game.guesses.isEmpty {
                Text("Spin the globe • Type a country to guess")
            } else {
                EmptyView()
            }
        }
        .font(Theme.rounded(13, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.black.opacity(0.45), in: Capsule())
    }

    private var fills: [(country: Country, color: UIColor)] {
        game.guesses
            .filter { $0.id != game.target.id }
            .map { ($0, Warmth.color(forDistanceKm: game.distanceKm(to: $0))) }
    }

    private var reveal: (country: Country, color: UIColor)? {
        game.isOver ? (game.target, revealColor) : nil
    }

    // MARK: - Scrollable content

    private var content: some View {
        VStack(spacing: 14) {
            if game.isOver {
                WinBanner(game: game)
            } else {
                GuessInputView(store: game.store, excluded: game.guessedIds) { country in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    game.makeGuess(country)
                }
                if game.hintAvailable { hintSection }
            }

            GuessListView(game: game)

            if !game.isOver && !game.guesses.isEmpty {
                Button(role: .destructive) { confirmGiveUp = true } label: {
                    Text("Show me the answer")
                        .font(Theme.rounded(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.textSecondary)
                .confirmationDialog("Reveal today's country?", isPresented: $confirmGiveUp, titleVisibility: .visible) {
                    Button("Yes, show me", role: .destructive) { game.giveUp() }
                    Button("Keep playing", role: .cancel) {}
                }
            }
            Color.clear.frame(height: 16)
        }
        .padding(.top, 2)
    }

    private var hintSection: some View {
        Group {
            if showHint {
                HStack(spacing: 10) {
                    Text("💡").font(.system(size: 24))
                    Text(game.hintText)
                        .font(Theme.rounded(16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                .cardStyle()
            } else {
                Button { withAnimation { showHint = true } } label: {
                    Label("Need a hint?", systemImage: "lightbulb.fill")
                        .font(Theme.rounded(15, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
        }
    }

    // MARK: - Helpers

    @AppStorage("globle.hasSeenHelp") private var hasSeenHelp = false

    private var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    private func celebrate() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { showConfetti = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation { showConfetti = false }
        }
    }
}

#Preview {
    ContentView()
}
