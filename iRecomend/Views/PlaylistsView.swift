import SwiftUI

@available(macOS 14.0, *)
struct PlaylistsView: View {
    @ObservedObject var viewModel: RecommendationViewModel

    var body: some View {
        ZStack {
            Theme.bodyBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select A Playlist To View Recommended Songs")
                        .font(.system(size: 14, weight: .bold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top)

                    VStack(spacing: 20) {
                        ForEach(viewModel.playlists) { playlist in
                            NavigationLink(destination: PlaylistTracksView(playlist: playlist, viewModel: viewModel)) {
                                Group {
                                    if let artworkURL = playlist.artworkURL {
                                        AsyncImage(url: artworkURL) { phase in
                                            if let image = phase.image {
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                            } else {
                                                Theme.cardGradient
                                            }
                                        }
                                    } else {
                                        Theme.cardGradient
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .clipped()
                                .overlay(
                                    LinearGradient(
                                        colors: [.black.opacity(0.6), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(alignment: .topLeading) {
                                    Text(playlist.name)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                        .padding(24)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .contentShape(RoundedRectangle(cornerRadius: 20))
                                .playlistItemShadow()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Your Playlists")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
