import Foundation
import MusicKit

// MARK: - Raw API response types (must be defined before the actor to avoid isolation inference)

private struct RawTracksResponse: Decodable {
    let data: [RawTrackItem]
}

private struct RawLibraryPlaylistsResponse: Decodable {
    let data: [Item]
    struct Item: Decodable {
        let id: String
        let attributes: Attributes?
        struct Attributes: Decodable {
            let name: String
            let artwork: ArtworkData?
            struct ArtworkData: Decodable {
                // Template URL e.g. "https://…/{w}x{h}bb.jpg"
                let url: String?
            }
        }
    }
}

private struct RawCatalogSearchResponse: Decodable {
    let results: Results
    struct Results: Decodable {
        let songs: SongsContainer?
        struct SongsContainer: Decodable {
            let data: [RawTrackItem]
        }
    }
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

    func fetchLibraryPlaylists(limit: Int = 100) async throws -> [PlaylistModel] {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = limit
        let response = try await request.response()

        #if os(macOS)
        // On macOS the MusicKit IDs are local DB IDs that don't work with the HTTP API.
        // Fetch HTTP library IDs and artwork URLs separately and match by name.
        let httpInfos = (try? await fetchLibraryPlaylistHTTPIDs(limit: limit)) ?? [:]
        let musicKitPlaylists = response.items.map { playlist -> PlaylistModel in
            let info = httpInfos[playlist.name]
            // Prefer the HTTP API artwork URL; fall back to MusicKit artwork if absent.
            let artworkURL = info?.artworkURL ?? playlist.artwork?.url(width: 500, height: 500)
            return PlaylistModel(
                id: playlist.id.rawValue,
                addToPlaylistID: info?.id ?? playlist.id.rawValue,
                name: playlist.name,
                artworkURL: artworkURL,
                genreHints: Self.extractGenreHints(from: playlist.name)
            )
        }
        // Append any HTTP-only playlists (e.g. "Purchased Music") that MusicKit omits on macOS.
        let musicKitNames = Set(response.items.map { $0.name })
        let httpOnlyPlaylists = httpInfos
            .filter { !musicKitNames.contains($0.key) }
            .map { name, info in
                PlaylistModel(
                    id: info.id,
                    addToPlaylistID: info.id,
                    name: name,
                    artworkURL: info.artworkURL,
                    genreHints: Self.extractGenreHints(from: name)
                )
            }
            .sorted { $0.name < $1.name }
        return musicKitPlaylists + httpOnlyPlaylists
        #else
        return response.items.map { playlist in
            PlaylistModel(
                id: playlist.id.rawValue,
                addToPlaylistID: playlist.id.rawValue,
                name: playlist.name,
                artworkURL: playlist.artwork?.url(width: 500, height: 500),
                genreHints: Self.extractGenreHints(from: playlist.name)
            )
        }
        #endif
    }

    #if os(macOS)
    private struct PlaylistHTTPInfo {
        let id: String
        let artworkURL: URL?
    }

