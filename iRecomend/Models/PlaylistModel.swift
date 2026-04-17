import Foundation

struct PlaylistModel: Identifiable, Hashable {
    let id: String              // MusicKit ID — used for fetching tracks
    let addToPlaylistID: String // HTTP library ID — used for adding tracks via API
    let name: String
    let genreHints: [String]
}
