import Foundation

/// La recherche de projets — **une seule** dans l'application (décision **D7**).
///
/// Il y en avait trois : `projectMatches` dans `Sidebar.swift` (nom, code,
/// domaine, notes), le filtre de `MeetingsProjectFilterPicker` et celui de
/// `SearchPopover`, chacun avec ses champs. Le handoff en demandait une
/// quatrième pour la palette `⌘K`, avec le sponsor. D'où ce service : la barre
/// latérale l'appelle dès ce lot, le Portfolio au lot 2, la palette au lot 3 —
/// et les deux filtres historiques y migrent avec elle.
///
/// **Trois questions, trois fonctions.** « Ce projet correspond-il ? »
/// (`matches`), « dans quel ordre les montrer ? » (`rank`) et « où surligner le
/// terme trouvé ? » (`highlightRanges`, qui alimentera le fond `highlight` de
/// la capture 1c). Aucune ne touche au store : ce sont des fonctions pures,
/// testées avant la vue, comme le veut la règle du dépôt.
///
/// **La comparaison plie la casse et les accents.** « financiere » trouve
/// « Direction financière » : les noms de projet du portfolio externe portent
/// des accents que personne ne tape dans un champ de recherche.
enum ProjectSearch {

    // MARK: - Correspondance

    /// Le projet correspond-il au terme ?
    ///
    /// Champs lus : nom, code, domaine, **sponsor**, **chef de projet**,
    /// **architecte**, et les notes fournies. Les trois derniers sont l'apport
    /// de D7 sur l'ancien prédicat de la barre latérale.
    ///
    /// - Parameters:
    ///   - notes: les notes à fouiller. Le paramètre existe parce que
    ///     `Meeting` ne se remonte pas depuis `Project` (la relation n'a pas
    ///     d'inverse) : l'appelant passe la liste qu'il a déjà sous la main, et
    ///     celles qui ne portent pas ce projet sont ignorées ici.
    /// - Returns: `true` pour un terme vide — pas de terme, pas de filtre.
    static func matches(_ project: Project, query: String, notes: [Meeting] = []) -> Bool {
        let terme = normalise(query)
        guard !terme.isEmpty else { return true }
        if champs(of: project).contains(where: { contient($0, terme) }) { return true }
        return notes.contains { note in
            note.project?.persistentModelID == project.persistentModelID
                && (contient(note.title, terme) || contient(note.liveNotes, terme))
        }
    }

    /// Ces champs contiennent-ils le terme ?
    ///
    /// La même comparaison que `matches` — casse et accents pliés, terme vide
    /// = pas de filtre — pour les appelants qui ne tiennent pas un `Project`
    /// sous la main. Le Portfolio filtre des `PortfolioRow` (décision **D11** :
    /// les lignes sont calculées d'avance) et n'a plus le projet ; il ne doit
    /// pas pour autant écrire une seconde comparaison, ce que D7 interdit.
    static func matches(fields: [String], query: String) -> Bool {
        let terme = normalise(query)
        guard !terme.isEmpty else { return true }
        return fields.contains { contient($0, terme) }
    }

    // MARK: - Classement

    /// Les projets correspondants, du plus pertinent au moins pertinent.
    ///
    /// Trois clés, dans cet ordre :
    ///
    /// 1. **La nature de la correspondance** — un nom (ou un code) qui
    ///    *commence* par le terme passe avant un nom dont un *mot* commence par
    ///    le terme, lui-même avant une simple sous-chaîne. C'est la clé
    ///    principale : taper « ged » doit rendre « GED – refonte » avant
    ///    « MEGEDIS », même si le second est épinglé.
    /// 2. **L'épinglage**, à pertinence égale.
    /// 3. **Le nom**, pour que deux lancements donnent le même ordre.
    ///
    /// Les notes ne sont pas fouillées ici : un classement se recalcule à
    /// chaque frappe, et scanner les corps de notes n'y tiendrait pas. C'est
    /// `matches` qui les lit, quand l'appelant les fournit.
    static func rank(_ projects: [Project], query: String) -> [Project] {
        let terme = normalise(query)
        guard !terme.isEmpty else {
            return projects.sorted { avant($0, $1, rangA: 0, rangB: 0) }
        }
        return projects
            .filter { matches($0, query: terme) }
            .map { (projet: $0, rang: rang($0, terme)) }
            .sorted { a, b in avant(a.projet, b.projet, rangA: a.rang, rangB: b.rang) }
            .map(\.projet)
    }

    // MARK: - Surlignage

    /// Les plages de `text` à surligner pour ce terme, de la première à la
    /// dernière, sans chevauchement.
    ///
    /// Casse et accents pliés comme pour la correspondance : le terme « etats »
    /// surligne « états ». Un terme vide ne surligne rien — un surlignage vide
    /// est un rendu valide, pas une erreur.
    static func highlightRanges(in text: String, query: String) -> [Range<String.Index>] {
        let terme = normalise(query)
        guard !terme.isEmpty, !text.isEmpty else { return [] }
        var plages: [Range<String.Index>] = []
        var depart = text.startIndex
        while depart < text.endIndex,
              let plage = text.range(of: terme,
                                     options: [.caseInsensitive, .diacriticInsensitive],
                                     range: depart..<text.endIndex) {
            plages.append(plage)
            // Une plage vide ne peut pas se produire (le terme n'est pas vide),
            // mais avancer d'au moins un caractère garantit la terminaison.
            depart = plage.upperBound > plage.lowerBound
                ? plage.upperBound
                : text.index(after: plage.lowerBound)
        }
        return plages
    }

    // MARK: - Les champs lus

    /// Les champs de texte d'un projet, dans l'ordre de leur importance.
    ///
    /// Le chef de projet et l'architecte sont lus **par la relation puis par la
    /// chaîne** (décision **D3** : la relation fait foi). Un projet dont la
    /// relation manque reste donc trouvable par le nom que l'import xlsx a
    /// écrit — c'est le cas `P25_099` du semis, et l'action « Compléter » du
    /// lot 5 est précisément là pour le résoudre.
    private static func champs(of project: Project) -> [String] {
        [project.name,
         project.code,
         project.domain,
         project.sponsor,
         project.projectManager?.name ?? project.chefDeProjet,
         project.technicalArchitect?.name ?? project.architecte]
    }

    // MARK: - Mécanique

    /// Le terme, débarrassé de ses espaces de bord.
    private static func normalise(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Casse et accents pliés — la comparaison de tout ce fichier.
    private static func contient(_ champ: String, _ terme: String) -> Bool {
        guard !champ.isEmpty else { return false }
        return champ.range(of: terme,
                           options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func plie(_ valeur: String) -> String {
        valeur.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// `0` préfixe, `1` mot, `2` sous-chaîne. Voir `rank`.
    private static func rang(_ project: Project, _ terme: String) -> Int {
        let plieTerme = plie(terme)
        if plie(project.name).hasPrefix(plieTerme) || plie(project.code).hasPrefix(plieTerme) {
            return 0
        }
        for champ in champs(of: project) {
            let mots = plie(champ).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            if mots.contains(where: { $0.hasPrefix(plieTerme) }) { return 1 }
        }
        return 2
    }

    /// L'ordre entre deux projets déjà rangés : pertinence, épinglage, nom.
    private static func avant(_ a: Project, _ b: Project, rangA: Int, rangB: Int) -> Bool {
        if rangA != rangB { return rangA < rangB }
        if a.pinned != b.pinned { return a.pinned }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
