import Foundation

/// Les repères de frise apportés par le lot 17 : **les planches épinglées**.
///
/// Dans un fichier d'extension, comme `+Pins.swift` du lot 6 : plusieurs lots
/// ajoutent leurs repères en parallèle, chacun dans son fichier, aucun conflit
/// à résoudre.
@MainActor
extension MeetingTimelineMarkers {

    /// Les repères des planches épinglées (`Épingler à mm:ss`), triés par
    /// timecode.
    ///
    /// Forme `capture` — le **carré** de la spec §2.4, pour la même raison que
    /// les pièces épinglées du lot 6 : la frise n'a que trois formes, et une
    /// planche montrée à un instant donné est exactement ce que le carré
    /// désigne, « quelque chose a été montré ici ».
    ///
    /// La source est la **note** posée par `WorkshopState.pinActiveBoard` — pas
    /// la planche elle-même : `Board.t` est l'instant de sa *création*, tandis
    /// qu'épingler désigne l'instant où on l'a montrée. Une planche dessinée à
    /// `08:15` et discutée à `34:20` porte donc deux instants différents, et
    /// c'est le second que la frise doit montrer.
    static func boardMarkers(for meeting: Meeting) -> [MeetingPlayhead.Marker] {
        pinnedBoardNotes(of: meeting)
            .map { MeetingPlayhead.Marker(t: $0.t, kind: .capture, label: $0.text) }
            .sorted { $0.t < $1.t }
    }

    /// **Tous** les repères, planches comprises : notes, captures, pièces
    /// épinglées et planches épinglées.
    ///
    /// Les notes de planche sont retirées de la base avant d'y ajouter les
    /// repères carrés : sans ce retrait, la même planche porterait deux
    /// repères superposés — un rond (c'est une note) et un carré (c'est une
    /// planche). `markes(for:)` vit dans le fichier partagé et n'a pas à
    /// connaître les planches.
    static func allMarkersIncludingBoards(for meeting: Meeting) -> [MeetingPlayhead.Marker] {
        let planches = pinnedBoardNotes(of: meeting)
        let aRetirer = Set(planches.map { "\($0.t)|\($0.text)" })
        let base = allMarkers(for: meeting).filter { repere in
            !aRetirer.contains("\(repere.t)|\(repere.label)")
        }
        return (base + boardMarkers(for: meeting)).sorted { $0.t < $1.t }
    }

    /// Les notes qui citent une planche — celles que `Épingler à mm:ss` pose.
    private static func pinnedBoardNotes(of meeting: Meeting) -> [MeetingNote] {
        meeting.timedNotes.filter { $0.sourceRef?.kind == .board }
    }
}
