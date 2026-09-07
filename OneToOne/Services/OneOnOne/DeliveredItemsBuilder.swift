import Foundation
import SwiftData

/// `CE QUE J'AI LIVRÉ` de l'écran de séance du 1:1 subi (spec §6.2, capture
/// 5a) — **pur** : il ne reçoit que des tableaux, ne requête rien et n'écrit
/// rien.
///
/// C'est la colonne qui manque partout ailleurs dans l'application, et c'est le
/// critère chantier 5 n° 3 : « la liste se remplit **sans saisie manuelle** et
/// se cite en un clic ». Un entretien où l'on doit se souvenir de ce qu'on a
/// fait est un entretien qu'on perd.
///
/// ## Qui suis-je, dans les données ?
///
/// L'utilisateur de l'application n'est **pas** un `Collaborator` : il n'a pas
/// de fiche d'annuaire, donc `Collaborator.assignedTasks` ne le désigne jamais.
/// La seule désignation qui existe est `ActionAudience.moi` — le défaut du
/// modèle `ActionTask`, et la valeur que pose le composeur d'actions quand on
/// ne délègue pas. C'est donc `destinataire == .moi` qui définit « mes
/// actions », et rien d'autre.
///
/// ## Les trois sources
///
/// 1. **Actions closes** dans `]1:1 précédent, séance]`. La fenêtre est celle
///    de la spec ; sans elle, chaque entretien ressortirait tout l'historique
///    et la colonne deviendrait un mur qu'on cesse de lire.
/// 2. **Réunions à rôle actif** dans la même fenêtre : une réunion où j'ai fait
///    prendre une décision ou pris des notes. Les tête-à-tête en sont exclus —
///    mes 1:1 ne sont pas un livrable, ce sont eux qui parlent des livrables.
/// 3. **Actions bloquées** : ouvertes, reportées ou commentées « bloqué par… ».
///    Elles n'ont **pas** de borne de date : un blocage est un état présent, pas
///    un événement de la fenêtre, et c'est justement ce qu'il faut dire à son
///    manager pendant qu'on l'a en face.
@MainActor
enum DeliveredItemsBuilder {

    // MARK: - Intitulés

    static let title = "CE QUE J'AI LIVRÉ"
    /// La pilule qui dit que personne n'a saisi cette liste (critère n° 3).
    static let autoBadge = "auto"
    static let quoteButtonLabel = "Citer"
    static let emptyInvite =
        "Rien de clos depuis le dernier point — vos actions closes et vos réunions apparaîtront ici."

    /// Nombre de minutes d'une journée de travail, pour l'écriture des charges.
    /// Sept heures serait plus juste d'un point de vue conventionnel ; huit est
    /// ce que porte `pomodoros`/`effortMinutes` partout ailleurs dans l'app.
    static let workdayMinutes = 480

    // MARK: - Le modèle d'une ligne

    enum Status: Sendable, Equatable {
        /// Livré : `✓`.
        case delivered
        /// Bloqué : `◐`, rendu en `warn` avec sa cause.
        case blocked
    }

    /// Une ligne de la carte, prête à rendre.
    struct Item: Identifiable, Equatable, Sendable {
        var id: String
        /// `✓` ou `◐`.
        var symbol: String
        var text: String
        /// `Action close le 29 août · 2 j`, `Réunion du 1er sept. · a débloqué
        /// la décision`, `En cours · bloqué par les comptes GitLab`.
        var detail: String
        var status: Status
        /// La chaîne de citation de la ligne, quand sa source est adressable.
        ///
        /// **Propagée, jamais inventée** : `SourceRef.Kind` n'a pas de cas pour
        /// une action, et `ActionTask` n'a pas de `stableID` qu'un `SourceRef`
        /// pourrait viser. Une ligne d'action reprend donc la source de
        /// l'action (l'endroit d'où elle est née) ; une ligne de réunion vise
        /// la note qui a justifié le rôle actif.
        var reference: SourceRef?
        /// Instant de la ligne, pour le tri. Jamais affiché tel quel.
        var date: Date
    }

