import SwiftUI

@available(macOS 14.0, *)
struct ContentView: View {
    @StateObject private var viewModel = RecommendationViewModel()
    @State private var sliderFullyDragged = false
    @State private var navigateToPlaylists = false

    var body: some View {
        
        NavigationStack {
            ZStack {
                Theme.bodyBackground.ignoresSafeArea()

                GeometryReader { geo in
                    ScrollView {
                        VStack {
                            Spacer()
                            VStack(spacing: 16) {
                                mainCard
                                    .frame(maxWidth: 560)

                                if viewModel.isLoading {
                                    ProgressView("Loading playlists and recommendations...")
                                        .padding()
                                }

                                if let errorMessage = viewModel.errorMessage {
                                    Text(errorMessage)
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            Spacer()
                        }
                        .frame(minHeight: geo.size.height)
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToPlaylists) {
                PlaylistsView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Main pink/purple card with big "iRecomend" title + connect button
    private var mainCard: some View {
        VStack(alignment: .center, spacing: 20) {
            Text("iRecomend")
                .font(Theme.titleFont(size: 64))
                .foregroundColor(Theme.titleCream)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

            // Drag the music-note thumb to the end, then the button unlocks.
            HStack(spacing: 12) {
                DragToConnectSlider(
                    onReachedEnd: { sliderFullyDragged = true },
                    isDimmed: sliderFullyDragged
                )
            }
            .padding(.horizontal, 20)

            Button(action: {
                Task {
                    await viewModel.connectAndLoad()
                    if !viewModel.playlists.isEmpty {
                        navigateToPlaylists = true
                    }
                }
            }) {
                Text("Connect Apple Music")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(sliderFullyDragged ? 0.85 : 0.4))
                    .foregroundColor(Theme.cardGradientStart)
                    .cornerRadius(25)
            }
            .disabled(!sliderFullyDragged || viewModel.isLoading)
            .padding(.horizontal, 20)

            VStack(spacing: 4) {
                Text("Drag to the end of the slider to connect")
                Text("your Apple Music account. Then press Connect.")
            }
            .font(.footnote)
            .foregroundColor(.white.opacity(0.9))
            .multilineTextAlignment(.center)
            .padding(.bottom, 20)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 60, style: .continuous))
        .mainCardShadow()
    }
}

// MARK: - Button style matching the play/pause button look in recommendations.js
struct TintedActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

#Preview {
    if #available(macOS 14.0, *) {
        ContentView()
    } else {
        // Fallback on earlier versions
    }
}
