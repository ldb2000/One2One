import Foundation
import SwiftData

/// Ce que l'en-tête de la préparation du 1:1 subi affiche (capture 5b) :
/// `YP`, `1:1 avec Yann — demain 14:00`,
/// `Préparation · 2 min · dernier point le 21 août`, badge `Collaborateur`.
///
/// **Modèle pur**, testable sans écran et sans attendre demain : l'écriture
/// « demain » est exactement le genre de détail qu'une vue calcule mal, et
/// qu'un test à horloge injectée attrape tout de suite.
struct CollabPrepHeaderModel: Equatable, Sendable {
    /// `1:1 avec Yann — demain 14:00`.
    var title: String
    /// `Préparation · 2 min · dernier point le 21 août`.
    var meta: String
    /// Le badge bordé de droite.
    var badge: String
    /// `YP`.
    var initials: String
    /// Le nom complet, pour la palette d'avatar et la bulle d'aide.
    var identity: String
}

/// Les intitulés et les deux calculs de l'écran de préparation du 1:1 subi
/// (capture 5b, spec §6.3) — **pur**.
///
/// Même parti que `CollaboratorSessionModel` au lot 13 : ce que l'écran ajoute
/// aux services du domaine (les titres, l'écriture d'un rendez-vous, la borne
/// de la fenêtre des livrés, la mention de provenance) vit ici, testé, plutôt
/// que dans le corps d'une `View` où seul l'œil pourrait le vérifier.
@MainActor
enum CollabPrepModel {

    // MARK: - Intitulés

    /// `CE QUE J'AI LIVRÉ DEPUIS` : le titre de 5b, plus long que le
    /// `CE QUE J'AI LIVRÉ` de la séance (5a) parce que la carte de préparation
    /// n'affiche pas la pilule `depuis le …` qui portait la borne.
    static let deliveredTitle = "CE QUE J'AI LIVRÉ DEPUIS"
    static let deliveredEmptyInvite =
        "Rien de clos depuis le dernier point — vos actions closes et vos réunions "
        + "apparaîtront ici, sans rien à saisir."
    /// La mention du pied de carte, au mot près (spec §6.3).
    static let provenance =
        "Généré depuis vos actions, vos réunions et l'historique des 1:1 "
        + "— modifiable avant partage."
    /// Le badge de rôle. Le même mot que la pilule de la barre du haut désigne
    /// le même fait : cet entretien-là, je le subis (critère chantier 5 n° 1).
    static let roleBadge = "Collaborateur"
    /// La promesse de la capture : deux minutes, pas deux heures. Une constante
    /// et non une durée calculée — c'est un engagement de conception, et il ne
    /// dépend pas du nombre de lignes.
    static let durationPromise = "2 min"
    /// L'invite affichée faute d'interlocuteur rattaché à la séance.
    static let noThreadTitle = "Aucun interlocuteur"
    static let noThreadInvite =
        "Ajoutez votre manager aux participants : le fil, les promesses et les demandes "
        + "se rattachent à lui."

    // MARK: - En-tête

    /// L'en-tête de la carte.
    ///
    /// - Parameter now: l'instant de référence, figé à l'ouverture de l'écran.
    ///   C'est lui qui décide de « demain ».
    static func header(meeting: Meeting,
                       thread: OneOnOneThread,
                       now: Date) -> CollabPrepHeaderModel {
        let prenom = OneOnOneThreadStore.firstName(of: thread)
        let quand = whenLabel(meeting.date, now: now)
        let titre = prenom.isEmpty ? "1:1 — \(quand)" : "1:1 avec \(prenom) — \(quand)"

        var parts = ["Préparation", durationPromise]
        if let precedente = OneOnOneThreadStore.previousMeeting(before: meeting, in: thread) {
            parts.append("dernier point le \(OneOnOneDateFormat.dayMonth(precedente.date))")
        } else {
            // « premier point » et non une date inventée : un fil qui commence
            // n'a pas d'ancienneté à annoncer, et c'est une information.
            parts.append("premier point")
        }

        return CollabPrepHeaderModel(title: titre,
                                     meta: parts.joined(separator: " · "),
                                     badge: roleBadge,
                                     initials: PersonCardModel.initials(of: thread),
                                     identity: PersonCardModel.name(of: thread))
    }

    /// `demain 14:00`, `aujourd'hui 14:00`, `Lundi 14:00`, `18 sept. 14:00`.
    ///
    /// « Demain » et « aujourd'hui » sont nommés parce que la notification de
    /// la veille amène ici : l'écran doit dire la même chose que le rappel qui
    /// l'a ouvert. Au-delà, l'écriture est celle de **toutes** les échéances du
    /// domaine (`OneOnOneDateFormat.dueDate` : le jour de la semaine dans les
    /// sept jours, la date ensuite) plutôt qu'une quatrième règle à part.
    ///
    /// L'heure suit toujours : un rendez-vous sans heure ne se prépare pas.
    static func whenLabel(_ date: Date, now: Date) -> String {
        let jours = dayOffset(from: now, to: date)
        let heure = time(date)
        switch jours {
        case 0:  return "aujourd'hui \(heure)"
        case 1:  return "demain \(heure)"
        default: return "\(OneOnOneDateFormat.dueDate(date, now: now)) \(heure)"
        }
    }

    // MARK: - Ce que j'ai livré depuis

    /// La borne basse de `CE QUE J'AI LIVRÉ DEPUIS` : la séance qui précède
    /// celle qu'on prépare.
    ///
    /// La séance **précédente** et non la dernière tenue : c'est la même borne
    /// que la carte de séance du lot 13 (`DeliveredCard.depuis`), et les deux
    /// écrans doivent lister les mêmes livrables. `nil` au premier entretien du
    /// fil — « depuis le dernier 1:1 » veut alors dire « depuis toujours ».
    static func deliveredSince(_ meeting: Meeting, in thread: OneOnOneThread) -> Date? {
        OneOnOneThreadStore.previousMeeting(before: meeting, in: thread)?.date
    }

    // MARK: - Outils

    /// Le nombre de jours **calendaires** entre deux instants : `1` pour
    /// demain, quelle que soit l'heure. Comparer des intervalles de 24 h dirait
    /// « aujourd'hui » d'un rendez-vous à 8 h le lendemain d'une préparation
    /// faite à 22 h.
    private static func dayOffset(from now: Date, to date: Date) -> Int {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.locale = Locale(identifier: "fr_FR")
        return calendrier.dateComponents([.day],
                                         from: calendrier.startOfDay(for: now),
                                         to: calendrier.startOfDay(for: date)).day ?? 0
    }

    /// `14:00` — locale forcée `fr_FR`, comme `OneOnOneDateFormat` : un poste
    /// réglé en anglais afficherait `2:00 PM` au milieu de libellés français.
    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
