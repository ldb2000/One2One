import Foundation

/// Construit et lit l'URL `onetoone://date/…` portée par `.mdLink` sur une
/// date insérée depuis le menu `/` — pendant de `MentionCatalog`
/// (`onetoone://collaborator/<uuid>`) pour les dates, voir
/// `docs/superpowers/specs/2026-08-05-dates-et-rappels.md` (chantier 1) et
/// son annotation du 2026-08-06 : la spec prévoyait ce lien **avant** le
/// popover (`SlashDatePickerPresenter`, `DateReminder`), qui a été livré en
/// premier — ce fichier comble l'écart. Logique pure, sans `NSTextView`,
/// testable telle quelle.
///
/// Format du chemin : la date en ISO 8601 (`AAAA-MM-JJ`), suivie de
/// `'T'HH:mm` si une heure a été choisie — ex. `onetoone://date/2026-08-05`,
/// `onetoone://date/2026-08-06T13:08`. Le rappel choisi, s'il n'est pas
/// `.none`, est porté par le paramètre de requête `reminder` sous forme d'une
/// durée ISO 8601 (`P0D`/`P1D`/`P2D`/`P1W`) — ex.
/// `onetoone://date/2026-08-05?reminder=P1D`. Ces trois formes sont les
/// exemples exacts de la spec.
///
/// Le libellé visible (français long, ex. `"@5 août 2026"`) est construit
/// séparément par `SlashController` (`dateInsertionFormatter`/
/// `timeInsertionFormatter`, déjà utilisés par le popover et ses tests) :
/// ce fichier ne s'occupe que de la donnée structurée dans l'URL, en ISO
/// 8601 — lisible par une machine, stable au changement de locale, comme la
/// spec le demande.
enum DateLinkCatalog {

    /// Partie date seule du chemin (`AAAA-MM-JJ`) — `en_US_POSIX` et un fuseau
    /// horaire fixé explicitement : ni la locale ni le fuseau de l'utilisateur
    /// ne doivent influencer une donnée censée être stable et relisable par
    /// une machine (même raisonnement que la spec pour préférer l'ISO 8601 au
    /// format d'affichage). `.current` conserve le jour affiché à l'écran
    /// (celui que l'utilisateur a choisi dans le calendrier) plutôt que de le
    /// décaler vers UTC, ce qui déplacerait la date d'un jour près de minuit
    /// pour un fuseau non nul.
    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    /// Partie date+heure du chemin (`AAAA-MM-JJ'T'HH:mm`) — même
    /// raisonnement que `isoDateFormatter` sur la locale et le fuseau.
    private static let isoDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    /// Jeton de requête `reminder=` pour chaque valeur de `DateReminder` où
    /// un rappel est réellement demandé — `.none` n'apparaît jamais ici : le
    /// paramètre est alors omis de l'URL plutôt que porter une valeur
    /// « aucun » (voir `dateURL(date:includesTime:reminder:)`).
    ///
    /// Durées ISO 8601 valides dans les quatre cas : `.sameDayAt9` n'est pas,
    /// à proprement parler, un décalage *avant* l'échéance — mais « zéro jour
    /// avant » (`P0D`) porte la même intention (rappel le jour même) tout en
    /// restant une durée ISO 8601 syntaxiquement correcte ; l'heure fixe
    /// (9 h) associée à ce choix est une convention d'affichage du popover
    /// (`DateReminder.label`), pas une donnée qui a besoin de tenir dans
    /// cette durée.
    private static let reminderTokens: [DateReminder: String] = [
        .sameDayAt9: "P0D",
        .dayBefore: "P1D",
        .twoDaysBefore: "P2D",
        .oneWeekBefore: "P1W"
    ]

    /// URL de date pour `date`/`includesTime`/`reminder` — symétrique de
    /// `selection(from:)`. Construite via `URLComponents` plutôt que par
    /// interpolation de chaîne (même précédent que `mentionURL(for:)` sur le
    /// choix de ne jamais produire d'URL invalide) : les seuls caractères en
    /// jeu — chiffres, tiret, `T`, `:` pour le chemin ; lettres/chiffres pour
    /// le jeton de rappel — sont tous valides sans pourcent-encodage dans
    /// leurs composants respectifs (vérifié : `URLComponents` ne les encode
    /// pas), donc `components.url` ne peut pas échouer ici.
    static func dateURL(date: Date, includesTime: Bool, reminder: DateReminder) -> URL {
        let path = includesTime
            ? isoDateTimeFormatter.string(from: date)
            : isoDateFormatter.string(from: date)
        var components = URLComponents()
        components.scheme = "onetoone"
        components.host = "date"
        components.path = "/\(path)"
        if let token = reminderTokens[reminder] {
            components.queryItems = [URLQueryItem(name: "reminder", value: token)]
        }
        return components.url!
    }

    /// Lit `url` et reconstruit la sélection qu'elle représente ; `nil` si
    /// `url` n'a pas exactement la forme produite par `dateURL(date:includesTime:reminder:)`
    /// (schéma ou hôte différents, chemin ni `AAAA-MM-JJ` ni
    /// `AAAA-MM-JJ'T'HH:mm`). Symétrique de `dateURL`, comme
    /// `MentionCatalog.collaboratorID(from:)` l'est de `mentionURL(for:)` —
    /// garantit que le format choisi est bien résoluble.
    ///
    /// Un paramètre `reminder` présent mais dont la valeur ne correspond à
    /// aucun jeton connu **ne fait pas échouer** l'ensemble du parsing : la
    /// date reste résoluble, seul le rappel retombe sur `.none` — dégradation
    /// volontaire plutôt que perte totale d'une date par ailleurs valide (un
    /// futur jeton de rappel encore inconnu de cette version ne doit pas
    /// rendre la date elle-même illisible).
    static func selection(from url: URL) -> SlashDateSelection? {
        guard url.scheme == "onetoone", url.host == "date" else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let reminder = reminder(from: url)
        if let date = isoDateTimeFormatter.date(from: path) {
            return SlashDateSelection(date: date, includesTime: true, reminder: reminder)
        }
        if let date = isoDateFormatter.date(from: path) {
            return SlashDateSelection(date: date, includesTime: false, reminder: reminder)
        }
        return nil
    }

    /// `.none` si `url` ne porte pas de paramètre `reminder`, ou si sa valeur
    /// ne correspond à aucun jeton de `reminderTokens` — voir la doc de
    /// `selection(from:)` sur ce choix de dégradation.
    private static func reminder(from url: URL) -> DateReminder {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let token = components.queryItems?.first(where: { $0.name == "reminder" })?.value
        else { return .none }
        return reminderTokens.first { $0.value == token }?.key ?? .none
    }
}
