//
//  Theme.swift
//  iRecomend
//
//  Created by phadeline Evra on 4/16/26.
//

import SwiftUI

/// Colors and gradients pulled directly from the original web app's CSS.
/// See: frontend/src/App.css, playlistpage.css, recommendations.css, Carousel.css
enum Theme {

    // MARK: - Colors

    /// Body background start: rgb(252, 251, 251)
    static let bodyBackgroundStart = Color(red: 252/255, green: 251/255, blue: 251/255)
    /// Body background end: rgb(204, 208, 205)
    static let bodyBackgroundEnd   = Color(red: 204/255, green: 208/255, blue: 205/255)

    /// Card gradient start (pink): rgb(228, 120, 143)
    static let cardGradientStart   = Color(red: 228/255, green: 120/255, blue: 143/255)
    /// Card gradient end (purple): rgb(201, 132, 214)
    static let cardGradientEnd     = Color(red: 201/255, green: 132/255, blue: 214/255)

    /// Title text color (cream): rgb(249, 238, 233)
    static let titleCream          = Color(red: 249/255, green: 238/255, blue: 233/255)

    /// Light blue shadow used behind the main card.
    static let cardShadow          = Color(red: 173/255, green: 216/255, blue: 230/255) // lightblue

    /// Recommendation card background (hot pink): rgb(247, 62, 186)
    static let recommendationPink  = Color(red: 247/255, green:  62/255, blue: 186/255)
    /// Recommendation card text (light blue): rgb(196, 233, 249)
    static let recommendationText  = Color(red: 196/255, green: 233/255, blue: 249/255)

    /// Carousel h2 cyan: rgba(0, 213, 255, 0.871)
    static let carouselHeading     = Color(red: 0, green: 213/255, blue: 255/255).opacity(0.871)
    /// Blue glow used behind the carousel heading.
    static let carouselHeadingGlow = Color.blue.opacity(0.6)

    /// Play button background tint: rgba(31, 190, 7, 0.2)
    static let playButtonTint      = Color(red: 31/255, green: 190/255, blue: 7/255).opacity(0.2)
    /// Pause button background tint: rgba(249, 7, 7, 0.2)
    static let pauseButtonTint     = Color(red: 249/255, green: 7/255, blue: 7/255).opacity(0.2)

    // MARK: - Platform-adaptive colors

    /// System background color that works on both iOS and macOS.
    static var rowBackground: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }

    // MARK: - Gradients

    static var bodyBackground: LinearGradient {
        LinearGradient(
            colors: [bodyBackgroundStart, bodyBackgroundEnd],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var cardGradient: LinearGradient {
        LinearGradient(
            colors: [cardGradientStart, cardGradientEnd],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Typography

    /// Closest system stack to the original:
    /// "Trebuchet MS", "Lucida Sans Unicode", "Lucida Grande", "Lucida Sans", Arial, sans-serif
    /// Trebuchet MS ships with iOS, so we can request it by name.
    static func titleFont(size: CGFloat) -> Font {
        .custom("Trebuchet MS", size: size)
    }
}
