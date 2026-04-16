//
//  Modifiers.swift
//  iRecomend
//
//  Created by phadeline Evra on 4/16/26.
//
import SwiftUI

// MARK: - Main card shadow
// Original CSS: `box-shadow: 10px 10px lightblue;`
struct MainCardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: Theme.cardShadow, radius: 0, x: 10, y: 10)
    }
}

// MARK: - Playlist list-item shadow
// Original CSS:
// box-shadow:
//   0 4px 8px rgba(0, 0, 0, 0.7),
//   2px 2px 5px rgba(0, 0.5, 0, 0.4);
struct PlaylistItemShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 4)
            .shadow(color: .black.opacity(0.4), radius: 5, x: 2, y: 2)
    }
}

// MARK: - Recommendation card shadow
// Same shadow spec as playlist items.
struct RecommendationShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 4)
            .shadow(color: .black.opacity(0.4), radius: 5, x: 2, y: 2)
    }
}

// MARK: - Carousel heading glow
// Original CSS: text-shadow: 1px 1px 5px black, 0 0 10em blue, 0 0 10em blue;
struct CarouselHeadingGlow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black, radius: 5, x: 1, y: 1)
            .shadow(color: Theme.carouselHeadingGlow, radius: 20, x: 0, y: 0)
            .shadow(color: Theme.carouselHeadingGlow, radius: 20, x: 0, y: 0)
    }
}

extension View {
    func mainCardShadow() -> some View       { modifier(MainCardShadow()) }
    func playlistItemShadow() -> some View   { modifier(PlaylistItemShadow()) }
    func recommendationShadow() -> some View { modifier(RecommendationShadow()) }
    func carouselHeadingGlow() -> some View  { modifier(CarouselHeadingGlow()) }

    /// Applies `.page` tab view style on iOS; no-op on macOS where it's unavailable.
    @ViewBuilder
    func pageTabViewStyleIfAvailable() -> some View {
        #if os(iOS)
        self.tabViewStyle(.page(indexDisplayMode: .never))
        #else
        self
        #endif
    }
}
