/// How an artist's page is laid out: every album with its songs (the original), or TIDAL-style rows
/// (Albums, EPs & Singles, Mixes, Videos, Similar Artists).
enum ArtistLayout: String, CaseIterable, Identifiable {
    case albumsWithSongs, overview

    var id: String { rawValue }
    var title: String { self == .albumsWithSongs ? "Albums and songs" : "Overview (TIDAL style)" }
    var systemImage: String { self == .albumsWithSongs ? "list.bullet.below.rectangle" : "square.grid.3x2" }
}
