import Foundation

/// Picks the mystery country of the day. The choice is fully deterministic from the
/// calendar date, so every device shows the same country on the same day, and the
/// sequence walks through every sovereign country before repeating.
enum DailyPuzzle {
    /// Day 0 of the puzzle sequence.
    private static let epoch = DateComponents(year: 2024, month: 1, day: 1)
    /// Fixed seed so the shuffled order is identical everywhere.
    private static let seed: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// Whole days from the epoch to `date` in the given calendar.
    static func dayNumber(for date: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: calendar.date(from: epoch) ?? date)
        let today = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: today).day ?? 0
    }

    /// Stable per-day key (e.g. "2026-06-07") used to save progress.
    static func dateKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The mystery country for `date`, chosen from `targets`.
    static func target(from targets: [Country], on date: Date = Date(),
                       calendar: Calendar = .current) -> Country? {
        let ordered = targets.sorted { $0.id < $1.id }
        guard !ordered.isEmpty else { return nil }
        let permutation = shuffledIndices(count: ordered.count, seed: seed)
        let day = dayNumber(for: date, calendar: calendar)
        let index = ((day % ordered.count) + ordered.count) % ordered.count
        return ordered[permutation[index]]
    }

    /// Deterministic Fisher–Yates shuffle driven by SplitMix64.
    private static func shuffledIndices(count: Int, seed: UInt64) -> [Int] {
        var indices = Array(0..<count)
        var state = seed
        func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        if count > 1 {
            for i in stride(from: count - 1, to: 0, by: -1) {
                let j = Int(next() % UInt64(i + 1))
                indices.swapAt(i, j)
            }
        }
        return indices
    }
}
