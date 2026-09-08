import Foundation

/// Une mise à jour de fiche projet **acceptée** en séance : ce que la variable
/// `{{fiche_projet.maj}}` rend dans le rapport (spec §8).
///
/// Le lot 9 ne persiste rien de l'acceptation — `ProjectCardSuggestions.accept`
/// mute un `ProjectCardDraft`, puis `ProjectCardDraft.apply(to:in:)` écrit
/// directement dans le `Project`. Après `Enregistrer`, plus rien ne dit qu'une
/// valeur vient d'une proposition validée : ni horodatage, ni citation, ni
/// lien vers la séance. Sans cette trace, le rapport devrait deviner ce que
/// l'utilisateur a validé — exactement ce que le critère n° 4 du chantier 3
/// (« aucune modification de la fiche projet n'est écrite sans validation
/// humaine explicite ») interdit de faire à sa place.
struct AcceptedProjectUpdate: Codable, Equatable, Sendable {

    var field: String
    var label: String
    /// La valeur enregistrée avant l'acceptation.
    var from: String
    var to: String
    /// La citation qui justifiait la proposition (`mm:ss texte`).
    var evidence: String

    /// Identité de la ligne, celle de `ProjectCardUpdate.id` : accepter deux
    /// fois la même proposition ne doit pas la tracer deux fois.
    var id: String { "\(field)|\(label)" }
}

extension Meeting {

    /// Façade typée de `acceptedProjectUpdatesJSON`. Même patron que
    /// `reportAttachmentOptions` : la vue lit et écrit une valeur, la colonne
    /// reste une chaîne.
    ///
    /// Un JSON illisible se relit en tableau vide — une exception ici
    /// empêcherait d'ouvrir l'espace Rapport, ce qui serait un prix absurde
    /// pour une trace d'audit.
    var acceptedProjectUpdates: [AcceptedProjectUpdate] {
        get {
            guard !acceptedProjectUpdatesJSON.isEmpty,
                  let data = acceptedProjectUpdatesJSON.data(using: .utf8),
                  let items = try? JSONDecoder().decode([AcceptedProjectUpdate].self, from: data)
            else { return [] }
            return items
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                acceptedProjectUpdatesJSON = "[]"
                return
            }
            acceptedProjectUpdatesJSON = json
        }
    }
}

extension ProjectCardSuggestions {

    /// Trace une acceptation sur la séance. Idempotent sur
    /// `ProjectCardUpdate.id`.
    ///
    /// `meeting == nil` (la feuille ouverte hors séance) ne trace rien : il n'y
    /// a alors pas de rapport à alimenter, et inventer un rattachement ferait
    /// remonter la mise à jour dans une réunion qui ne l'a pas produite.
    @MainActor
    static func recordAcceptance(_ update: ProjectCardUpdate, in meeting: Meeting?) {
        guard let meeting else { return }
        let entree = AcceptedProjectUpdate(field: update.field.rawValue,
                                           label: update.displayLabel,
                                           from: update.current,
                                           to: update.proposed,
                                           evidence: update.evidence)
        var toutes = meeting.acceptedProjectUpdates
        guard !toutes.contains(where: { $0.id == entree.id }) else { return }
        toutes.append(entree)
        meeting.acceptedProjectUpdates = toutes
        try? meeting.modelContext?.save()
    }
}
