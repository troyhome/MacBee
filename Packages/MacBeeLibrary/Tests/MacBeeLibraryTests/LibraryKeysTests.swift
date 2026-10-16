import XCTest
@testable import MacBeeLibrary

final class LibraryKeysTests: XCTestCase {
    func testNormalizeMergesCaseAccentsAndSpaces() {
        XCTAssertEqual(LibraryKeys.normalize("Björk"), LibraryKeys.normalize("bjork "))
        XCTAssertEqual(LibraryKeys.normalize("Beady  Eye"), "beady eye")
    }

    func testAlbumArtistFallbacks() {
        XCTAssertEqual(LibraryKeys.albumArtist(albumArtist: "Björk", artist: "Björk feat. Antony", isCompilation: false), "Björk")
        XCTAssertEqual(LibraryKeys.albumArtist(albumArtist: nil, artist: "Beady Eye", isCompilation: false), "Beady Eye")
        XCTAssertEqual(LibraryKeys.albumArtist(albumArtist: nil, artist: "Someone", isCompilation: true), "Various Artists")
        XCTAssertEqual(LibraryKeys.albumArtist(albumArtist: "  ", artist: nil, isCompilation: false), "Unknown Artist")
    }

    func testAlbumTitleFallsBackToFolderName() {
        let url = URL(fileURLWithPath: "/Volumes/Music/Björk/2007 - Volta [vinyl]/04 Innocence.flac")
        XCTAssertEqual(LibraryKeys.albumTitle(album: nil, fileURL: url), "2007 - Volta [vinyl]")
        XCTAssertEqual(LibraryKeys.albumTitle(album: "Volta", fileURL: url), "Volta")
    }

    func testYearParsing() {
        XCTAssertEqual(LibraryKeys.year(from: "2007-05-01"), 2007)
        XCTAssertEqual(LibraryKeys.year(from: "c. 1999"), 1999)
        XCTAssertNil(LibraryKeys.year(from: "unknown"))
        XCTAssertNil(LibraryKeys.year(from: nil))
    }

    func testCoverFileChoice() {
        XCTAssertEqual(LibraryKeys.bestCoverFile(in: ["back.jpg", "Folder.JPG", "cover.png"]), "cover.png")
        XCTAssertEqual(LibraryKeys.bestCoverFile(in: ["back.jpg", "Folder.JPG"]), "Folder.JPG")
        XCTAssertNil(LibraryKeys.bestCoverFile(in: ["back.jpg", "notes.txt", "._cover.jpg"]))
    }

    func testCodecNames() {
        XCTAssertEqual(MetadataReader.codecName(pathExtension: "m4a", formatName: "Apple Lossless"), "ALAC")
        XCTAssertEqual(MetadataReader.codecName(pathExtension: "m4a", formatName: "AAC"), "AAC")
        XCTAssertEqual(MetadataReader.codecName(pathExtension: "FLAC", formatName: nil), "FLAC")
    }
}
