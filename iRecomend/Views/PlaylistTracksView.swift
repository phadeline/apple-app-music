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
                if !viewModel.playlistTracks.isEmpty {
                    Button("Stop") { viewModel.stopPreview() }
                        .foregroundColor(Theme.cardGradientStart)
                }
            }
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
                        onPlay: { viewModel.playPreview(for: track) }
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
        HStack(spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    currentIndex = max(0, currentIndex - 1)
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(currentIndex > 0 ? Theme.cardGradientStart : Color.gray.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(currentIndex <= 0)

            if let track = currentTrack {
                TrackCard(
                    track: track,
                    isVisible: visibleCards.contains(track.id),
                    onPlay: { viewModel.playPreview(for: track) }
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

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    currentIndex = min(viewModel.playlistTracks.count - 1, currentIndex + 1)
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(currentIndex < viewModel.playlistTracks.count - 1 ? Theme.cardGradientStart : Color.gray.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= viewModel.playlistTracks.count - 1)
        }
        .frame(height: 340)
        .frame(maxWidth: .infinity)
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
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Because you're listening to")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Text("Genre: \"\(genre)\" ")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    Spacer()
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
                            RecommendationRow(track: rec, onPlay: { viewModel.playPreview(for: rec) })
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
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            #if os(macOS)
            if let artwork = track.musicKitArtwork {
                ArtworkImage(artwork, width: 500, height: 500)
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
                if track.previewURL != nil {
                    Button(action: onPlay) {
                        Label("Play Preview", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.25))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    }
                } else {
                    Text("No preview available")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
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
    let onPlay: () -> Void

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

            if track.previewURL != nil {
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.rowBackground.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}
