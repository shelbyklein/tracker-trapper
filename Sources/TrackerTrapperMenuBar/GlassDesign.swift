import SwiftUI

private struct TrackerOpaqueSurfacesKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var trackerOpaqueSurfaces: Bool {
        get { self[TrackerOpaqueSurfacesKey.self] }
        set { self[TrackerOpaqueSurfacesKey.self] = newValue }
    }
}

/// Shared native material treatment for the panel, cards and celebration.
struct TrackerGlassSurface: ViewModifier {
    var radius: CGFloat = 22
    var shell = false
    @ObservedObject var appearance: AppearanceSettings = .shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.trackerOpaqueSurfaces) private var opaqueSurfaces
    func body(content: Content) -> some View {
        content.background {
            let preferences = appearance.preferences.normalized
            let tint = preferences.color.opacity(preferences.tintStrength * (shell ? 1 : 0.39))
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if reduceTransparency || opaqueSurfaces {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else if #available(macOS 26.0, *) {
                shape.fill(.clear)
                    .glassEffect((preferences.clarity == .clear ? Glass.clear : Glass.regular).tint(tint), in: shape)
                    .overlay {
                        if preferences.clarity == .frosted {
                            shape.fill(.thickMaterial).opacity(0.65)
                        }
                    }
                    .overlay(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(preferences.opacity)))
            } else {
                shape.fill(preferences.clarity == .clear ? .ultraThinMaterial : preferences.clarity == .frosted ? .thickMaterial : .regularMaterial)
                    .overlay(shape.fill(tint))
                    .overlay(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(preferences.opacity)))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.24 : 0.8), .white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(shell ? 0.08 : 0.035), radius: shell ? 14 : 6, y: 3)
    }
}
extension View {
    func trackerGlass(radius: CGFloat = 22, shell: Bool = false) -> some View {
        modifier(TrackerGlassSurface(radius: radius, shell: shell))
    }
}
struct TrackerProgress: View {
    let completed: Int
    let total: Int
    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text("\(completed)/\(total) complete")
                Spacer()
                Text("\(Int(Double(completed) / Double(max(total, 1)) * 100))%")
            }.font(.system(size: 12)).monospacedDigit()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.blue.opacity(0.12))
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.02, green: 0.40, blue: 1), .cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * CGFloat(completed) / CGFloat(max(total, 1)))
                }
            }.frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completed) of \(total) tasks complete")
    }
}
