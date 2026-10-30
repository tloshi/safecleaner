import SwiftUI
#if SWIFT_PACKAGE
import SafeCleanerCore
#endif

enum Palette {
    static let background = Color(red: 0.037, green: 0.055, blue: 0.070)
    static let sidebar = Color(red: 0.057, green: 0.078, blue: 0.091)
    static let card = Color(red: 0.072, green: 0.100, blue: 0.119)
    static let mint = Color(red: 0.57, green: 0.94, blue: 0.78)
    static let muted = Color(red: 0.59, green: 0.66, blue: 0.70)
    static let line = Color.white.opacity(0.07)
    /// Semantic status colors: amber for “not yet confirmed”, rose for a failure.
    static let amber = Color(red: 0.98, green: 0.77, blue: 0.47)
    static let rose = Color(red: 0.94, green: 0.61, blue: 0.70)
    static func color(_ category: CleanCategory) -> Color {
        switch category {
        case .developer: return mint
        case .applications: return Color(red: 0.72, green: 0.66, blue: 0.98)
        case .browsers: return Color(red: 0.49, green: 0.76, blue: 0.98)
        case .logs: return amber
        case .projects: return rose
        case .simulators: return Color(red: 0.45, green: 0.86, blue: 0.90)
        case .android: return Color(red: 0.64, green: 0.86, blue: 0.47)
        case .xcode: return Color(red: 0.98, green: 0.62, blue: 0.42)
        case .gradle: return Color(red: 0.91, green: 0.80, blue: 0.50)
        }
    }
}

enum Motion {
    static let navigation = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let detail = Animation.spring(response: 0.32, dampingFraction: 0.9)
    static let feedback = Animation.easeOut(duration: 0.16)
    static let measurement = Animation.easeInOut(duration: 0.65)
}

struct Card<Content: View>: View {
    var accent = false
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [accent ? Palette.mint.opacity(0.11) : Palette.card, Palette.card], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(accent ? Palette.mint.opacity(0.21) : Palette.line, lineWidth: 1))
    }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.background).padding(.horizontal, 19).padding(.vertical, 12)
            .background(LinearGradient(colors: [Palette.mint, Palette.mint.opacity(0.83)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 11))
            .shadow(color: Palette.mint.opacity(enabled ? 0.09 : 0), radius: 12, y: 3)
            .opacity(enabled ? 1 : 0.38)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : Motion.feedback, value: configuration.isPressed)
    }
}

struct HoverSurface: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content.background(Color.white.opacity(hovered ? 0.025 : 0), in: RoundedRectangle(cornerRadius: radius))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : Motion.feedback, value: hovered)
    }
}

struct AnimatedNumber: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    let value: Double
    var body: some View {
        Text(text).contentTransition(reduceMotion ? .identity : .numericText(value: value))
            .animation(reduceMotion ? nil : Motion.measurement, value: value)
    }
}

struct CategoryIcon: View {
    let category: CleanCategory
    var body: some View {
        Image(systemName: category.symbol).font(.system(size: 17, weight: .medium))
            .foregroundStyle(Palette.color(category)).frame(width: 42, height: 42)
            .background(Palette.color(category).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.color(category).opacity(0.07)))
    }
}

struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(eyebrow).font(.system(size: 10, weight: .semibold)).tracking(2.0).foregroundStyle(Palette.mint)
            Text(title).font(.system(size: 29, weight: .semibold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.muted)
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(Palette.mint)
                .frame(width: 84, height: 84)
                .background(LinearGradient(colors: [Palette.mint.opacity(0.10), Palette.mint.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Palette.mint.opacity(0.09)))
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).frame(maxWidth: 400).lineSpacing(4)
        }.frame(maxWidth: .infinity).padding(.vertical, 65)
    }
}
