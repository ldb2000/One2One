import SwiftUI

extension Color {
    /// Initialise une couleur sRGB opaque depuis une chaîne hexadécimale `RRGGBB`
    /// (préfixe `#` et espaces optionnels). Renvoie `nil` si la chaîne ne contient
    /// pas exactement 6 chiffres hexadécimaux valides.
    init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Renvoie la couleur au format `#RRGGBB` (majuscules) dans l'espace sRGB.
    /// Renvoie `nil` si la couleur ne peut pas être convertie en sRGB
    /// (composantes RGB indisponibles).
    func toHex() -> String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components,
              components.count >= 3 else { return nil }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
