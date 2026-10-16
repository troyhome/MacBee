import MacBeeLibrary
import SwiftUI

/// Search, genre, years, format, rating, play count and favorites.
struct StudioFilterBar: View {
    @Binding var filter: TrackFilter
    let genres: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Search songs, artists, albums", text: $filter.text)
                    .textFieldStyle(.roundedBorder)
                Toggle("Favorites only", isOn: $filter.favoritesOnly)
                    .toggleStyle(.checkbox)
                    .fixedSize()
            }
            // Where the search text looks. Nothing ticked = everywhere.
            HStack(spacing: 14) {
                Text("Search in:")
                    .foregroundStyle(.secondary)
                ForEach(TrackFilter.SearchField.allCases) { field in
                    Toggle(field.title, isOn: Binding(
                        get: { filter.searchFields.contains(field) },
                        set: { on in
                            if on { filter.searchFields.insert(field) } else { filter.searchFields.remove(field) }
                        }))
                        .toggleStyle(.checkbox)
                }
                Text(filter.searchFields.isEmpty ? "(everything)" : "")
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Picker("Genre", selection: $filter.genre) {
                    Text("Any genre").tag(String?.none)
                    Divider()
                    ForEach(genres, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .labelsHidden()
                .frame(maxWidth: 160)

                HStack(spacing: 4) {
                    Text("Years")
                        .foregroundStyle(.secondary)
                    TextField("from", value: $filter.yearFrom, format: .number.grouping(.never))
                        .frame(width: 52)
                    Text("–")
                    TextField("to", value: $filter.yearTo, format: .number.grouping(.never))
                        .frame(width: 52)
                }
                .textFieldStyle(.roundedBorder)

                Picker("Format", selection: $filter.format) {
                    ForEach(TrackFilter.FormatFilter.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 150)

                Picker("Rating", selection: $filter.minimumStars) {
                    Text("Any rating").tag(Int?.none)
                    ForEach(1...5, id: \.self) { stars in
                        Text(String(repeating: "★", count: stars) + (stars < 5 ? " or more" : "")).tag(Optional(stars))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)

                Picker("Plays", selection: $filter.playCount) {
                    ForEach(TrackFilter.PlayCountFilter.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 170)

                Spacer(minLength: 0)
                if hasFilters {
                    Button("Clear") {
                        let source = filter.playlistId
                        filter = TrackFilter()
                        filter.playlistId = source // keep showing the same playlist's songs
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .font(.system(size: 12))
        .controlSize(.small)
    }

    private var hasFilters: Bool {
        var cleared = TrackFilter()
        cleared.playlistId = filter.playlistId
        return filter != cleared
    }
}
