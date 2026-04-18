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
    @Published var musicAccessDenied = false
    @Published var playingTrackID: String?

    private var usedRecommendationIDs: Set<String> = []
    private var usedRecommendationTitles: Set<String> = []
    private var refreshCountByTrack: [String: Int] = [:]
    private var recommendationHistory: [String: [[RecommendedTrack]]] = [:]
    @Published var recommendationPageIndex: [String: Int] = [:]
    // Tracks added by the user that Apple Music hasn't synced back yet
    private var pendingAddedTracks: [String: [RecommendedTrack]] = [:]

    private let musicService = AppleMusicService()
    private var player: AVPlayer?
    private var playerObserver: Any?

    func connectAndLoad() async {
        isLoading = true
        errorMessage = nil

        do {
            try await musicService.requestAuthorization()
            musicAccessDenied = false
            playlists = try await musicService.fetchLibraryPlaylists()
            tracks = try await musicService.fetchRecommendations(from: playlists)
        } catch MusicServiceError.notAuthorized {
            musicAccessDenied = true
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
        refreshCountByTrack = [:]
        recommendationHistory = [:]
        recommendationPageIndex = [:]

        isLoadingTracks = true
        errorMessage = nil
        do {
            let fetched = try await musicService.fetchTracks(for: playlist.id)
            // Merge with any locally-added tracks not yet synced by Apple Music
            let pending = pendingAddedTracks[playlist.id] ?? []
            let pendingNew = pending.filter { p in !fetched.contains(where: { $0.id == p.id }) }
            playlistTracks = fetched + pendingNew
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingTracks = false
    }

    func refreshRecommendations(for track: RecommendedTrack) async {
        guard !loadingRecommendationsFor.contains(track.id) else { return }
        refreshCountByTrack[track.id, default: 0] += 1
        await fetchAndAppendRecommendations(for: track)
    }

    func loadGenreRecommendations(for track: RecommendedTrack) async {
        guard trackRecommendations[track.id] == nil,
              !loadingRecommendationsFor.contains(track.id) else { return }
        await fetchAndAppendRecommendations(for: track)
    }

    private func fetchAndAppendRecommendations(for track: RecommendedTrack) async {
        _ = loadingRecommendationsFor.insert(track.id)
        do {
            let page = refreshCountByTrack[track.id, default: 0]
            let recs = try await musicService.fetchGenreRecommendations(
                for: track,
                excludingIDs: usedRecommendationIDs,
                excludingTitles: usedRecommendationTitles,
                page: page
            )
            let history = recommendationHistory[track.id] ?? []
            recommendationHistory[track.id] = history + [recs]
            recommendationPageIndex[track.id] = history.count // index of new page
            trackRecommendations[track.id] = recs
            usedRecommendationIDs.formUnion(recs.map { $0.id })
            usedRecommendationTitles.formUnion(recs.map { $0.title.lowercased() })
        } catch {
            // Leave as nil on error so the refresh button can retry
        }
        loadingRecommendationsFor.remove(track.id)
    }

    func goBackInHistory(for track: RecommendedTrack) {
        guard let idx = recommendationPageIndex[track.id], idx > 0,
              let history = recommendationHistory[track.id] else { return }
        let newIdx = idx - 1
        recommendationPageIndex[track.id] = newIdx
        trackRecommendations[track.id] = history[newIdx]
    }

    func goForwardInHistory(for track: RecommendedTrack) {
        guard let idx = recommendationPageIndex[track.id],
              let history = recommendationHistory[track.id],
              idx < history.count - 1 else { return }
        let newIdx = idx + 1
        recommendationPageIndex[track.id] = newIdx
        trackRecommendations[track.id] = history[newIdx]
    }

    func recommendationHistory(for trackID: String) -> Int {
        recommendationHistory[trackID]?.count ?? 0
    }

    func canGoBack(for track: RecommendedTrack) -> Bool {
        (recommendationPageIndex[track.id] ?? 0) > 0
    }

    func canGoForward(for track: RecommendedTrack) -> Bool {
        guard let idx = recommendationPageIndex[track.id],
              let history = recommendationHistory[track.id] else { return false }
        return idx < history.count - 1
    }

    func addTrack(_ track: RecommendedTrack, toPlaylist targetPlaylist: PlaylistModel, currentPlaylistID: String? = nil) async -> Bool {
        do {
            try await musicService.addTrack(catalogID: track.id, toPlaylistID: targetPlaylist.addToPlaylistID)
            // If the user added to the playlist they're currently viewing, append immediately
            if targetPlaylist.id == currentPlaylistID,
               !playlistTracks.contains(where: { $0.id == track.id }) {
                playlistTracks.append(track)
                pendingAddedTracks[targetPlaylist.id, default: []].append(track)
            }
            return true
        } catch {
            return false
        }
    }

    func playPreview(for track: RecommendedTrack) {
        // Toggle off if already playing this track
        if playingTrackID == track.id {
            stopPreview()
            return
        }

        guard let previewURL = track.previewURL else { return }

        stopPreview()

        let item = AVPlayerItem(url: previewURL)
        player = AVPlayer(playerItem: item)

        // Auto-clear state when preview finishes
        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.playingTrackID = nil
                self?.player = nil
            }
        }

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        playingTrackID = track.id
        player?.play()
    }

    func stopPreview() {
        player?.pause()
        player = nil
        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
            playerObserver = nil
        }
        playingTrackID = nil
    }
}
