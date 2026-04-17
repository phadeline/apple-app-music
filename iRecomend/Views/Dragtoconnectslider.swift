//
//  Dragtoconnectslider.swift
//  iRecomend
//
//  Created by phadeline Evra on 4/16/26.
//

import SwiftUI
 
/// A drag-to-connect slider that matches the original web app's interaction.
///
/// The original CSS (`App.css`):
///   - 200px wide, 12px tall track
///   - Grey background `#f9f9f9`, 4px border, 25px rounded left edge only
///   - Thumb is 50x30, uses a music-note icon as its background image
///   - Track becomes translucent (opacity 0.2) once connected
///
/// Behavior from `App.js`:
///   - User must drag the thumb all the way to max (200)
///   - Only then does the Connect button become enabled
///   - Once authorized, the slider fades to 0.2 opacity
struct DragToConnectSlider: View {
    /// Called when the user drags the thumb to the far right edge.
    var onReachedEnd: () -> Void
 
    /// Set to `true` after the user has authorized — slider fades.
    var isDimmed: Bool
 
    @State private var thumbX: CGFloat = 0
    @State private var hasTriggered = false
 
    private let trackWidth: CGFloat = 200
    private let trackHeight: CGFloat = 12
    private let thumbWidth: CGFloat = 30
    private let thumbHeight: CGFloat = 30
 
    private var maxThumbX: CGFloat { trackWidth - thumbWidth }
 
    var body: some View {
        ZStack(alignment: .leading) {
            // Track — grey background, 4px border, rounded left edge only (matches CSS).
            RoundedCorners(radius: 25, corners: [.topLeft, .bottomLeft])
                .fill(Color(red: 249/255, green: 249/255, blue: 249/255))
                .overlay(
                    RoundedCorners(radius: 25, corners: [.topLeft, .bottomLeft])
                        .stroke(Color.black, lineWidth: 4)
                )
                .frame(width: trackWidth, height: trackHeight)
 
            // Thumb — load from bundle (covers both asset catalog and loose PNG).
            MusicThumbImage()
                .frame(width: thumbWidth, height: thumbHeight)
            .offset(x: thumbX)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard !isDimmed else { return }
                        let newX = min(max(0, value.translation.width + dragStartX), maxThumbX)
                        thumbX = newX
 
                        // Fire only once when we reach the end.
                        if !hasTriggered && newX >= maxThumbX {
                            hasTriggered = true
                            onReachedEnd()
                        }
                    }
                    .onEnded { _ in
                        dragStartX = thumbX
                    }
            )
        }
        .frame(width: trackWidth, height: thumbHeight)
        .opacity(isDimmed ? 0.2 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: isDimmed)
    }
 
    // Track where the thumb was when this drag started so dragging feels continuous.
    @State private var dragStartX: CGFloat = 0
}
 
// icons8-music-note-94.png embedded as base64 so it is always available
// regardless of asset catalog compilation status.
private let musicNoteImageData = Data(base64Encoded: """
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
""", options: .ignoreUnknownCharacters)

private struct MusicThumbImage: View {
    var body: some View {
        if let data = musicNoteImageData {
            #if canImport(UIKit)
            if let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Image(systemName: "music.note").font(.system(size: 20, weight: .bold))
            }
            #else
            if let img = NSImage(data: data) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Image(systemName: "music.note").font(.system(size: 20, weight: .bold))
            }
            #endif
        } else {
            Image(systemName: "music.note").font(.system(size: 20, weight: .bold))
        }
    }
}

/// Helper shape that rounds only specific corners — used for the slider's
/// left-only rounded track (`border-top-right-radius: 0` in the original CSS).
///
/// Uses pure SwiftUI `Path` so this compiles on iOS, iPadOS, and Mac Catalyst
/// (UIBezierPath/UIRectCorner are UIKit and would force an iOS-only build).
private struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: Corner
 
    struct Corner: OptionSet {
        let rawValue: Int
        static let topLeft     = Corner(rawValue: 1 << 0)
        static let topRight    = Corner(rawValue: 1 << 1)
        static let bottomLeft  = Corner(rawValue: 1 << 2)
        static let bottomRight = Corner(rawValue: 1 << 3)
        static let all: Corner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }
 
    func path(in rect: CGRect) -> Path {
        var path = Path()
 
        let tl = corners.contains(.topLeft)     ? radius : 0
        let tr = corners.contains(.topRight)    ? radius : 0
        let bl = corners.contains(.bottomLeft)  ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
 
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                radius: tr,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                radius: bl,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                radius: tl,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }
}
 
