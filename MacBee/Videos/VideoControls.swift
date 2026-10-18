import AppKit
import MacBeeVideo
import SwiftUI

/// The bars over a playing video: title and close at the top; play/pause, skip, the time bar,
/// audio and subtitle choices, volume and full screen at the bottom.
struct VideoControls: View {
    let player: MPVPlayer
    let playback: VideoPlayback
    let visible: Bool
    let onMini: () -> Void
    let onClose: () -> Void

    @Environment(\.theme) private var theme
    @AppStorage("videoVolume") private var volume = 100.0
    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            if player.isBuffering {
                Text("Loading…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            if let error = player.errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.7)))
            }
            Spacer()
            bottomBar
        }
        .opacity(visible || player.isPaused ? 1 : 0)
        .onAppear { player.setVolume(volume) }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            CircleButton(systemImage: "chevron.down", help: "Close (Esc)", tinted: false, action: onClose)
            VStack(alignment: .leading, spacing: 2) {
                Text(playback.title)
                    .font(.system(size: 16, weight: .semibold))
                if !playback.subtitle.isEmpty {
                    Text(playback.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            Spacer()
            VideoLikeButton(id: playback.likeId, diameter: 34)
            CircleButton(systemImage: "pip.enter", help: "Mini player: keep watching while you browse",
                         tinted: false, diameter: 34, action: onMini)
        }
        .padding(20)
        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(Self.time(scrubbing ?? player.position))
                Slider(value: Binding(get: { scrubbing ?? player.position },
                                      set: { scrubbing = $0 }),
                       in: 0...max(player.duration, 1)) { editing in
                    if !editing, let target = scrubbing {
                        player.seek(to: target)
                        scrubbing = nil
                    }
                }
                .controlSize(.small)
                Text("-" + Self.time(max(0, player.duration - (scrubbing ?? player.position))))
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 18) {
                trackMenu(title: "Audio", systemImage: "waveform", tracks: player.audioTracks, kind: "audio", allowsOff: false)
                trackMenu(title: "Subtitles", systemImage: "captions.bubble", tracks: player.subtitleTracks, kind: "sub", allowsOff: true)
                Spacer()
                controlButton("gobackward.10", help: "Back 10 seconds (←)") { player.seek(by: -10) }
                controlButton(player.isPaused ? "play.fill" : "pause.fill", help: "Play/Pause (Space)", size: 26) { player.togglePause() }
                controlButton("goforward.10", help: "Forward 10 seconds (→)") { player.seek(by: 10) }
                Spacer()
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.white.opacity(0.8))
                Slider(value: $volume, in: 0...100)
                    .frame(width: 100)
                    .controlSize(.small)
                    .onChange(of: volume) { _, value in player.setVolume(value) }
                controlButton("arrow.up.left.and.arrow.down.right", help: "Full screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
    }

    private func controlButton(_ systemImage: String, help: String, size: CGFloat = 18, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func trackMenu(title: String, systemImage: String, tracks: [MPVPlayer.Track], kind: String, allowsOff: Bool) -> some View {
        Menu {
            if allowsOff {
                Button {
                    player.select(nil, kind: kind)
                } label: {
                    if !tracks.contains(where: \.isSelected) { Label("Off", systemImage: "checkmark") } else { Text("Off") }
                }
            }
            ForEach(tracks) { track in
                Button {
                    player.select(track, kind: kind)
                } label: {
                    if track.isSelected { Label(track.title, systemImage: "checkmark") } else { Text(track.title) }
                }
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(tracks.isEmpty ? 0.4 : 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(tracks.isEmpty)
        .help(title)
    }

    /// 125 -> "2:05", 3725 -> "1:02:05"
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Buttons over the mini player, shown while the mouse is over it: expand, play/pause, close,
/// and a thin bar showing how far along the video is.
struct MiniVideoControls: View {
    let player: MPVPlayer
    let onExpand: () -> Void
    let onClose: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        ZStack {
            if hovering {
                Color.black.opacity(0.35)
                HStack(spacing: 22) {
                    button("arrow.up.left.and.arrow.down.right", help: "Back to full size", action: onExpand)
                    button(player.isPaused ? "play.fill" : "pause.fill", help: "Play/Pause", size: 24) { player.togglePause() }
                    button("xmark", help: "Close video", action: onClose)
                }
            }
            VStack {
                Spacer()
                GeometryReader { geometry in
                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: geometry.size.width * progress)
                }
                .frame(height: 3)
            }
        }
        .onHover { hovering = $0 }
        .help("Drag to move. Double-click for full size.")
    }

    private var progress: CGFloat {
        player.duration > 0 ? CGFloat(min(1, player.position / player.duration)) : 0
    }

    private func button(_ systemImage: String, help: String, size: CGFloat = 16, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
