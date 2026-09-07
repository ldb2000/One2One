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

    // MARK: - Lots 11 et 12 : le type 1:1 a ses propres écrans

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

    /// Vrai quand l'espace `Réunion` doit monter l'écran de séance du **1:1
    /// subi** (capture `5a-1to1-collaborateur-seance.png`, lot 13).
    ///
    /// Symétrique de `usesOneOnOneManagerSession`, et **exclusive** de lui : un
    /// type ne peut pas être à la fois mené et subi, puisque `myRole` se déduit
    /// du type (D4). Réservé au mode En séance : la préparation est la capture
    /// 5b (lot 14), la relecture reste le poste de pilotage.
    static func usesOneOnOneCollaboratorSession(kind: MeetingKind,
                                                mode: MeetingScreenModel.Mode) -> Bool {
        kind == .manager && mode == .live
    }

    /// Vrai quand le mode Préparer doit céder la place à l'écran de préparation
    /// du 1:1 côté manager (`ManagerPrepView`, capture 2b).
    ///
    /// Le type `.manager` (je suis le collaborateur) a le **sien**, au lot 14 :
    /// la préparation en deux minutes de la capture 5b n'est pas cet écran-là,
    /// et servir 2b à un collaborateur lui montrerait le suivi de son propre
    /// moral vu du poste de son manager.
    static func usesOneOnOnePreparation(kind: MeetingKind,
                                        mode: MeetingScreenModel.Mode) -> Bool {
        kind == .oneToOne && mode == .prepare
    }

    /// Vrai quand le mode Préparer doit monter la **préparation en deux
    /// minutes** du 1:1 subi (`CollaboratorPrepView`, capture 5b, lot 14).
    ///
    /// Symétrique de `usesOneOnOnePreparation`, et exclusive de lui comme des
    /// deux écrans de séance : `myRole` se déduit du type (D4), donc un
    /// entretien est mené ou subi, jamais les deux. C'est le mode par défaut à
    /// l'ouverture d'un 1:1 subi sans enregistrement (`initialMode`), parce que
    /// c'est l'écran que la notification de la veille propose d'ouvrir.
    static func usesOneOnOneCollaboratorPreparation(kind: MeetingKind,
                                                    mode: MeetingScreenModel.Mode) -> Bool {
        kind == .manager && mode == .prepare
    }

    // MARK: - Lot 18 : le mode Relire de l'atelier

    /// Vrai quand le mode Relire doit monter la **planche de séance** de
    /// l'atelier (capture `6b-atelier-planche-de-seance.png`, lot 18) au lieu
    /// du poste de pilotage.
    ///
    /// Un atelier n'a pas de tableau d'actions dense à relire : il a une
    /// production à passer en revue — planches, captures et pièces dans
    /// l'ordre du temps, prêtes à partir dans le rapport (spec §7.3).
    /// Exclusive des quatre prédicats de 1:1, qui exigent `.oneToOne` ou
    /// `.manager` — et du mode Relire standard, dont elle est l'exception
    /// pour ce seul type.
    static func usesWorkshopReview(kind: MeetingKind,
                                   mode: MeetingScreenModel.Mode) -> Bool {
        kind == .workshop && mode == .review
    }

    /// Le mode d'ouverture d'une réunion **jamais ouverte**, quand rien n'est
    /// mémorisé pour elle.
    ///
    /// Spec §3 : « `2b` s'ouvre par défaut en mode `Préparer` ». Un 1:1 qui
    /// porte déjà un enregistrement n'est plus à préparer : on l'ouvre là où on
    /// l'avait laissé, c'est-à-dire en séance.
    ///
    /// **Les deux types de tête-à-tête**, depuis le lot 14 : la préparation en
    /// deux minutes de la capture 5b est précisément l'écran qu'on ouvre la
    /// veille d'un entretien subi, et l'ouvrir en séance obligerait à changer
    /// de mode à la main avant chaque entretien.
    ///
    /// - Parameter persistedRaw: la valeur mémorisée dans `UserDefaults`, `nil`
    ///   si la réunion n'a jamais été ouverte. Un choix mémorisé fait toujours
    ///   loi : ce défaut ne s'applique qu'en son absence.
    /// - Returns: le mode à imposer, ou `nil` s'il n'y a rien à changer.
    static func initialMode(persistedRaw: String?,
                            kind: MeetingKind,
                            hasRecording: Bool) -> MeetingScreenModel.Mode? {
        guard persistedRaw == nil || MeetingScreenModel.Mode(rawValue: persistedRaw ?? "") == nil,
              OneOnOneThreadStore.faceToFace.contains(kind),
              !hasRecording,
              modes(for: kind).contains(.prepare) else { return nil }
        return .prepare
    }

    /// Libellé de l'espace `Réunion` dans la barre d'espaces. « Réunion » n'a
    /// pas de sens sur une note : c'est la même exception que portait
    /// `MeetingSection.liveNotes.label(for:)`.
    static func meetingSpaceLabel(for kind: MeetingKind) -> String {
        kind == .note ? "Note" : MeetingScreenModel.Space.meeting.label
    }
}