    // MARK: - Construction

    /// Les lignes de la carte, dans l'ordre d'affichage.
    ///
    /// - Parameters:
    ///   - actions: toutes les actions connues. Le filtre `destinataire == .moi`
    ///     est fait ici, pour qu'un appelant ne puisse pas l'oublier.
    ///   - meetings: toutes les réunions connues, tête-à-tête compris — ils
    ///     sont écartés ici, pour la même raison.
    ///   - since: date du 1:1 précédent. `nil` à la première séance du fil :
    ///     « depuis le dernier 1:1 » veut alors dire « depuis toujours ».
    ///   - now: l'instant de référence, c'est-à-dire la **date de la séance**.
    static func build(actions: [ActionTask],
                      meetings: [Meeting],
                      since: Date?,
                      now: Date) -> [Item] {
        let miennes = actions.filter { $0.destinataire == .moi }
        let lignes = closedActionItems(miennes, since: since, now: now)
            + activeMeetingItems(meetings, since: since, now: now)
            + blockedActionItems(miennes, now: now)

        // Les livrés d'abord, du plus ancien au plus récent — l'ordre de la
        // capture, et l'ordre dans lequel on raconte ce qu'on a fait. Les
        // bloqués ferment la liste : ce ne sont pas des livrables, c'est ce
        // qu'il reste à débloquer.
        return lignes.sorted { gauche, droite in
            if gauche.status != droite.status { return gauche.status == .delivered }
            if gauche.date != droite.date { return gauche.date < droite.date }
            return gauche.text < droite.text
        }
    }

    /// Les actions closes de la fenêtre.
    private static func closedActionItems(_ actions: [ActionTask],
                                          since: Date?,
                                          now: Date) -> [Item] {
        actions.compactMap { action in
            guard action.isCompleted, let close = action.completedAt else { return nil }
            guard close <= now else { return nil }
            if let since, close <= since { return nil }

            var detail = "Action close le \(OneOnOneDateFormat.dayMonthOrdinal(close))"
            if let charge = effortLabel(minutes: action.effortMinutes) {
                detail += " · \(charge)"
            }
            return Item(id: "action-\(action.persistentModelID.hashValue)",
                        symbol: "✓",
                        text: action.title,
                        detail: detail,
                        status: .delivered,
                        reference: action.sourceRef,
                        date: close)
        }
    }

    /// Les réunions de la fenêtre où j'ai eu un rôle actif.
    private static func activeMeetingItems(_ meetings: [Meeting],
                                           since: Date?,
                                           now: Date) -> [Item] {
        meetings.compactMap { reunion in
            // Un tête-à-tête n'est pas un livrable : même définition que
            // `OneOnOneThreadStore.faceToFace`, pour qu'il n'y ait pas deux
            // listes de types 1:1 dans le projet.
            guard !OneOnOneThreadStore.faceToFace.contains(reunion.kind) else { return nil }
            guard reunion.date <= now else { return nil }
            if let since, reunion.date <= since { return nil }

            let notes = MeetingNoteStore.sorted(reunion.timedNotes)
            let decision = notes.first { $0.kind == .decision }
            let mienne = notes.first { $0.authorSide == .me }
            // « Rôle actif » se lit sur ce que la réunion a produit : une
            // décision, ou au moins une ligne que j'ai écrite. Une réunion où
            // je n'ai rien dit et rien noté n'est pas quelque chose que j'ai
            // livré, et l'inscrire gonflerait la colonne d'assistances muettes.
            guard let source = decision ?? mienne else { return nil }

            let quoi = decision != nil ? "a débloqué la décision" : "notes prises"
            return Item(id: "meeting-\(reunion.ensuredStableID.uuidString)",
                        symbol: "✓",
                        text: reunion.title,
                        detail: "Réunion du \(OneOnOneDateFormat.dayMonthOrdinal(reunion.date))"
                                + " · \(quoi)",
                        status: .delivered,
                        reference: SourceRef(kind: .note,
                                             stableID: source.ensuredStableID,
                                             t: source.t),
                        date: reunion.date)
        }
    }

