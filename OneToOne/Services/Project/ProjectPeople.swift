import Foundation

/// Qui porte un projet — **la relation fait foi** (décision **D3**, tranchée
/// par Laurent le 2026-09-09).
///
/// `Project` porte deux fois chaque rôle : une chaîne libre venue de l'import
/// xlsx (`chefDeProjet`, `architecte`) et une relation vers un `Collaborator`
/// connu de l'application (`projectManager`, `technicalArchitect`). Les deux
/// se contredisent — le semis en a un exemple, `P25_099`, dont le xlsx écrit
/// « NOMINE Laurent » alors qu'aucun collaborateur n'est lié.
///
/// D3 tranche : **la colonne « Chef de projet » du Portfolio, la carte
/// Interlocuteurs de l'écran projet et la règle « fiche incomplète » lisent la
/// relation, et rien d'autre.** Un projet dont la relation manque affiche
/// « Non affecté », même si la chaîne porte un nom. La chaîne ne disparaît pas
/// pour autant : c'est elle qui préremplit le sélecteur de l'action
/// « Compléter » de la vue « À risque » (`suggestedManager`), pour que la mise
/// en conformité soit un clic par projet.
enum ProjectPeople {

    /// Ce qu'affiche une colonne de rôle vide, en italique et en `inkMuted`
    /// (capture 1a, ligne `P25_193`).
    static let nonAffecte = "Non affecté"

    // MARK: - Ce qui s'affiche

    /// Le chef de projet, ou `nil` — `projectManager?.name` seulement.
    ///
    /// Un nom réduit à des espaces compte pour vide : un `Collaborator` sans
    /// nom afficherait une colonne blanche, ce qui se lit comme un bogue et
    /// non comme « non affecté ».
    static func manager(of project: Project) -> String? {
        nomAffichable(project.projectManager?.name)
    }

    /// L'architecte technique, ou `nil` — `technicalArchitect?.name`
    /// seulement. Même règle que le chef de projet, dit D3.
    static func architect(of project: Project) -> String? {
        nomAffichable(project.technicalArchitect?.name)
    }

    // MARK: - Ce que « Compléter » propose

    /// Le collaborateur que l'action « Compléter » doit présélectionner pour le
    /// rôle de chef de projet : celui dont le nom correspond à la chaîne
    /// `chefDeProjet` importée du xlsx.
    ///
    /// Correspondance insensible à la casse et aux accents (D3), sur le nom
    /// **entier** : « RIGAUT Manuel » ne doit pas proposer « RIGAUT Manuela ».
    /// `nil` si la chaîne est vide ou si aucun collaborateur ne porte ce nom —
    /// il n'y a alors rien à préremplir, et le sélecteur s'ouvre vide.
    ///
    /// La relation déjà posée n'est **pas** consultée : la fonction répond
    /// « qui ce nom désigne-t-il ? », pas « faut-il compléter ? ». C'est
    /// l'appelant qui sait s'il a besoin d'une suggestion.
    static func suggestedManager(for project: Project,
                                 among collaborators: [Collaborator]) -> Collaborator? {
        collaborateur(nomme: project.chefDeProjet, among: collaborators)
    }

    /// Le pendant pour l'architecte technique, sur `Project.architecte`.
    static func suggestedArchitect(for project: Project,
                                   among collaborators: [Collaborator]) -> Collaborator? {
        collaborateur(nomme: project.architecte, among: collaborators)
    }

    // MARK: - Mécanique

    private static func nomAffichable(_ nom: String?) -> String? {
        guard let nom else { return nil }
        let net = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        return net.isEmpty ? nil : net
    }

    private static func collaborateur(nomme nom: String,
                                      among collaborators: [Collaborator]) -> Collaborator? {
        let attendue = clef(nom)
        guard !attendue.isEmpty else { return nil }
        return collaborators.first { clef($0.name) == attendue }
    }

    /// Casse, accents et espaces de bord pliés — même normalisation que
    /// `ProjectValueList.normalizedKey`, pour la même raison.
    private static func clef(_ valeur: String) -> String {
        valeur.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
