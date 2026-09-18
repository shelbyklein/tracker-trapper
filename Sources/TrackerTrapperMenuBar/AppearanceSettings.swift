import AppKit
import SwiftUI

struct GlassPreferences: Codable, Equatable {
    enum Clarity: String, Codable, CaseIterable {
        case clear, regular, frosted
        var title: String { rawValue.capitalized }
    }
    var clarity: Clarity = .regular
    var red = 0.0
    var green = 0.48
    var blue = 1.0
    var tintStrength = 0.09
    var opacity = 0.0

    var color: Color { Color(red: red, green: green, blue: blue) }
    var normalized: Self {
        var value = self
        func unit(_ number: Double, fallback: Double) -> Double {
            number.isFinite ? min(1, max(0, number)) : fallback
        }
        value.red = unit(red, fallback: 0)
        value.green = unit(green, fallback: 0.48)
        value.blue = unit(blue, fallback: 1)
        value.tintStrength = unit(tintStrength, fallback: 0.09)
        value.opacity = unit(opacity, fallback: 0)
        return value
    }
}

@MainActor final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()
    static let key = "appearance.glass.v1"
    private let defaults: UserDefaults
    @Published var preferences: GlassPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences.normalized) {
                defaults.set(data, forKey: Self.key)
            }
        }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(GlassPreferences.self, from: $0) }?.normalized ?? GlassPreferences()
    }
    func reset() { preferences = GlassPreferences() }
    var color: Color {
        get { preferences.normalized.color }
        set {
            guard let color = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            var value = preferences
            value.red = color.redComponent; value.green = color.greenComponent; value.blue = color.blueComponent
            preferences = value
        }
    }
}

struct AppearancePane: View {
    @ObservedObject var appearance: AppearanceSettings = .shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Form {
            Section("Glass appearance") {
                Picker("Glass clarity", selection: $appearance.preferences.clarity) {
                    ForEach(GlassPreferences.Clarity.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text("Clear lets more background through. Frosted softens it for easier reading.")
                    .font(.caption).foregroundStyle(.secondary)
                ColorPicker("Glass tint", selection: $appearance.color, supportsOpacity: false)
                slider("Tint strength", value: $appearance.preferences.tintStrength)
                slider("Surface opacity", value: $appearance.preferences.opacity)
                Text("Higher opacity hides more of the background. Text and controls stay sharp.")
                    .font(.caption).foregroundStyle(.secondary)
                if reduceTransparency {
                    Label("Reduce Transparency is on in macOS. Glass surfaces stay opaque.", systemImage: "accessibility")
                        .font(.caption)
                }
            }
            Section("Live preview") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Tracker Trapper").font(.headline)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Build something great").font(.headline)
                        TrackerProgress(completed: 2, total: 5)
                    }.padding(14).modifier(TrackerGlassSurface(radius: 16, appearance: appearance))
                }
                .padding(16)
                .modifier(TrackerGlassSurface(radius: 22, shell: true, appearance: appearance))
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(colors: [.blue, .cyan, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                Text("Changes apply immediately to your panel and cards and are saved automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button { appearance.reset() } label: {
                Image(systemName: "arrow.counterclockwise")
            }
                .help("Reset Appearance")
                .accessibilityLabel("Reset Appearance")
                .disabled(appearance.preferences == GlassPreferences())
        }.formStyle(.grouped)
    }
    private func slider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Slider(value: value, in: 0...1) { Text(title) }
            Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
        }
    }
}