    /// Les actions à moi qu'un blocage retient.
    private static func blockedActionItems(_ actions: [ActionTask], now: Date) -> [Item] {
        actions.compactMap { action in
            guard action.status == .open else { return nil }
            guard let cause = blockingCause(action) else { return nil }
            return Item(id: "blocked-\(action.persistentModelID.hashValue)",
                        symbol: "◐",
                        text: action.title,
                        detail: "En cours · \(cause)",
                        status: .blocked,
                        reference: action.sourceRef,
                        date: action.dueDate ?? now)
        }
    }

    /// La cause du blocage, ou `nil` quand rien ne bloque.
    ///
    /// Le commentaire prime sur le compteur de reports : il **nomme** la cause,
    /// et c'est la cause qu'un manager peut lever. Le compteur seul ne dit que
    /// l'ancienneté du problème.
    private static func blockingCause(_ action: ActionTask) -> String? {
        if let commentaire = blockingComment(action) {
            return decapitalized(commentaire.text)
        }
        guard action.deferralCount > 0 else { return nil }
        return action.deferralCount == 1
            ? "reporté une fois"
            : "reporté \(action.deferralCount) fois"
    }

    /// Le commentaire de blocage le plus récent : celui dont le texte replié
    /// commence par « bloqu » (`bloqué`, `bloquée`, `bloquant`…).
    ///
    /// Pas de colonne dédiée sur `ActionTask` : un blocage se dit dans un
    /// commentaire, c'est ce que les utilisateurs font déjà, et ajouter une
    /// colonne obligerait à la remplir deux fois.
    private static func blockingComment(_ action: ActionTask) -> ActionComment? {
        action.comments
            .filter { folded($0.text).hasPrefix("bloqu") }
            .max { $0.date < $1.date }
    }

    // MARK: - Charge

    /// `30min`, `4h`, `4h30`, `1 j`, `2 j`. `nil` quand la charge n'est pas
    /// estimée : une charge inventée sur une preuve se retrouverait dans un
    /// arbitrage (même règle que `CommitmentsRailModel.effortPill`).
    static func effortLabel(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        if minutes >= workdayMinutes {
            let jours = Double(minutes) / Double(workdayMinutes)
            let arrondi = (jours * 10).rounded() / 10
            return arrondi == arrondi.rounded()
                ? "\(Int(arrondi)) j"
                : String(format: "%.1f j", arrondi).replacingOccurrences(of: ".", with: ",")
        }
        guard minutes >= 60 else { return "\(minutes)min" }
        let heures = minutes / 60
        let reste = minutes % 60
        return reste == 0 ? "\(heures)h" : "\(heures)h\(String(format: "%02d", reste))"
    }

    // MARK: - En-tête

    /// `depuis le 21 août`, ou `depuis le début du fil` à la première séance :
    /// il n'y a alors pas de borne à annoncer, et une date inventée mentirait
    /// sur l'étendue de la liste.
    static func sinceLabel(_ since: Date?) -> String {
        guard let since else { return "depuis le début du fil" }
        return "depuis le \(OneOnOneDateFormat.dayMonthOrdinal(since))"
    }

    // MARK: - Citer (critère n° 3)

    /// Le texte de la note `proof` qu'un clic sur `Citer` insère.
    ///
    /// La provenance est dans le texte, et pas seulement dans le `sourceRef` :
    /// la ligne doit rester lisible dans le récap et dans le rapport, où la
    /// chaîne de citation n'est pas rendue.
    static func quoteText(_ item: Item) -> String {
        "\(item.text) — \(item.detail)"
    }

    // MARK: - Outils

    private static func folded(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "fr_FR"))
    }

    /// Première lettre en minuscule : le commentaire est écrit comme une phrase
    /// (`Bloqué par…`) et vient ici après un point médian (`En cours · …`).
    private static func decapitalized(_ text: String) -> String {
        let propre = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let premiere = propre.first else { return propre }
        return String(premiere).lowercased() + propre.dropFirst()
    }
}
