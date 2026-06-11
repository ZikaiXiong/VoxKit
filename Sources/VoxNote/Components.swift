import SwiftUI

extension LinearGradient {
    /// Brand gradient: indigo → sky blue
    static let vox = LinearGradient(
        colors: [Color(red: 0.36, green: 0.32, blue: 0.96), Color(red: 0.13, green: 0.67, blue: 0.97)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Audio level meter
struct LevelMeter: View {
    let level: Float
    var barCount: Int = 21
    var barWidth: CGFloat = 3.5
    var spacing: CGFloat = 3
    var maxBarHeight: CGFloat = 32   // bars bounce between minBarHeight and this with the mic level
    var minBarHeight: CGFloat = 5

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient.vox)
                    .frame(width: barWidth, height: height(for: i))
                    .opacity(0.45 + 0.55 * Double(level))
            }
        }
        .frame(height: maxBarHeight + 8)
        .animation(.easeOut(duration: 0.09), value: level)
    }

    private func height(for index: Int) -> CGFloat {
        let mid = Double(barCount - 1) / 2
        let envelope = 1.0 - abs(Double(index) - mid) / (mid + 2)
        let wobble = 0.55 + 0.45 * abs(sin(Double(index) * 1.7))
        return minBarHeight + CGFloat(Double(level) * envelope * wobble) * maxBarHeight
    }
}

/// Small tag chip
struct TagChip: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }
}

/// Card container
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
            )
    }
}

extension View {
    /// Secondary caption text
    func captionStyle() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}
