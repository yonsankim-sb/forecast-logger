import SwiftUI

/// Tunable parameters for the liquid-glass concentric-circle background shader.
struct ShaderParams: Codable, Equatable {
    /// Outward expansion speed of the rings.
    var speed: Double
    /// Ring frequency — how many concentric circles are visible at once.
    var circles: Double
    /// Strength of the lens bend at each glass rim.
    var refraction: Double
    /// Specular / highlight intensity of the glass.
    var gloss: Double
    /// Chromatic aberration (color fringing) at the rims.
    var aberration: Double
    /// Width of the glass rim band around each circle boundary.
    var rim: Double
    /// Manual overall hue shift, 0…1 → a full turn around the color wheel.
    var hue: Double
    /// Thin-film rainbow sheen + depth on the glass rims (0 = flat tint).
    var iridescence: Double
    /// Environment reflection strength (cool sky above, warm below).
    var reflection: Double
    /// Focused light filaments (caustics) on the rims.
    var caustics: Double
    /// Overall color saturation (1 = normal, 0 = greyscale, >1 = boosted).
    var saturation: Double

    init(speed: Double = 0.5, circles: Double = 4.0, refraction: Double = 0.4,
         gloss: Double = 1.0, aberration: Double = 0.45, rim: Double = 0.22,
         hue: Double = 0.0, iridescence: Double = 0.35,
         reflection: Double = 0.3, caustics: Double = 0.4, saturation: Double = 1.0) {
        self.speed = speed
        self.circles = circles
        self.refraction = refraction
        self.gloss = gloss
        self.aberration = aberration
        self.rim = rim
        self.hue = hue
        self.iridescence = iridescence
        self.reflection = reflection
        self.caustics = caustics
        self.saturation = saturation
    }

    /// Resilient decoder: any missing key falls back to its default, so adding
    /// or renaming a parameter never discards the rest of a saved preset.
    init(from decoder: Decoder) throws {
        let d = Self()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed
        circles = try c.decodeIfPresent(Double.self, forKey: .circles) ?? d.circles
        refraction = try c.decodeIfPresent(Double.self, forKey: .refraction) ?? d.refraction
        gloss = try c.decodeIfPresent(Double.self, forKey: .gloss) ?? d.gloss
        aberration = try c.decodeIfPresent(Double.self, forKey: .aberration) ?? d.aberration
        rim = try c.decodeIfPresent(Double.self, forKey: .rim) ?? d.rim
        hue = try c.decodeIfPresent(Double.self, forKey: .hue) ?? d.hue
        iridescence = try c.decodeIfPresent(Double.self, forKey: .iridescence) ?? d.iridescence
        reflection = try c.decodeIfPresent(Double.self, forKey: .reflection) ?? d.reflection
        caustics = try c.decodeIfPresent(Double.self, forKey: .caustics) ?? d.caustics
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? d.saturation
    }
}

/// Live, persisted parameters controlling the background shader.
@MainActor
final class NoiseSettings: ObservableObject {
    static let shared = NoiseSettings()

    @Published var params: ShaderParams { didSet { save() } }

    // New key for the liquid-glass shader; earlier ripple/ring presets are left
    // untouched so this effect starts from its own clean defaults.
    private static let key = "shader.glass"
    private static let defaults = ShaderParams()

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let p = try? JSONDecoder().decode(ShaderParams.self, from: data) {
            params = p
        } else {
            params = Self.defaults
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(params) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func reset() { params = Self.defaults }
}
