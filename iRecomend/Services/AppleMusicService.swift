import Foundation
import MusicKit

// MARK: - Raw API response types (must be defined before the actor to avoid isolation inference)

private struct RawTracksResponse: Decodable {
    let data: [RawTrackItem]
}

private struct RawTrackItem: Decodable {
    let id: String
    let attributes: Attributes?
    let relationships: Relationships?

    struct Attributes: Decodable {
        let name: String
        let artistName: String
        let genreNames: [String]?
        let previews: [Preview]?
        let artwork: ArtworkData?

        struct Preview: Decodable {
            let url: URL?
        }

        struct ArtworkData: Decodable {
            // Template URL e.g. "https://…/{w}x{h}bb.jpg"
            let url: String?
        }
    }

    struct Relationships: Decodable {
        let catalog: CatalogRelationship?

        struct CatalogRelationship: Decodable {
            let data: [CatalogSong]?

            struct CatalogSong: Decodable {
                let attributes: CatalogAttributes?

                struct CatalogAttributes: Decodable {
                    let genreNames: [String]?
                }
            }
        }
    }
}

private func makeRecommendedTrack(from item: RawTrackItem) -> RecommendedTrack? {
    guard let attrs = item.attributes, !attrs.name.isEmpty else { return nil }

    let artworkURL: URL? = attrs.artwork?.url.flatMap { template in
        URL(string: template
            .replacingOccurrences(of: "{w}", with: "500")
            .replacingOccurrences(of: "{h}", with: "500"))
    }

    return RecommendedTrack(
        id: item.id,
        title: attrs.name,
        artistName: attrs.artistName,
        previewURL: attrs.previews?.first?.url,
        artworkURL: artworkURL,
        genreNames: attrs.genreNames ?? []
    )
}

// MARK: -

