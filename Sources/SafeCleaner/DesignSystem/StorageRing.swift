import SwiftUI

struct StorageRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    let fraction: Double
    let label: String
    private var displayed: Double { appeared || reduceMotion ? fraction : 0 }
    var body: some View {
        ZStack {
            Circle().stroke(Palette.mint.opacity(0.04), lineWidth: 28)
            Circle().stroke(Color.white.opacity(0.045), lineWidth: 10)
            Circle().trim(from: 0, to: displayed)
                .stroke(AngularGradient(colors: [Palette.mint.opacity(0.2), Palette.mint], center: .center,
                    startAngle: .degrees(0), endAngle: .degrees(360 * fraction)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Palette.mint.opacity(0.12), radius: 7)
            Circle().fill(Palette.mint).frame(width: 6, height: 6)
                .offset(y: -79).rotationEffect(.degrees(360 * displayed))
                .opacity(fraction > 0 ? 1 : 0)
            VStack(spacing: 6) {
                Text(label).font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("DISK USED").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Palette.muted)
            }
        }.frame(width: 158, height: 158).padding(12)
            .onAppear { appeared = true }
            .animation(reduceMotion ? nil : Motion.measurement, value: displayed)
            .accessibilityElement(children: .ignore).accessibilityLabel("Disk used: \(label)")
    }
}

struct ScanActivity: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let detail: String
    let cancel: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { context in
                ZStack {
                    Circle().stroke(Palette.mint.opacity(0.12), lineWidth: 2)
                    Circle().trim(from: 0, to: 0.28).stroke(Palette.mint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(reduceMotion ? -90 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) * 180))
                    Image(systemName: "sparkle").font(.system(size: 13)).foregroundStyle(Palette.mint)
                }.frame(width: 36, height: 36)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Making sense of your space…").font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer()
            Text("READ ONLY").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Palette.mint)
            Button("Cancel", action: cancel).buttonStyle(.bordered).controlSize(.small)
        }.padding(18).background(Palette.mint.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.mint.opacity(0.13)))
    }
}
