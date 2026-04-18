import SwiftUI
#if os(macOS)
import MusicKit
#endif

@available(macOS 14.0, *)
struct PlaylistTracksView: View {
    let playlist: PlaylistModel
    @ObservedObject var viewModel: RecommendationViewModel

    @State private var visibleCards: Set<String> = []
    @State private var currentIndex = 0
    @State private var trackToAdd: RecommendedTrack? = nil

    private var currentTrack: RecommendedTrack? {
        guard viewModel.playlistTracks.indices.contains(currentIndex) else { return nil }
        return viewModel.playlistTracks[currentIndex]
    }

    var body: some View {
        ZStack {
            Theme.bodyBackground.ignoresSafeArea()

            #if os(macOS)
            if let artwork = currentTrack?.musicKitArtwork,
               let trackID = currentTrack?.id {
                ArtworkImage(artwork, width: 900, height: 900)
                    .ignoresSafeArea()
                    .blur(radius: 40)
                    .overlay(Color.black.opacity(0.45).ignoresSafeArea())
                    .id(trackID)
                    .animation(Animation.easeInOut(duration: 0.4), value: trackID)
            }
            #endif

            Group {
                if viewModel.isLoadingTracks {
                    ProgressView("Loading tracks…")
                } else if viewModel.playlistTracks.isEmpty {
                    Text("No tracks found.")
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            cardSlider
                            recommendationsSection
                        }
                    }
                }
            }
        }
        .navigationTitle(playlist.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if viewModel.playingTrackID != nil {
                    Button("Stop") { viewModel.stopPreview() }
                        .foregroundColor(Theme.cardGradientStart)
                }
            }
        }
        .sheet(item: $trackToAdd) { track in
            PlaylistPickerView(track: track, currentPlaylistID: playlist.id, viewModel: viewModel)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #else
                .frame(minWidth: 380, minHeight: 400)
                #endif
        }
        .task {
            await viewModel.loadPlaylistTracks(for: playlist)
        }
        // Once tracks finish loading, trigger recommendations for whichever card is visible.
        // This avoids the race where .task(id: currentIndex) fires before playlistTracks is populated.
        .onChange(of: viewModel.isLoadingTracks) { isLoading in
            if !isLoading, let track = currentTrack {
                Task { await viewModel.loadGenreRecommendations(for: track) }
            }
        }
        // Load recommendations whenever the user swipes to a new card
        .task(id: currentIndex) {
            if let track = currentTrack {
                await viewModel.loadGenreRecommendations(for: track)
            }
        }
    }

    // MARK: - Card Slider

    private var cardSlider: some View {
        VStack(spacing: 16) {
            Text("\(currentIndex + 1) / \(viewModel.playlistTracks.count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            #if os(macOS)
            macOSCardSlider
            #else
            TabView(selection: $currentIndex) {
                ForEach(Array(viewModel.playlistTracks.enumerated()), id: \.element.id) { index, track in
                    TrackCard(
                        track: track,
                        isVisible: visibleCards.contains(track.id),
                        onAdd: { trackToAdd = track }
                    )
                    .padding(.horizontal, 24)
                    .tag(index)
                    .onAppear {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.06)) {
                            _ = visibleCards.insert(track.id)
                        }
                    }
                }
            }
            .pageTabViewStyleIfAvailable()
            .frame(height: 340)
            #endif

            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<min(viewModel.playlistTracks.count, 10), id: \.self) { i in
                    Circle()
                        .fill(i == currentIndex % 10 ? Theme.cardGradientStart : Color.gray.opacity(0.4))
                        .frame(width: i == currentIndex % 10 ? 10 : 6,
                               height: i == currentIndex % 10 ? 10 : 6)
                        .animation(.spring(response: 0.3), value: currentIndex)
                }
            }
        }
        .padding(.vertical, 20)
    }

    #if os(macOS)
    private var macOSCardSlider: some View {
        ZStack {
            if let track = currentTrack {
                TrackCard(
                    track: track,
                    isVisible: visibleCards.contains(track.id),
                    onAdd: { trackToAdd = track }
                )
                .frame(maxWidth: 400)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        _ = visibleCards.insert(track.id)
                    }
                }
                .onChange(of: currentIndex) { _ in
                    if let t = currentTrack {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                            _ = visibleCards.insert(t.id)
                        }
                    }
                }
            }

            HStack {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(currentIndex > 0 ? Theme.cardGradientStart : Color.gray.opacity(0.6))
                    .shadow(radius: 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard currentIndex > 0 else { return }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            currentIndex -= 1
                        }
                    }

                Spacer()

                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(currentIndex < viewModel.playlistTracks.count - 1 ? Theme.cardGradientStart : Color.gray.opacity(0.6))
                    .shadow(radius: 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard currentIndex < viewModel.playlistTracks.count - 1 else { return }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            currentIndex += 1
                        }
                    }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 340)
        .frame(maxWidth: 480)
        .padding(.horizontal, 24)
    }
    #endif

    // MARK: - Genre Recommendations

    @ViewBuilder
    private var recommendationsSection: some View {
        if let track = currentTrack {
            VStack(alignment: .leading, spacing: 14) {
                let genre = track.genreNames.sorted().first ?? "Similar Music"
                let recs = viewModel.trackRecommendations[track.id]
                let isLoading = viewModel.loadingRecommendationsFor.contains(track.id)

                // Section header
                let pageIdx = viewModel.recommendationPageIndex[track.id] ?? 0
                let totalPages = (viewModel.recommendationHistory(for: track.id))
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Because you're listening to")
                            .font(.system(size: 13))
                            #if os(macOS)
                            .foregroundColor(.white.opacity(0.7))
                            #else
                            .foregroundColor(.secondary)
                            #endif
                        Text("Genre: \"\(genre)\" ")
                            .font(.system(size: 20, weight: .bold))
                            #if os(macOS)
                            .foregroundColor(.white)
                            #else
                            .foregroundColor(.primary)
                            #endif
                        if totalPages > 1 {
                            Text("Page \(pageIdx + 1) of \(totalPages)")
                                .font(.system(size: 12))
                                #if os(macOS)
                                .foregroundColor(.white.opacity(0.6))
                                #else
                                .foregroundColor(.secondary)
                                #endif
                        }
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            viewModel.goBackInHistory(for: track)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(viewModel.canGoBack(for: track) ? Theme.cardGradientStart : Color.gray.opacity(0.3))
                                .padding(10)
                                .background(Theme.cardGradientStart.opacity(viewModel.canGoBack(for: track) ? 0.12 : 0.05))
                                .clipShape(Circle())
                        }
                        .disabled(!viewModel.canGoBack(for: track))

                        Button {
                            viewModel.goForwardInHistory(for: track)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(viewModel.canGoForward(for: track) ? Theme.cardGradientStart : Color.gray.opacity(0.3))
                                .padding(10)
                                .background(Theme.cardGradientStart.opacity(viewModel.canGoForward(for: track) ? 0.12 : 0.05))
                                .clipShape(Circle())
                        }
                        .disabled(!viewModel.canGoForward(for: track))

                        Button {
                            Task { await viewModel.refreshRecommendations(for: track) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(Theme.cardGradientStart)
                                .padding(10)
                                .background(Theme.cardGradientStart.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .disabled(isLoading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if let recs, recs.isEmpty {
                    Text("No recommendations found.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if let recs {
                    VStack(spacing: 12) {
                        ForEach(recs) { rec in
                            RecommendationRow(
                                track: rec,
                                isPlaying: viewModel.playingTrackID == rec.id,
                                onPlay: { viewModel.playPreview(for: rec) },
                                onAdd: { trackToAdd = rec }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 32)
            .id(track.id) // force redraw when track changes
        }
    }
}

// MARK: - Track Card (artwork background with frosted panel)

private struct TrackCard: View {
    let track: RecommendedTrack
    let isVisible: Bool
    let onAdd: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            #if os(macOS)
            if let artwork = track.musicKitArtwork {
                ArtworkImage(artwork, width: 500, height: 500)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if let url = track.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        LinearGradient(
                            colors: [Theme.cardGradientStart, Theme.cardGradientEnd],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                LinearGradient(
                    colors: [Theme.cardGradientStart, Theme.cardGradientEnd],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #else
            AsyncImage(url: track.artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    LinearGradient(
                        colors: [Theme.cardGradientStart, Theme.cardGradientEnd],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            #endif

            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(track.artistName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
        .offset(y: isVisible ? 0 : 40)
        .opacity(isVisible ? 1 : 0)
    }
}

// MARK: - Recommendation Row

private struct RecommendationRow: View {
    let track: RecommendedTrack
    let isPlaying: Bool
    let onPlay: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Small artwork thumbnail
            AsyncImage(url: track.artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    LinearGradient(
                        colors: [Theme.cardGradientStart, Theme.cardGradientEnd],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                if track.previewURL != nil {
                    Button(action: onPlay) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(
                                LinearGradient(
                                    colors: [Theme.cardGradientStart, Theme.cardGradientEnd],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .clipShape(Circle())
                    }
                }
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.cardGradientStart)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.rowBackground.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Playlist Picker Sheet

@available(macOS 14.0, *)
private struct PlaylistPickerView: View {
    let track: RecommendedTrack
    let currentPlaylistID: String
    @ObservedObject var viewModel: RecommendationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var adding = false
    @State private var resultMessage: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let message = resultMessage {
                    let succeeded = message == "Added!"
                    VStack(spacing: 16) {
                        Image(systemName: succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 52))
                            .foregroundColor(succeeded ? .green : .red)
                        Text(message)
                            .font(.system(size: 20, weight: .semibold))
                        if !succeeded {
                            Button("Close") { dismiss() }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                                .background(Theme.cardGradientStart)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if adding {
                    ProgressView("Adding…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.playlists) { playlist in
                        Button {
                            Task {
                                adding = true
                                let success = await viewModel.addTrack(track, toPlaylist: playlist, currentPlaylistID: currentPlaylistID)
                                resultMessage = success ? "Added!" : "Addition to playlist failed."
                                adding = false
                                if success {
                                    try? await Task.sleep(nanoseconds: 900_000_000)
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "music.note.list")
                                    .foregroundColor(Theme.cardGradientStart)
                                Text(playlist.name)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add \"\(track.title)\" to…")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
    }
}
