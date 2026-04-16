import Foundation
import AVFoundation
import Combine

@available(macOS 14.0, *)
@MainActor
final class RecommendationViewModel: ObservableObject {
    @Published var playlists: [PlaylistModel] = []
    @Published var tracks: [RecommendedTrack] = []
    @Published var playlistTracks: [RecommendedTrack] = []
    @Published var trackRecommendations: [String: [RecommendedTrack]] = [:]
    @Published var isLoading = false
    @Published var isLoadingTracks = false
    @Published var loadingRecommendationsFor: Set<String> = []
    @Published var errorMessage: String?

    private var usedRecommendationIDs: Set<String> = []
    private var usedRecommendationTitles: Set<String> = []

    private let musicService = AppleMusicService()
    private var player: AVPlayer?

    func connectAndLoad() async {
        isLoading = true
        errorMessage = nil

        do {
            try await musicService.requestAuthorization()
            playlists = try await musicService.fetchLibraryPlaylists()
            tracks = try await musicService.fetchRecommendations(from: playlists)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadPlaylistTracks(for playlist: PlaylistModel) async {
        // Reset all state so each visit starts fresh.
        // Clear playlistTracks immediately so currentTrack returns nil while loading,
        // preventing .task(id: currentIndex) from triggering stale recommendation fetches.
        playlistTracks = []
        trackRecommendations = [:]
        usedRecommendationIDs = []
        usedRecommendationTitles = []
        loadingRecommendationsFor = []

        isLoadingTracks = true
        errorMessage = nil
        do {
            playlistTracks = try await musicService.fetchTracks(for: playlist.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingTracks = false
    }

    func refreshRecommendations(for track: RecommendedTrack) async {
        trackRecommendations.removeValue(forKey: track.id)
        loadingRecommendationsFor.remove(track.id)
        await loadGenreRecommendations(for: track)
    }

    func loadGenreRecommendations(for track: RecommendedTrack) async {
        guard trackRecommendations[track.id] == nil,
              !loadingRecommendationsFor.contains(track.id) else { return }
        _ = loadingRecommendationsFor.insert(track.id)
        do {
            let recs = try await musicService.fetchGenreRecommendations(
                for: track,
                excludingIDs: usedRecommendationIDs,
                excludingTitles: usedRecommendationTitles
            )
            trackRecommendations[track.id] = recs
            usedRecommendationIDs.formUnion(recs.map { $0.id })
            usedRecommendationTitles.formUnion(recs.map { $0.title.lowercased() })
        } catch {
            // Leave as nil on error so the refresh button can retry
        }
        loadingRecommendationsFor.remove(track.id)
    }

    func playPreview(for track: RecommendedTrack) {
        guard let previewURL = track.previewURL else {
            return
        }

        player = AVPlayer(url: previewURL)
        player?.play()
    }

    func stopPreview() {
        player?.pause()
        player = nil
    }
}
