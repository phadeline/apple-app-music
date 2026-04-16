import Foundation

struct PlaylistModel: Identifiable, Hashable {
    let id: String
    let name: String
    let genreHints: [String]
}
