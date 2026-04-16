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
 
    // Matches original dimensions: 200pt track, 50pt thumb.
    private let trackWidth: CGFloat = 200
    private let trackHeight: CGFloat = 12
    private let thumbWidth: CGFloat = 50
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
 
            // Thumb — music note icon (uses the `icons8-music-100` asset from
            // the original web app; falls back to SF Symbol if not added yet).
            Group {
                #if canImport(UIKit)
                if UIImage(named: "icons8-music-100") != nil {
                    Image("icons8-music-100")
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.black)
                }
                #else
                Image("icons8-music-100")
                    .resizable()
                    .scaledToFit()
                #endif
            }
            .frame(width: thumbWidth, height: thumbHeight)
            .background(Color.white.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black, lineWidth: 1)
            )
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
 
