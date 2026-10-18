import Foundation
import MacBeeVideo
import SwiftUI

/// How Movies, TV Shows and Music Videos are ordered (the sort menu next to the search box).
enum VideoSortField: String, CaseIterable, Identifiable {
    case title, year, dateAdded, genre, artist

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: "Title"
        case .year: "Year"
        case .dateAdded: "Date Added"
        case .genre: "Genre"
        case .artist: "Artist"
        }
    }

    /// The fields that make sense for a page. Music videos have no year or genre; they have an artist (folder).
    static func fields(for category: VideoCategory) -> [VideoSortField] {
        category == .musicVideos ? [.title, .artist, .dateAdded] : [.title, .year, .genre, .dateAdded]
    }
}

struct VideoSort: Equatable {
    var field: VideoSortField = .title
    var ascending = true

    /// Saved per page, e.g. "videoSort.movies" = "year.desc".
    static func load(for category: VideoCategory) -> VideoSort {
        let parts = (UserDefaults.standard.string(forKey: "videoSort.\(category.rawValue)") ?? "").split(separator: ".")
        guard let first = parts.first, let field = VideoSortField(rawValue: String(first)),
              VideoSortField.fields(for: category).contains(field) else { return VideoSort() }
        return VideoSort(field: field, ascending: parts.count < 2 || parts[1] != "desc")
    }

    func save(for category: VideoCategory) {
        UserDefaults.standard.set("\(field.rawValue).\(ascending ? "asc" : "desc")", forKey: "videoSort.\(category.rawValue)")
    }

    /// Sorts by the field, then by title. Missing years and genres go last either way.
    func apply(to titles: [VideoTitle]) -> [VideoTitle] {
        func name(_ t: VideoTitle) -> String { VideoScanner.sortKey(t.title) }
        func compare(_ a: VideoTitle, _ b: VideoTitle) -> Bool {
            switch field {
            case .title:
                return ordered(name(a), name(b))
            case .year:
                return orderedOptional(a.year, b.year) ?? (name(a) < name(b))
            case .dateAdded:
                return a.added == b.added ? name(a) < name(b) : ordered(a.added, b.added)
            case .genre:
                return orderedOptional(a.genres.first?.lowercased(), b.genres.first?.lowercased()) ?? (name(a) < name(b))
            case .artist:
                let x = a.artistName.lowercased(), y = b.artistName.lowercased()
                return x == y ? name(a) < name(b) : ordered(x, y)
            }
        }
        return titles.sorted(by: compare)
    }

    private func ordered<T: Comparable>(_ a: T, _ b: T) -> Bool { ascending ? a < b : a > b }

    /// nil when equal (fall back to title).
    private func orderedOptional<T: Comparable>(_ a: T?, _ b: T?) -> Bool? {
        switch (a, b) {
        case let (x?, y?): return x == y ? nil : ordered(x, y)
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return nil
        }
    }
}

extension VideoTitle {
    var year: Int? {
        switch self {
        case let .movie(movie): movie.year
        case let .show(show): show.year
        case .musicVideo: nil
        }
    }

    var artistName: String {
        if case let .musicVideo(video) = self { return video.folderName }
        return ""
    }
}

/// The round sort button with Sort By and Ascending / Descending, like the Apple TV app.
struct VideoSortMenu: View {
    let category: VideoCategory
    @Binding var sort: VideoSort

    var body: some View {
        Menu {
            Section("Sort By") {
                ForEach(VideoSortField.fields(for: category)) { field in
                    Toggle(field.label, isOn: Binding(get: { sort.field == field }, set: { if $0 { sort.field = field } }))
                }
            }
            Section {
                Toggle("Ascending", isOn: Binding(get: { sort.ascending }, set: { if $0 { sort.ascending = true } }))
                Toggle("Descending", isOn: Binding(get: { !sort.ascending }, set: { if $0 { sort.ascending = false } }))
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort")
    }
}
