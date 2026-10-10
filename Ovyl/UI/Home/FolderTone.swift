import SwiftUI

/// A folder color's two tones: the front, which is the color picked, and the
/// back with its tab. Every color in the flower has a back picked to read
/// apart from it, lighter behind a dark color and deeper behind a light one,
/// so a folder shows its shape whatever its color. Any other color gets a
/// back made the same way.
nonisolated struct FolderTone: Equatable, Sendable {
    let front: HexColor
    let back: HexColor

    init(_ hex: String) {
        let key = hex.uppercased()
        front = HexColor(key)
        if let back = Self.backs[key] {
            self.back = HexColor(back)
        } else {
            back = front.isLight ? front.mixed(-0.15) : front.mixed(0.3)
        }
    }

    /// A front about as light as the page: it's edged in the back's tone and
    /// casts a plain shadow, so the folder still stands out.
    var isPale: Bool { front.luminance > 0.85 }

    /// The back for each color in the flower, by its front.
    static let backs: [String: String] = [
        // The outer ring: a lighter tone of each.
        "#A63D2F": "#D27866", // brick
        "#E2725B": "#F2A893", // terracotta
        "#E8833A": "#F5B27A", // burnt orange
        "#D4A017": "#EBC65C", // mustard
        "#B0C246": "#D2DE84", // the app's green
        "#5E9E4F": "#93C383", // fern
        "#2A9D8F": "#6FC4B8", // teal
        "#1F6F78": "#4F9AA2", // deep turquoise
        "#3D5A80": "#7189AB", // denim
        "#8E4162": "#B97692", // plum
        "#7A4E2D": "#A97D5A", // walnut
        "#212121": "#4A4A4A", // the app's graphite
        // The inner ring and the center: a deeper tone of each.
        "#F2C14E": "#DDA63A", // saffron
        "#F4A988": "#E08768", // apricot
        "#E8C9A0": "#D4AE7E", // sand
        "#C9DE8A": "#AFC766", // lime
        "#9DD3C8": "#78BBAE", // seafoam
        "#D9A5B3": "#C48496", // dusty rose
        "#F1F2EC": "#DCDDD2", // off-white
    ]
}
