import CoreGraphics
import Foundation

/// Ce que le lot 7 ajoute à la frise : le **carré de capture** de la spec §5.2
/// — « marqueur carré 12 px `#3d5180` par capture, `accent/action` pour la
/// dernière, légende `■ = capture` ».
///
/// Dans un fichier d'extension, comme les repères du lot 6
/// (`MeetingTimelineMarkers+Pins.swift`) : trois lots travaillent en parallèle
/// sur la même base, chacun dans son fichier.
///
/// Les repères eux-mêmes existent depuis le lot 2 (`markers(for:)` lit déjà
/// `SlideCapture.t`) : ce qui manquait, c'est **quel** carré est le dernier et
/// **quand** la légende a un sens. Deux fonctions pures, plutôt que deux `if`
/// dans le `Canvas` de la frise.
@MainActor
extension MeetingTimelineMarkers {

    /// Côté du carré de capture, en points (spec §5.2). Plus grand que les
    /// 7 px des ronds et des losanges : c'est le seul repère qui désigne une
    /// **image** qu'on veut pouvoir viser à la souris sur une frise de 22 px.
    static let captureMarkerSize: CGFloat = 12

    /// L'instant de la **dernière** capture parmi les repères, `nil` s'il n'y
    /// en a aucune. C'est ce carré que la frise dessine en `accent/action`.
    ///
    /// Les repères des pièces épinglées (lot 6) portent la même forme carrée,
    /// délibérément : « quelque chose a été montré ici ». Ils comptent donc
    /// aussi comme captures pour cette mise en avant — la dernière chose
    /// montrée est la dernière chose montrée.
    static func lastCaptureT(_ markers: [MeetingPlayhead.Marker]) -> Double? {
        markers.filter { $0.kind == .capture }.map(\.t).max()
    }

    /// La légende de la frise (`■ = capture`), `nil` quand la séance n'a aucune
    /// capture : une légende qui expliquerait un symbole absent est du bruit.
    static func captureLegend(_ markers: [MeetingPlayhead.Marker]) -> String? {
        markers.contains { $0.kind == .capture } ? "■ = capture" : nil
    }
}
