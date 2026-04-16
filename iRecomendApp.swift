import SwiftUI

@main
struct iRecomendApp: App {
    var body: some Scene {
        WindowGroup {
            if #available(macOS 14.0, *) {
                ContentView()
            } else {
                // Fallback on earlier versions
            }
        }
    }
}
