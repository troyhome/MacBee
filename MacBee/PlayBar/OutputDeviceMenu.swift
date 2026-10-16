import MacBeeAudio
import SwiftUI

/// Picks the output device (DAC, speakers...). Each device shows the sample rates it supports.
struct OutputDeviceMenu: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
            Picker("Output", selection: Binding(get: { player.engine.settings.deviceUID },
                                                set: { player.selectDevice(uid: $0) })) {
                Text(systemDefaultTitle).tag(String?.none)
                Divider()
                ForEach(player.availableDevices()) { device in
                    Text("\(device.name)  ·  \(details(for: device))").tag(Optional(device.uid))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: "hifispeaker.2")
                .foregroundStyle(theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 4)
        .help("Output: \(player.engine.outputDevice?.name ?? "System Default")")
    }

    /// "System Default (MacBook Air Speakers)" while following the Mac's setting.
    private var systemDefaultTitle: String {
        guard player.engine.settings.deviceUID == nil, let name = player.engine.outputDevice?.name else {
            return "System Default"
        }
        return "System Default (\(name))"
    }

    /// "44.1, 48, 88.2, 96 kHz", or a range when the device has many rates.
    private func details(for device: AudioDevice) -> String {
        if device.isVirtual { return "virtual device, never bit-perfect" }
        let rates = device.supportedSampleRates.map { AudioFormatInfo.formatRate($0).replacingOccurrences(of: " kHz", with: "") }
        guard let first = rates.first, let last = rates.last else { return "rates unknown" }
        return (rates.count <= 5 ? rates.joined(separator: ", ") : "\(first)–\(last)") + " kHz"
    }
}
