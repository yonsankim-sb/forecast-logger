import SwiftUI

/// Live controls for the background shader: choose the shader style, tune its
/// own parameter page, and edit the shared gradient — with a live preview.
struct NoiseControlsView: View {
    @ObservedObject private var settings = NoiseSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SymbolBadge(system: "circle.circle.fill", tint: .orange, size: 30)
                Text("Background").font(.headline)
                Spacer()
            }
            .padding(20)

            // Live preview of the active shader.
            NoiseBackground()
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
                .padding(.horizontal, 20)

            Form {
                Section("Motion") {
                    slider("Speed", value: $settings.params.speed, range: 0...2)
                    slider("Circles", value: $settings.params.circles, range: 1...8)
                }
                Section("Glass") {
                    slider("Refraction", value: $settings.params.refraction, range: 0...1)
                    slider("Gloss", value: $settings.params.gloss, range: 0...2)
                    slider("Aberration", value: $settings.params.aberration, range: 0...1)
                    slider("Rim width", value: $settings.params.rim, range: 0.05...0.45)
                    slider("Reflection", value: $settings.params.reflection, range: 0...1)
                    slider("Caustics", value: $settings.params.caustics, range: 0...1)
                }
                Section("Color") {
                    slider("Hue", value: $settings.params.hue, range: 0...1)
                    slider("Saturation", value: $settings.params.saturation, range: 0...2)
                    slider("Iridescence", value: $settings.params.iridescence, range: 0...1)
                }
            }
            .formStyle(.grouped)
            .scrollIndicators(.hidden)
            .hideScrollers()

            Divider()

            HStack {
                Button("Reset") { settings.reset() }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 420, height: 560)
        .tint(.blue)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

#if DEBUG
#Preview("Pulse-ring controls") {
    NoiseControlsView()
}
#endif
