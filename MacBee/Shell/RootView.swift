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
                            }
                        }
                        .clipped()
                        .animation(.easeOut(duration: 0.2), value: model.showQueue)
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
                if let video = model.playingVideo {
                    VideoPlayerOverlay(playback: video)
                        .id(video.id)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.playingVideo)
            .environment(library)
            .alert("Tag editor", isPresented: Binding(
                get: { model.tagEditor?.problem != nil },
                set: { if !$0 { model.tagEditor?.problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.tagEditor?.problem ?? "")
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

    private var errorShown: Binding<Bool> {
        Binding(get: { player.errorMessage != nil },
                set: { if !$0 { player.errorMessage = nil } })
    }
}