    /// Returns a name → PlaylistHTTPInfo map (HTTP library ID + artwork URL) using the raw /me/library/playlists endpoint.
    private func fetchLibraryPlaylistHTTPIDs(limit: Int) async throws -> [String: PlaylistHTTPInfo] {
        guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists?limit=\(limit)") else {
            return [:]
        }
        let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
        let decoded = try JSONDecoder().decode(RawLibraryPlaylistsResponse.self, from: response.data)
        var result: [String: PlaylistHTTPInfo] = [:]
        for item in decoded.data {
            guard let name = item.attributes?.name, !name.isEmpty, result[name] == nil else { continue }
            let artworkURL = item.attributes?.artwork?.url.flatMap { template in
                URL(string: template
                    .replacingOccurrences(of: "{w}", with: "500")
                    .replacingOccurrences(of: "{h}", with: "500"))
            }
            result[name] = PlaylistHTTPInfo(id: item.id, artworkURL: artworkURL)
        }
        return result
    }
    #endif

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

        guard let playlist = playlistResponse.items.first else {
            // MusicKit doesn't know this playlist (e.g. "Purchased Music" — a system playlist
            // that the typed API omits on macOS). Fall back to the HTTP library tracks endpoint.
            return try await fetchLibraryTracksHTTP(playlistID: playlistID)
        }
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

    /// HTTP library tracks fallback for system playlists (e.g. "Purchased Music") that
    /// MusicKit's typed API doesn't return on macOS. These playlists have valid HTTP library IDs.
    private func fetchLibraryTracksHTTP(playlistID: String) async throws -> [RecommendedTrack] {
        guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(playlistID)/tracks?limit=100") else {
            return []
        }
        let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
        let decoded = try JSONDecoder().decode(RawTracksResponse.self, from: response.data)
        return decoded.data.compactMap { makeRecommendedTrack(from: $0) }
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
        excludingTitles: Set<String>,
        page: Int = 0
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

        // Fetch primary (genre + artist) and 2 random international storefronts concurrently
        let pageSize = 25
        let intlOffset = (page % 4) * pageSize
        let intlStorefronts = Array(Self.alternativeStorefronts.shuffled().prefix(2))

        var genreRequest = MusicCatalogSearchRequest(term: genreTerm, types: [Song.self])
        genreRequest.limit = pageSize
        genreRequest.offset = page * pageSize

        var artistRequest = MusicCatalogSearchRequest(term: track.artistName, types: [Song.self])
        artistRequest.limit = pageSize
        artistRequest.offset = page * pageSize

        let frozenGenreRequest = genreRequest
        let frozenArtistRequest = artistRequest
        async let genreResponse = frozenGenreRequest.response()
        async let artistResponse = frozenArtistRequest.response()
        async let intlTracks = withTaskGroup(of: [RecommendedTrack].self) { group in
            for storefront in intlStorefronts {
                group.addTask { await self.fetchRawFromStorefront(storefront: storefront, term: genreTerm, limit: pageSize, offset: intlOffset) }
            }
            var all: [RecommendedTrack] = []
            for await batch in group { all.append(contentsOf: batch) }
            return all
        }

        let (genreResult, artistResult, internationalTracks) = try await (genreResponse, artistResponse, intlTracks)

        let sourceTitle = track.title.lowercased()
        let sourceGenres = Set(track.genreNames.map { $0.lowercased() })

        // Artist picks: 2 from same artist (primary storefront only, shuffled)
        var chosenTitles = excludingTitles.union([sourceTitle])
        var artistPicks: [RecommendedTrack] = []
        for song in artistResult.songs.shuffled() {
            guard artistPicks.count < 2 else { break }
            let t = song.title.lowercased()
            guard song.id.rawValue != track.id,
                  !excludingIDs.contains(song.id.rawValue),
                  !chosenTitles.contains(t) else { continue }
            artistPicks.append(RecommendedTrack(
                id: song.id.rawValue, title: song.title, artistName: song.artistName,
                previewURL: song.previewAssets?.first?.url,
                artworkURL: song.artwork?.url(width: 300, height: 300),
                genreNames: Array(song.genreNames)
            ))
            chosenTitles.insert(t)
        }

        // Genre pool: merge primary + international, deduplicate, shuffle, then sort by overlap
        let primaryGenreTracks = genreResult.songs.map { song in
            RecommendedTrack(
                id: song.id.rawValue, title: song.title, artistName: song.artistName,
                previewURL: song.previewAssets?.first?.url,
                artworkURL: song.artwork?.url(width: 300, height: 300),
                genreNames: Array(song.genreNames)
            )
        }
        let artistPickIDs = Set(artistPicks.map { $0.id })
        var seenIDs = Set<String>()
        let genrePool = (primaryGenreTracks + internationalTracks)
            .filter { seenIDs.insert($0.id).inserted }
            .shuffled() // shuffle before sorting so equal-overlap entries are randomised
            .filter { rec in
                rec.id != track.id &&
                rec.artistName != track.artistName &&
                !excludingIDs.contains(rec.id) &&
                !artistPickIDs.contains(rec.id) &&
                !chosenTitles.contains(rec.title.lowercased())
            }
            .sorted { a, b in
                let aOverlap = Set(a.genreNames.map { $0.lowercased() }).intersection(sourceGenres).count
                let bOverlap = Set(b.genreNames.map { $0.lowercased() }).intersection(sourceGenres).count
                return aOverlap > bOverlap
            }

        var genrePicks: [RecommendedTrack] = []
        for rec in genrePool {
            guard genrePicks.count < 8 else { break }
            let t = rec.title.lowercased()
            guard !chosenTitles.contains(t) else { continue }
            genrePicks.append(rec)
            chosenTitles.insert(t)
        }

        let result = artistPicks + genrePicks
        if !result.isEmpty { return result }

        // All pools exhausted — broaden to remaining international storefronts
        return await fetchFromAlternativeStorefronts(
            term: genreTerm,
            excludingIDs: excludingIDs,
            page: page
        )
    }

    // Storefronts to try when the primary storefront is exhausted
    private static let alternativeStorefronts = [
        "gb", "au", "ca", "fr", "de", "jp", "br", "kr", "mx", "es",
        "it", "nl", "se", "no", "dk", "fi", "pt", "pl", "be", "at",
        "ch", "nz", "sg", "in", "id", "ph", "th", "my", "vn", "tw",
        "hk", "cn", "ru", "tr", "sa", "ae", "eg", "za", "ng", "ke",
        "ar", "cl", "co", "pe", "ve", "cz", "ro", "hu", "sk", "hr",
        "ua", "il", "pk", "bd", "lk", "gh", "tz", "et", "dz", "ma"
    ]

    func addTrack(catalogID: String, toPlaylistID playlistID: String) async throws {
        guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(playlistID)/tracks") else {
            throw MusicServiceError.invalidRequest
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["data": [["id": catalogID, "type": "songs"]]]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await MusicDataRequest(urlRequest: urlRequest).response()
    }

    private func fetchRawFromStorefront(storefront: String, term: String, limit: Int, offset: Int) async -> [RecommendedTrack] {
        let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
        guard let url = URL(string: "https://api.music.apple.com/v1/catalog/\(storefront)/search?term=\(encodedTerm)&types=songs&limit=\(limit)&offset=\(offset)") else { return [] }
        guard let response = try? await MusicDataRequest(urlRequest: URLRequest(url: url)).response(),
              let decoded = try? JSONDecoder().decode(RawCatalogSearchResponse.self, from: response.data) else { return [] }
        return decoded.results.songs?.data.compactMap { makeRecommendedTrack(from: $0) } ?? []
    }

    private func fetchFromAlternativeStorefronts(
        term: String,
        excludingIDs: Set<String>,
        page: Int
    ) async -> [RecommendedTrack] {
        let offset = (page % 4) * 25
        var results: [RecommendedTrack] = []
        for storefront in Self.alternativeStorefronts {
            guard results.count < 10 else { break }
            let tracks = await fetchRawFromStorefront(storefront: storefront, term: term, limit: 25, offset: offset)
            results.append(contentsOf: tracks.filter { !excludingIDs.contains($0.id) })
        }
        return Array(results.prefix(10))
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
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Apple Music access is required to continue."
        case .invalidRequest:
            return "Could not build the request."
        }
    }
}
