import AppKit
import MacBeeAudio
import MacBeeLibrary
import SwiftUI

/// "Record to MiniDisc": plays a playlist into a recorder through the headphone jack, a USB DAC or an
/// optical adapter, with a silent gap between songs so each one becomes its own track on the disc.
struct RecordToMiniDiscSheet: View {
    let title: String
    @State private var session: RecordOutSession

    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var devices: [AudioDevice] = []

    init(title: String, tracks: [Track], player: PlayerViewModel, discMinutes: Int? = nil) {
        self.title = title
        _session = State(initialValue: RecordOutSession(tracks: tracks, player: player, discMinutes: discMinutes))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(20)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                settings
                    .frame(width: 330, alignment: .topLeading)
                    .padding(20)
                Divider()
                trackList
            }
            Divider()
            footer
                .padding(16)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 600)
        .background(theme.background)
        .interactiveDismissDisabled(session.isRunning)
        .onAppear { devices = player.availableDevices() }
        .onDisappear { session.close() }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 22))
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Record to MiniDisc").font(.mbSection)
                Text("\(title) · \(session.tracks.count) songs")
                    .font(.mbSecondary)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            statusText
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch session.phase {
        case .setup:
            EmptyView()
        case let .leadIn(left):
            Text("Starting in \(left)…").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.accent)
        case .recording:
            Text(session.pauseAfterCurrent
                 ? "Pausing after song \(session.currentNumber ?? 1) of \(session.tracks.count)"
                 : "Playing song \(session.currentNumber ?? 1) of \(session.tracks.count)")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.accent)
        case .paused:
            Text("Paused after song \(session.currentNumber ?? 0) of \(session.tracks.count)")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.warning)
        case .finished:
            Label("Done. Stop the recorder now.", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.good)
        case .stopped:
            Text("Stopped").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.warning)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            step(1, "Connect the recorder") {
                Text("Cable from the Mac's headphone jack (or a USB DAC) to the recorder's LINE IN, not MIC. With an optical adapter, use OPTICAL IN: best quality, and the recorder numbers tracks by itself.")
            }
            step(2, "Output") {
                Picker("Output", selection: deviceBinding) {
                    Text("macOS default").tag(String?.none)
                    ForEach(devices) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                }
                .labelsHidden()
                .disabled(session.isRunning)
                Text("Hi-res songs are sent at 44.1 or 48 kHz, which the recorder accepts.")
            }
            step(3, "Disc and gaps") {
                Picker("Disc", selection: $session.discMinutes) {
                    ForEach(RecordOutSession.discLengths, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(session.isRunning)
                CapacityBar(total: session.totalSeconds, capacity: Double(session.discMinutes * 60))
                Stepper("Gap between songs: \(Int(session.gap)) s", value: $session.gap, in: 2...6, step: 1)
                    .disabled(session.isRunning)
                    .foregroundStyle(theme.textPrimary)
            }
            step(4, "Record") {
                Text("Set the recording level on the recorder, start it recording, then click Start. MacBee waits \(RecordOutSession.leadInSeconds) seconds, then plays. Recording takes as long as the songs: \(Format.minutes(session.totalSeconds)).")
            }
            if player.engine.equalizer.isActive {
                Label("The equalizer is on and will be recorded.", systemImage: "slider.vertical.3")
                    .font(.mbCaption)
                    .foregroundStyle(theme.warning)
            }
        }
    }

    private func step<Content: View>(_ number: Int, _ heading: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(number). \(heading)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            content()
                .font(.mbCaption)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trackList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(session.tracks.enumerated()), id: \.offset) { index, track in
                    trackRow(index + 1, track)
                        .id(index + 1)
                }
            }
            .scrollContentBackground(.hidden)
            .onChange(of: session.currentNumber) { _, number in
                if let number { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(number, anchor: .center) } }
            }
        }
    }

    private func trackRow(_ number: Int, _ track: Track) -> some View {
        let isCurrent = session.currentNumber == number
        return HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(isCurrent ? theme.accent : theme.textTertiary)
                .frame(width: 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.displayTitle)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? theme.accent : theme.textPrimary)
                Text(track.displayArtist)
                    .font(.mbCaption)
                    .foregroundStyle(theme.textSecondary)
            }
            .lineLimit(1)
            Spacer()
            Text(Format.time(track.duration))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            Button("Copy Track Names") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.trackNames, forType: .string)
            }
            .help("Copies a numbered list of titles, for typing them in on the recorder")
            Spacer()
            if session.isRunning {
                pauseButton
                Button("Stop") { session.stop() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button(session.phase == .setup ? "Cancel" : "Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if session.phase != .finished {
                    Button(session.phase == .setup ? "Start" : "Start Again") { session.start() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(session.tracks.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var pauseButton: some View {
        switch session.phase {
        case .paused:
            Button("Resume Play", systemImage: "play.fill") { session.resume() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Start the recorder again, then click: plays on from the next song after a 3-second lead-in")
        case .recording:
            Button(session.pauseAfterCurrent ? "Keep Playing" : "Pause After This Song",
                   systemImage: session.pauseAfterCurrent ? "play.fill" : "pause.fill") {
                session.togglePauseAfterCurrent()
            }
            .help("Stops when this song ends, so you can pause the recorder; Resume Play continues with the next song")
        default:
            EmptyView()
        }
    }

    private var deviceBinding: Binding<String?> {
        Binding(get: { player.engine.settings.deviceUID },
                set: { player.selectDevice(uid: $0) })
    }
}
