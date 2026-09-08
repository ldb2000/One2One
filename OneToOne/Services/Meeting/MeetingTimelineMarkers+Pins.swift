import Foundation

/// Les repères de frise apportés par le lot 6 : **les pièces épinglées**.
///
/// Dans un fichier d'extension, et non dans `MeetingTimelineMarkers.swift` :
/// trois lots travaillent en parallèle sur la même base, et deux d'entre eux
/// ajouteront leurs propres repères (les captures du lot 7, les planches du
/// lot 16). Chacun dans son fichier, aucun conflit à résoudre.
@MainActor
extension MeetingTimelineMarkers {

    /// Les repères des pièces épinglées, triés par timecode.
    ///
    /// Forme `capture` — le **carré** de la spec §2.4. La frise n'a que trois
    /// formes (rond, carré, losange) et en inventer une quatrième pour les
    /// pièces la rendrait illisible ; or un document mis à l'écran à un instant
    /// donné est exactement ce que le carré désigne déjà : « quelque chose a
    /// été montré ici ».
    ///
    /// Une pièce sans `pinnedAtT` est ignorée, comme l'est une capture sans
    /// `t` : un repère à `00:00` désignerait un instant où rien ne s'est passé.
    static func pinMarkers(for meeting: Meeting) -> [MeetingPlayhead.Marker] {
        meeting.pinnedAttachments.compactMap { piece in
            guard let t = piece.pinnedAtT else { return nil }
            return MeetingPlayhead.Marker(t: t, kind: .capture, label: piece.fileName)
        }
    }

    /// **Tous** les repères de la réunion : notes, captures et pièces
    /// épinglées. C'est cette fonction que les vues appellent — `markers(for:)`
    /// reste la base, et chaque lot y ajoute la sienne sans que la vue ait à
    /// connaître la liste.
    static func allMarkers(for meeting: Meeting) -> [MeetingPlayhead.Marker] {
        (markers(for: meeting) + pinMarkers(for: meeting)).sorted { $0.t < $1.t }
    }
}
