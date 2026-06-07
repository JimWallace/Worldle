import SwiftUI

/// Lightweight, GPU-friendly confetti drawn in a single Canvas (no per-piece views).
struct ConfettiView: View {
    private struct Piece {
        let x: CGFloat          // 0…1 horizontal start
        let delay: Double
        let speed: Double
        let sway: CGFloat
        let size: CGFloat
        let spin: Double
        let color: Color
    }

    private let pieces: [Piece]
    private let startDate = Date()
    private static let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .mint]

    init(count: Int = 70) {
        pieces = (0..<count).map { _ in
            Piece(x: .random(in: 0...1),
                  delay: .random(in: 0...0.9),
                  speed: .random(in: 0.5...1.1),
                  sway: .random(in: 12...48),
                  size: .random(in: 7...13),
                  spin: .random(in: -2.0...2.0),
                  color: Self.palette.randomElement()!)
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startDate)
                for piece in pieces {
                    let local = max(0, elapsed - piece.delay) * piece.speed
                    let fallHeight = size.height + 40
                    let y = ((local * 160).truncatingRemainder(dividingBy: fallHeight)) - 20
                    let x = piece.x * size.width + sin(local * 2 + Double(piece.x) * 6) * piece.sway
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 2,
                                      width: piece.size, height: piece.size * 0.62)
                    let transform = CGAffineTransform(translationX: x, y: y)
                        .rotated(by: piece.spin * local)
                    let path = Path(roundedRect: rect, cornerRadius: 2).applying(transform)
                    context.fill(path, with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
