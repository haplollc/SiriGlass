//
//  DropGeometry.swift
//  SiriGlass
//
//  Where the Dynamic Island is, and how big the drop gets.
//
//  There is no API for the island's frame, so it is read off the window:
//  every iPhone with an island has a top safe area of 59 pt or more in
//  portrait (notched phones have 44–50, others 20 or none), and the island
//  sits a little lower on the phones with the deeper top inset. Measured on
//  an iPhone 17 Pro Max (62 pt): 126.67 x 37.33 pt, 13.67 pt from the top;
//  the 59 pt phones put it 11.33 pt down. Anywhere else (a notch, no
//  notch, an iPad, landscape) the drop pours from the top centre of the
//  window instead, out of an island just above the edge.
//

import CoreGraphics

/// What the drop needs to know about its window.
struct WindowMetrics: Equatable, Sendable {
    var size: CGSize
    var safeAreaTop: CGFloat
    var isPhone: Bool

    var isPortrait: Bool { size.height >= size.width }
}

enum DropGeometry {
    static let islandSize = CGSize(width: 126.67, height: 37.33)

    /// The drop as it hangs under the island, measured off the iOS 27
    /// capture: 170 x 126 pt, its top 4 pt below the screen's edge.
    static let top = 4.0
    static let bottom = 130.0
    static let halfWidth = 85.0
    static let size = CGSize(width: 170, height: 126)

    /// How far down the drop and its light can reach under the island,
    /// with room for it to swell with a loud voice.
    static let reach = 196.0

    /// True when the window has a Dynamic Island at its top.
    static func hasIsland(_ window: WindowMetrics) -> Bool {
        window.isPhone && window.isPortrait && window.safeAreaTop >= 51
    }

    /// The island's frame in window coordinates, or, without one, a pill
    /// of the same size hidden just above the top edge.
    static func island(in window: WindowMetrics) -> CGRect {
        let x = (window.size.width - islandSize.width) / 2
        guard hasIsland(window) else {
            return CGRect(x: x, y: -islandSize.height - 6, width: islandSize.width, height: islandSize.height)
        }
        let y = min(max(11.33 + (window.safeAreaTop - 59) * 0.78, 9), 20)
        return CGRect(x: x, y: y, width: islandSize.width, height: islandSize.height)
    }
}
