import SwiftUI
import AppKit

enum MeetingTheme {
    static let canvasCream  = Color(nsColor: NSColor(srgbRed: 0.976, green: 0.960, blue: 0.929, alpha: 1))
    static let surfaceCream = Color(nsColor: NSColor(srgbRed: 0.988, green: 0.980, blue: 0.957, alpha: 1))
    static let accentOrange = Color(nsColor: NSColor(srgbRed: 0.776, green: 0.400, blue: 0.400, alpha: 1))
    static let hairline     = Color.secondary.opacity(0.18)
    static let badgeBlack   = Color(nsColor: NSColor(white: 0.10, alpha: 1))
    static let softShadow   = Color.black.opacity(0.06)

    static let titleSerif   = Font.system(size: 34, weight: .semibold, design: .serif)
    static let bodySerif    = Font.system(.body, design: .serif)
    static let sectionLabel = Font.caption2.weight(.bold)
    static let meta         = Font.caption.monospacedDigit()
}
