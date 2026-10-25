import MacBeeLibrary
import SwiftUI

/// Window layout: sidebar | content, with the full-width play bar along the bottom.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        if let library = model.library {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    SidebarView(selection: Binding(get: { model.selection }, set: { model.selection = $0 }))
                    Rectangle().fill(theme.separator).frame(width: 1)
                    ContentRouter(selection: model.selection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.background)
                        .overlay(alignment: .trailing) {
                            if model.showQueue {
                                QueueDrawer()
                                    .transition(.move(edge: .trailing))
                            } else if model.showLyrics {
                                LyricsDrawer()
                                    .transition(.move(edge: .trailing))
                            }
                        }
                        .clipped()
                        .animation(.easeOut(duration: 0.2), value: model.showQueue)
                        .animation(.easeOut(duration: 0.2), value: model.showLyrics)
                }
                Rectangle().fill(theme.separator).frame(height: 1)
                PlayBarView()
                    .zIndex(1) // keeps pop-up panels from the bar above the page content
            }
            .overlay {
                if model.showNowPlaying {
                    NowPlayingView()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.showNowPlaying)
            .overlay {
                if let session = model.videoSession, !model.videoIsMini {
                    VideoPlayerOverlay(session: session)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.videoSession == nil || model.videoIsMini)
            .environment(library)
            .task(id: player.currentTrack?.path) {
                // A song without lyrics gets them looked up online as it starts (Settings > General > Lyrics).
                guard model.preferences.findLyricsOnline, let track = player.currentTrack else { return }
                await model.lyrics.fill(track)
            }
            .modifier(PlaylistActionsModifier())
            .alert("Tag editor", isPresented: Binding(
                get: { model.tagEditor?.problem != nil },
                set: { if !$0 { model.tagEditor?.problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.tagEditor?.problem ?? "")
            }
            .alert("Deleted on \(model.networkSync?.pendingRemovalsFrom ?? "your other Mac")", isPresented: removalsShown) {
                Button("Delete Here Too", role: .destructive) {
                    let ids = model.networkSync?.pendingRemovals.map(\.playlistId) ?? []
                    model.networkSync?.pendingRemovals = []
                    Task {
                        for id in ids {
                            if let playlist = model.playlists?.playlist(id: id) { await model.playlists?.delete(playlist) }
                        }
                    }
                }
                Button("Keep Them", role: .cancel) { model.networkSync?.keepPendingRemovals() }
            } message: {
                Text("These were deleted on \(model.networkSync?.pendingRemovalsFrom ?? "your other Mac") but are still on this Mac:\n\n"
                     + (model.networkSync?.pendingRemovals.map { ($0.removed.folders + [$0.removed.name]).joined(separator: " › ") } ?? [])
                        .joined(separator: "\n")
                     + "\n\nDelete them here too?")
            }
            .alert("Playback problem", isPresented: errorShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(player.errorMessage ?? "")
            }
        } else {
            ContentUnavailableView("The music library couldn't be opened",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(model.libraryError ?? "Unknown error"))
        }
    }

    private var removalsShown: Binding<Bool> {
        Binding(get: { !(model.networkSync?.pendingRemovals.isEmpty ?? true) },
                set: { _ in }) // the two buttons decide (and empty the list)
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { player.errorMessage != nil },
                set: { if !$0 { player.errorMessage = nil } })
    }
}
