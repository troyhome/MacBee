import SwiftUI

/// Opens the Equalizer window. Lit in the accent color while the EQ is changing the sound.
struct EqualizerButton: View {
    @Environment(EqualizerStore.self) private var eq
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        BarIconButton(systemImage: "slider.vertical.3",
                      help: eq.isActive ? "Equalizer is on (\(eq.presetTitle)): not bit-perfect. Click to open."
                                        : "Equalizer (off, bit-perfect). Click to open.",
                      isActive: eq.isActive) { openWindow(id: MacBeeApp.equalizerWindowID) }
    }
}