@available(iOS 16.0, macOS 14.0, *)
actor AppleMusicService {
    func requestAuthorization() async throws {
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            throw MusicServiceError.notAuthorized
        }
    }

    func fetchLibraryPlaylists(limit: Int = 25) async throws -> [PlaylistModel] {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = limit

        let response = try await request.response()
        return response.items.map { playlist in
            PlaylistModel(
                id: playlist.id.rawValue,
                name: playlist.name,
                genreHints: Self.extractGenreHints(from: playlist.name)
            )
        }
    }

    func fetchTracks(for playlistID: String) async throws -> [RecommendedTrack] {
        #if os(macOS)
        return try await fetchTracksMacOS(playlistID: playlistID)
        #else
        let countryCode = try await MusicDataRequest.currentCountryCode

        // Catalog endpoint returns genreNames directly in song attributes.
        // Works for Apple Music playlists saved to library. Falls back to the
        // library endpoint (with catalog relationship) for user-created playlists.
        if let tracks = try? await fetchTracksFromCatalog(playlistID: playlistID, countryCode: countryCode),
           !tracks.isEmpty {
            return tracks
        }
        return try await fetchTracksFromLibrary(playlistID: playlistID)
        #endif
    }

    #if os(macOS)
    private func fetchTracksMacOS(playlistID: String) async throws -> [RecommendedTrack] {
        // On macOS, raw library playlist IDs are internal database IDs that the HTTP API
        // does not accept. Use MusicKit's typed API which resolves IDs correctly.
        var playlistRequest = MusicLibraryRequest<Playlist>()
        playlistRequest.filter(matching: \.id, equalTo: MusicItemID(rawValue: playlistID))
        let playlistResponse = try await playlistRequest.response()

        guard let playlist = playlistResponse.items.first else { return [] }
        let detailed = try await playlist.with([.tracks])
        guard let tracks = detailed.tracks else { return [] }

        let songs = tracks.compactMap { track -> Song? in
            guard case .song(let song) = track else { return nil }
            return song
        }

        // Fetch genres in batches of 5 to avoid overwhelming the network (which caused timeouts
        // when all songs were requested concurrently).
        var results: [RecommendedTrack] = []
        let batchSize = 5
        for batchStart in stride(from: 0, to: songs.count, by: batchSize) {
            let batch = songs[batchStart..<min(batchStart + batchSize, songs.count)]
            let batchTracks = await withTaskGroup(of: RecommendedTrack?.self) { group in
                for song in batch {
                    group.addTask {
                        var genreNames = Array(song.genreNames)
                        if genreNames.isEmpty,
                           let enriched = try? await song.with([.genres]),
                           let genres = enriched.genres {
                            genreNames = genres.map { $0.name }
                        }
                        return RecommendedTrack(
                            id: song.id.rawValue,
                            title: song.title,
                            artistName: song.artistName,
                            previewURL: song.previewAssets?.first?.url,
                            artworkURL: song.artwork?.url(width: 500, height: 500),
                            genreNames: genreNames,
                            musicKitArtwork: song.artwork
                        )
                    }
                }
                var batch: [RecommendedTrack] = []
                for await result in group {
                    if let result { batch.append(result) }
                }
                return batch
            }
            results.append(contentsOf: batchTracks)
        }
        return results
    }
    #endif

    #if !os(macOS)
    private func fetchTracksFromCatalog(playlistID: String, countryCode: String) async throws -> [RecommendedTrack] {
        guard let url = URL(string: "https://api.music.apple.com/v1/catalog/\(countryCode)/playlists/\(playlistID)/tracks?limit=100") else {
            return []
        }
        let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
        let decoded = try JSONDecoder().decode(RawTracksResponse.self, from: response.data)
        return decoded.data.compactMap { makeRecommendedTrack(from: $0) }
    }

    private func fetchTracksFromLibrary(playlistID: String) async throws -> [RecommendedTrack] {
        // First try with catalog relationship to get genreNames from catalog equivalent.
        // This fails (404) for playlists containing only local/non-catalog tracks, so fall back
        // to the simple endpoint in that case.
        if let tracks = try? await fetchLibraryTracksWithCatalog(playlistID: playlistID),
           !tracks.isEmpty {
            return tracks
        }
        return try await fetchLibraryTracksSimple(playlistID: playlistID)
    }

    private func fetchLibraryTracksWithCatalog(playlistID: String) async throws -> [RecommendedTrack] {
        guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(playlistID)/tracks?include[library-songs]=catalog&fields[songs]=name,artistName,genreNames,artwork,previews&limit=100") else {
            return []
        }
        let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
        let decoded = try JSONDecoder().decode(RawTracksResponse.self, from: response.data)
        return decoded.data.compactMap { item -> RecommendedTrack? in
            // Prefer catalog genre names; fall back to whatever the library item carries.
            let catalogGenres = item.relationships?.catalog?.data?.first?.attributes?.genreNames
            if let genres = catalogGenres, let attrs = item.attributes {
                let merged = RawTrackItem(
                    id: item.id,
                    attributes: RawTrackItem.Attributes(
                        name: attrs.name,
                        artistName: attrs.artistName,
                        genreNames: genres,
                        previews: attrs.previews,
                        artwork: attrs.artwork
                    ),
                    relationships: item.relationships
                )
                return makeRecommendedTrack(from: merged)
            }
            return makeRecommendedTrack(from: item)
        }
    }

    private func fetchLibraryTracksSimple(playlistID: String) async throws -> [RecommendedTrack] {
        guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(playlistID)/tracks?limit=100") else {
            return []
        }
        let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
        let decoded = try JSONDecoder().decode(RawTracksResponse.self, from: response.data)
        return decoded.data.compactMap { makeRecommendedTrack(from: $0) }
    }
    #endif

    func fetchRecommendations(from playlists: [PlaylistModel], limit: Int = 20) async throws -> [RecommendedTrack] {
        let genreTerms = Array(Set(playlists.flatMap { $0.genreHints })).prefix(3)
        let searchTerm = genreTerms.isEmpty ? "pop" : genreTerms.joined(separator: " ")

        var searchRequest = MusicCatalogSearchRequest(term: searchTerm, types: [Song.self])
        searchRequest.limit = limit

        let response = try await searchRequest.response()
        return response.songs.compactMap { song in
            RecommendedTrack(
                id: song.id.rawValue,
                title: song.title,
                artistName: song.artistName,
                previewURL: song.previewAssets?.first?.url,
                artworkURL: song.artwork?.url(width: 500, height: 500),
                genreNames: Array(song.genreNames)
            )
        }
    }

    func fetchGenreRecommendations(
        for track: RecommendedTrack,
        excludingIDs: Set<String>,
        excludingTitles: Set<String>
    ) async throws -> [RecommendedTrack] {
        // On macOS, genres aren't loaded upfront. Fetch them lazily for this one track.
        #if os(macOS)
        var resolvedGenreNames = track.genreNames
        if resolvedGenreNames.isEmpty,
           let song = try? await { () -> Song? in
               var req = MusicLibraryRequest<Song>()
               req.filter(matching: \.id, equalTo: MusicItemID(rawValue: track.id))
               let resp = try await req.response()
               guard let s = resp.items.first else { return nil }
               let enriched = try await s.with([.genres])
               return enriched
           }(),
           let genres = song.genres {
            resolvedGenreNames = genres.map { $0.name }
        }
        let genreTerm = Self.searchTerm(for: resolvedGenreNames)
        #else
        // Use all genre names for a richer search term so results skew toward the track's style
        let genreTerm = Self.searchTerm(for: track.genreNames)
        #endif

        // Two concurrent API calls: one by genre, one by artist
        var genreRequest = MusicCatalogSearchRequest(term: genreTerm, types: [Song.self])
        genreRequest.limit = 25

        var artistRequest = MusicCatalogSearchRequest(term: track.artistName, types: [Song.self])
        artistRequest.limit = 25

        async let genreResponse = genreRequest.response()
        async let artistResponse = artistRequest.response()
        let (genreResult, artistResult) = try await (genreResponse, artistResponse)

        let sourceTitle = track.title.lowercased()

        // 2 songs from the same artist — exclude source track, used IDs, and used titles
        var chosenTitles = excludingTitles.union([sourceTitle])
        var artistPicks: [Song] = []
        for song in artistResult.songs {
            guard artistPicks.count < 2 else { break }
            let t = song.title.lowercased()
            guard song.id.rawValue != track.id,
                  !excludingIDs.contains(song.id.rawValue),
                  !chosenTitles.contains(t) else { continue }
            artistPicks.append(song)
            chosenTitles.insert(t)
        }

        // 8 songs from genre — different artist, scored by genre overlap for closest similarity
        let artistPickIDs = Set(artistPicks.map { $0.id.rawValue })
        let sourceGenres = Set(track.genreNames.map { $0.lowercased() })

        // Filter candidates then rank by how many genres they share with the source track
        let genreCandidates = genreResult.songs
            .filter { song in
                song.id.rawValue != track.id &&
                song.artistName != track.artistName &&
                !excludingIDs.contains(song.id.rawValue) &&
                !artistPickIDs.contains(song.id.rawValue) &&
                !chosenTitles.contains(song.title.lowercased())
            }
            .sorted { a, b in
                let aOverlap = Set(a.genreNames.map { $0.lowercased() }).intersection(sourceGenres).count
                let bOverlap = Set(b.genreNames.map { $0.lowercased() }).intersection(sourceGenres).count
                return aOverlap > bOverlap
            }

        var genrePicks: [Song] = []
        for song in genreCandidates {
            guard genrePicks.count < 8 else { break }
            let t = song.title.lowercased()
            guard !chosenTitles.contains(t) else { continue }
            genrePicks.append(song)
            chosenTitles.insert(t)
        }

        return (artistPicks + genrePicks).map { song in
            RecommendedTrack(
                id: song.id.rawValue,
                title: song.title,
                artistName: song.artistName,
                previewURL: song.previewAssets?.first?.url,
                artworkURL: song.artwork?.url(width: 300, height: 300),
                genreNames: Array(song.genreNames)
            )
        }
    }

    /// Converts genre names into a catalog search term, substituting vague genres with
    /// more specific queries that return better results.
    private static func searchTerm(for genreNames: [String]) -> String {
        let genreMap: [String: String] = [:]
        let terms = genreNames.map { name -> String in
            genreMap[name.lowercased()] ?? name
        }
        return terms.isEmpty ? "pop" : terms.joined(separator: " ")
    }

    private static func extractGenreHints(from text: String) -> [String] {
        let knownGenres = ["pop", "hip-hop", "rap", "r&b", "rock", "country", "electronic", "dance", "jazz", "classical", "indie"]
        let lowercased = text.lowercased()

        return knownGenres.filter { lowercased.contains($0) }
    }
}

enum MusicServiceError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Apple Music access is required to continue."
        }
    }
}
