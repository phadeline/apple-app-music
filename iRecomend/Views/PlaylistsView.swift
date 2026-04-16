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
                        .font(.system(size: 20, weight: .bold))
                        .underline()
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top)

                    VStack(spacing: 20) {
                        ForEach(viewModel.playlists) { playlist in
                            NavigationLink(destination: PlaylistTracksView(playlist: playlist, viewModel: viewModel)) {
                                Text(playlist.name)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(24)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.cardGradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                                    .playlistItemShadow()
                            }
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
