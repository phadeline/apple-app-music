import SwiftUI

@main
struct iRecomendApp: App {
    var body: some Scene {
        WindowGroup {
            if #available(macOS 14.0, *) {
                SplashContainerView()
            } else {
                // Fallback on earlier versions
            }
        }
    }
}

@available(macOS 14.0, *)
struct SplashContainerView: View {
    @State private var showSplash = true
    @State private var opacity: Double = 0

    var body: some View {
        if showSplash {
            ZStack {
                Color.black.ignoresSafeArea()
                Image("icons8-music-100")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .opacity(opacity)
            }
            .onAppear {
                withAnimation(.easeIn(duration: 2)) {
                    opacity = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation(.easeOut(duration: 1)) {
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showSplash = false
                    }
                }
            }
        } else {
            ContentView()
        }
    }
}
