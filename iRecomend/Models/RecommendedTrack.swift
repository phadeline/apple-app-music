import Foundation
#if os(macOS)
import MusicKit
#endif

struct RecommendedTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let previewURL: URL?
    let artworkURL: URL?
    let genreNames: [String]
    #if os(macOS)
    var musicKitArtwork: Artwork?
    #endif
}
