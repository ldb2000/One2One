import Foundation

/// Le badge de type d'une réunion, sur la carte « DERNIÈRES RÉUNIONS » de
/// l'écran projet (capture `1d-ecran-projet-pilotage.png`) et dans la tuile
/// « DERNIÈRE RÉUNION » — décision **D10**.
///
/// **Trois cas seulement, et un quatrième qui n'en est pas un.** `MeetingKind`
/// n'a pas de COPIL et n'en aura pas (constat §2.19) : un COPIL est une
/// réunion projet que son thème ou son titre désigne comme telle. `Atelier` et
/// `1:1`, eux, sont des `kind`. Toute autre réunion — une réunion projet
/// ordinaire, une note, une réunion globale — n'a **pas** de badge : la
/// maquette ne colore que ce qui se distingue, et un badge « Projet » sur une
/// carte qui ne montre que les réunions d'un projet ne dirait rien.
///
/// Fonction pure, testée avant sa vue (règle du dépôt) : les teintes vivent
/// dans `MeetingTypeBadgeView` (`Views/Project/Pilotage/`), ce fichier ne
/// nomme aucune couleur.
enum MeetingTypeBadge: String, CaseIterable, Sendable {
    case copil
    case atelier
    case oneOnOne

    /// Le libellé du badge, tel que la capture 1d l'écrit.
    var libelle: String {
        switch self {
        case .copil:    return "COPIL"
        case .atelier:  return "Atelier"
        case .oneOnOne: return "1:1"
        }
    }

    /// Le terme reconnu dans un thème ou un titre pour faire un COPIL.
    static let termeCopil = "copil"

    /// Le badge d'une réunion, ou `nil` si elle n'en porte pas.
    ///
    /// L'ordre des trois épreuves compte : un COPIL **tenu en atelier**
    /// resterait un COPIL, parce que c'est l'instance qui se lit sur la carte,
    /// pas la forme de la séance.
    static func from(_ meeting: Meeting) -> MeetingTypeBadge? {
        if estCopil(titre: meeting.title, themes: meeting.tags.map(\.name)) { return .copil }
        switch meeting.kind {
        case .workshop: return .atelier
        case .oneToOne: return .oneOnOne
        default:        return nil
        }
    }

    /// La règle COPIL, séparée de `Meeting` pour se tester sans store : un
    /// thème **ou** le titre contient « COPIL », casse et accents ignorés.
    static func estCopil(titre: String, themes: [String]) -> Bool {
        ([titre] + themes).contains { contientCopil($0) }
    }

    private static func contientCopil(_ texte: String) -> Bool {
        texte.range(of: termeCopil,
                    options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
