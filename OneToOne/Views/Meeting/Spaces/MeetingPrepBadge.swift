import SwiftUI

/// Le badge « À préparer » / « Préparée » d'une réunion.
///
/// Extrait de `MeetingView` (le programme interdit d'y ajouter) et repeint aux
/// jetons `One2OneToken`. Le calcul de l'état est une **fonction pure** :
/// c'est la seule partie qu'on peut vérifier, et elle décidait jusqu'ici de ce
/// que l'écran affiche depuis le corps d'une vue de 2 900 lignes.
struct MeetingPrepBadge: View {

    /// Ce que le badge annonce. `aucun` = pas de badge du tout.
    enum Etat: Sendable {
        case aucun, aPreparer, preparee
    }

    /// « à préparer » pour une réunion future sans contenu, « préparée » dès
    /// qu'il existe des notes (ponctuelles ou permanentes), sinon rien.
    ///
    /// `maintenant` est un paramètre pour que le test n'ait pas à attendre.
    static func etat(kind: MeetingKind,
                     prepNotes: String,
                     standingNotesNonVides: Bool,
                     debutPrevu: Date,
                     maintenant: Date = Date()) -> Etat {
        let futur = debutPrevu > maintenant
        let aDuContenu = !prepNotes.isEmpty || standingNotesNonVides
        if futur && !aDuContenu { return .aPreparer }
        if aDuContenu { return .preparee }
        return .aucun
    }

    /// Les notes permanentes qui comptent pour ce type de réunion : celles du
    /// collaborateur en 1:1, celles du projet en réunion de projet, aucune
    /// ailleurs.
    @MainActor
    static func standingNotesNonVides(for meeting: Meeting) -> Bool {
        switch meeting.kind {
        case .oneToOne, .manager:
            return !(meeting.participants.first?.standingPrepNotes.isEmpty ?? true)
        case .project:
            return !(meeting.project?.standingPrepNotes.isEmpty ?? true)
        case .global, .work, .note, .workshop:
            return false
        }
    }

    /// L'état du badge pour une réunion.
    @MainActor
    static func etat(for meeting: Meeting, maintenant: Date = Date()) -> Etat {
        etat(kind: meeting.kind,
             prepNotes: meeting.prepNotes,
             standingNotesNonVides: standingNotesNonVides(for: meeting),
             debutPrevu: meeting.scheduledStart ?? meeting.date,
             maintenant: maintenant)
    }

    let etat: Etat
    /// Passe l'écran en mode Préparer — un badge « À préparer » qui ne mène
    /// nulle part n'est qu'un reproche.
    let onPrepare: () -> Void

    var body: some View {
        switch etat {
        case .aucun:
            EmptyView()
        case .aPreparer:
            Button(action: onPrepare) {
                Chip("À préparer", ton: .warn)
            }
            .buttonStyle(.plain)
            .help("Ouvrir le mode Préparer")
        case .preparee:
            Chip("Préparée", ton: .ok)
        }
    }
}
