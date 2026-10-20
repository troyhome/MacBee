import MacBeeLibrary
import SwiftUI

/// The magic wand in Track Studio: looks up covers online for every album in the list, shows the choices
/// for each album, and has TagBee write the chosen covers into the files.
struct CoverWandSheet: View {
    let tracks: [Track]

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [AlbumCovers] = []
    @State private var searching = true
    @State private var saving = false
    @State private var progress = ""
    @State private var problems: [String] = []
    @State private var savedCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars").font(.system(size: 20)).foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find Covers Online").font(.system(size: 18, weight: .bold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                if searching || saving { ProgressView().controlSize(.small) }
            }
            .padding(20)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach($albums) { $album in
                        AlbumCoverRow(album: $album)
                        Divider()
                    }
                }
            }
            Divider()
            HStack {
                if !problems.isEmpty {
                    Label(problems.joined(separator: "  "), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(theme.textSecondary).lineLimit(2)
                }
                Spacer()
                Button(savedCount == nil ? "Cancel" : "Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if savedCount == nil {
                    Button("Save Covers to \(chosenCount) Album\(chosenCount == 1 ? "" : "s")") { Task { await save() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(chosenCount == 0 || saving)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 820, idealWidth: 900, minHeight: 520, idealHeight: 640)
        .background(theme.background)
        .task { await searchAll() }
    }

    private var chosenCount: Int { albums.filter { $0.choice != nil }.count }

    private var subtitle: String {
        if let savedCount { return "Saved covers for \(savedCount) album\(savedCount == 1 ? "" : "s")." }
        if saving { return progress }
        if searching { return progress }
        return "\(albums.count) album\(albums.count == 1 ? "" : "s"). Click a cover to choose it, or None to leave that album alone."
    }

    /// One album at a time: MusicBrainz allows about one request a second.
    private func searchAll() async {
        albums = AlbumCovers.group(tracks)
        for i in albums.indices {
            progress = "Searching \(i + 1) of \(albums.count): \(albums[i].title)"
            let found = await CoverFinder.search(artist: albums[i].searchArtist, album: albums[i].title)
            guard !Task.isCancelled else { return }
            albums[i].candidates = found
            albums[i].choice = albums[i].bestMatch()
            albums[i].searched = true
            try? await Task.sleep(for: .seconds(1))
        }
        searching = false
    }

    private func save() async {
        guard let editor = app.tagEditor else { return }
        saving = true
        problems = []
        let chosen = albums.indices.filter { albums[$0].choice != nil }
        var saved = 0
        for (n, i) in chosen.enumerated() {
            guard let candidate = albums[i].candidates.first(where: { $0.id == albums[i].choice }) else { continue }
            progress = "Saving \(n + 1) of \(chosen.count): \(albums[i].title)"
            guard let image = await CoverFinder.download(candidate) else {
                problems.append("\(albums[i].title): couldn't download the cover.")
                continue
            }
            do {
                try await editor.setCover(image, on: albums[i].tracks)
                albums[i].saved = true
                saved += 1
            } catch {
                problems.append("\(albums[i].title): \(error.localizedDescription)")
            }
        }
        saving = false
        savedCount = saved
    }
}

/// An album from the list, with the covers found for it.
struct AlbumCovers: Identifiable {
    let id: String               // albumKey
    let title: String
    let artist: String
    let artworkId: Int64?
    let tracks: [Track]
    var candidates: [CoverCandidate] = []
    var choice: UUID?
    var searched = false
    var saved = false

    /// Album artist for the search; left out for compilations ("Various Artists" matches nothing useful).
    var searchArtist: String {
        let various = ["various artists", "various", "va"]
        return various.contains(artist.lowercased()) ? "" : artist
    }

    /// Pre-picks a cover only when its album title matches, so nothing wrong gets saved by accident.
    func bestMatch() -> UUID? {
        let norm = CoverFinder.norm
        let want = norm(title)
        guard !want.isEmpty else { return nil }
        return (candidates.first { norm($0.album) == want }
            ?? candidates.first { norm($0.album).hasPrefix(want) || want.hasPrefix(norm($0.album)) })?.id
    }

    static func group(_ tracks: [Track]) -> [AlbumCovers] {
        var order: [String] = []
        var byKey: [String: [Track]] = [:]
        for t in tracks {
            if byKey[t.albumKey] == nil { order.append(t.albumKey) }
            byKey[t.albumKey, default: []].append(t)
        }
        return order.map { key in
            let list = byKey[key]!
            return AlbumCovers(id: key, title: list[0].displayAlbum, artist: list[0].displayAlbumArtist,
                               artworkId: list.first { $0.artworkId != nil }?.artworkId, tracks: list)
        }
    }
}

private struct AlbumCoverRow: View {
    @Binding var album: AlbumCovers
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                ArtworkView(artworkId: album.artworkId, pixelSize: 160, cornerRadius: 4)
                    .frame(width: 64, height: 64)
                Text(album.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text(album.artist).font(.system(size: 11)).foregroundStyle(theme.textSecondary).lineLimit(1)
                Text("\(album.tracks.count) song\(album.tracks.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(theme.textTertiary)
                if album.saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.accent)
                }
            }
            .frame(width: 170, alignment: .leading)

            if !album.searched {
                Text("Searching…").font(.system(size: 12)).foregroundStyle(theme.textTertiary)
                    .frame(height: 120)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        noneTile
                        ForEach(album.candidates) { c in candidateTile(c) }
                    }
                    .padding(.vertical, 2)
                }
                if album.candidates.isEmpty {
                    Text("No covers found online for this album.")
                        .font(.system(size: 12)).foregroundStyle(theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .opacity(album.saved ? 0.6 : 1)
    }

    private var noneTile: some View {
        let selected = album.choice == nil
        return Button { album.choice = nil } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4).fill(theme.surface)
                    .overlay(Text("None").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.textSecondary))
                    .frame(width: 110, height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? theme.accent : .clear, lineWidth: 3))
                Text("Leave as is").font(.system(size: 10)).foregroundStyle(theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .disabled(album.saved)
    }

    private func candidateTile(_ c: CoverCandidate) -> some View {
        let selected = album.choice == c.id
        return Button { album.choice = c.id } label: {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let image = NSImage(data: c.thumbnail) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        theme.surface
                    }
                }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? theme.accent : .clear, lineWidth: 3))
                Text(c.album).font(.system(size: 10, weight: .medium)).lineLimit(1)
                Text([c.artist, c.year].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(theme.textSecondary).lineLimit(1)
                Text(c.source).font(.system(size: 9)).foregroundStyle(theme.textTertiary)
            }
            .frame(width: 110)
        }
        .buttonStyle(.plain)
        .help("\(c.album)\n\(c.artist) \(c.year)\nfrom \(c.source)")
        .disabled(album.saved)
    }
}
