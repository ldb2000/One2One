import Foundation

/// Ce que la navigation de l'écran de réunion propose selon le type.
///
/// Remplace `MeetingView.visibleSections(for:)` et son énumération de sept
/// onglets par les trois espaces de la spec §1.1 et le sous-mode temporel du
/// §2.2. Comme la fonction qu'il remplace, ce routage est **pur** : il ne lit
/// que le `MeetingKind`, ce qui le rend testable sans base ni écran.
///
/// La règle de fond est inchangée : une note (`MeetingKind.note`) n'a ni audio,
/// ni transcription, ni rapport — donc pas d'espace `Rapport`, et pas de
/// sélecteur de mode : elle s'écrit, elle ne se prépare ni ne se relit.
enum MeetingSpaceRouting {

    /// Les espaces offerts pour ce type, dans l'ordre d'affichage de la barre.
    static func spaces(for kind: MeetingKind) -> [MeetingScreenModel.Space] {
        switch kind {
        case .note:
            return [.meeting, .resources]
        case .global, .project, .oneToOne, .work, .manager, .workshop:
            return [.meeting, .report, .resources]
        }
    }

    /// Les modes offerts pour ce type. Vide = pas de sélecteur du tout.
    static func modes(for kind: MeetingKind) -> [MeetingScreenModel.Mode] {
        switch kind {
        case .note:
            return []
        case .global, .project, .oneToOne, .work, .manager, .workshop:
            return [.prepare, .live, .review]
        }
    }

    /// Le couple espace/mode à afficher, une fois écarté ce que ce type ne
    /// propose pas.
    ///
    /// Appelé à l'apparition de l'écran et à chaque changement de type : c'est
    /// le pendant des deux `onChange` qui remettaient `activeSection` sur le
    /// premier onglet visible. Le défaut est celui de `MeetingScreenModel`
    /// (`meeting` / `live`), pour que le repli et l'ouverture d'une réunion
    /// jamais vue donnent le même écran.
    static func fallback(space: MeetingScreenModel.Space,
                         mode: MeetingScreenModel.Mode,
                         for kind: MeetingKind) -> (space: MeetingScreenModel.Space,
                                                    mode: MeetingScreenModel.Mode) {
        let espacesOfferts = spaces(for: kind)
        let modesOfferts = modes(for: kind)
        return (
            space: espacesOfferts.contains(space) ? space : (espacesOfferts.first ?? .meeting),
            mode: modesOfferts.contains(mode) ? mode : .live
        )
    }

    /// Vrai quand l'espace `Réunion` doit monter l'écran de séance du **1:1
    /// mené** (capture `2a-1to1-manager-seance.png`, lot 11) au lieu du
    /// cockpit multi-participants.
    ///
    /// Réservé à `.oneToOne` : le 1:1 **subi** (`.manager`) est la capture 5a,
    /// dont la grille, les colonnes et les commandes diffèrent (lot 13). Et
    /// réservé au mode En séance : la préparation est la capture 2b (lot 12),
    /// la relecture reste le poste de pilotage.
    static func usesOneOnOneManagerSession(kind: MeetingKind,
                                           mode: MeetingScreenModel.Mode) -> Bool {
        kind == .oneToOne && mode == .live
    }

    /// Libellé de l'espace `Réunion` dans la barre d'espaces. « Réunion » n'a
    /// pas de sens sur une note : c'est la même exception que portait
    /// `MeetingSection.liveNotes.label(for:)`.
    static func meetingSpaceLabel(for kind: MeetingKind) -> String {
        kind == .note ? "Note" : MeetingScreenModel.Space.meeting.label
    }
}
