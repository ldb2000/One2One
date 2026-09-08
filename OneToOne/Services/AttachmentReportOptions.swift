import Foundation

/// Les trois cases du pied `À L'ENVOI DU RAPPORT` du tiroir Ressources
/// (spec §4.1, capture `3a-tiroir-ressources.png`).
///
/// Valeurs par défaut : **les deux premières cochées**. Joindre les pièces
/// épinglées et donner l'accès aux participants sont ce qu'on fait à chaque
/// séance ; verser dans les documents du projet est une décision, elle se
/// prend explicitement.
///
/// Persistées sur `Meeting.reportAttachmentOptionsJSON` — un choix par réunion,
/// pas un réglage global : une revue de projet et un 1:1 ne se diffusent pas
/// de la même façon. JSON et non trois colonnes : ce sont trois cases d'une
/// même intention, aucune n'est requêtable seule.
struct AttachmentReportOptions: Codable, Equatable, Sendable {

    /// Joindre au rapport les pièces épinglées pendant la séance.
    var attachPinned: Bool
    /// Donner l'accès aux participants présents.
    var grantAccessToParticipants: Bool
    /// Verser les pièces dans les documents du projet.
    var pushToProject: Bool

    /// Le pied à l'ouverture d'une réunion qui n'a rien réglé.
    static let defaults = AttachmentReportOptions(attachPinned: true,
                                                  grantAccessToParticipants: true,
                                                  pushToProject: false)

    init(attachPinned: Bool = true,
         grantAccessToParticipants: Bool = true,
         pushToProject: Bool = false) {
        self.attachPinned = attachPinned
        self.grantAccessToParticipants = grantAccessToParticipants
        self.pushToProject = pushToProject
    }

    /// Décode le JSON persisté. **Retombe sur les défauts** pour un JSON vide,
    /// tronqué ou écrit par une version future : un pied de tiroir sans cases
    /// serait un cul-de-sac, et une exception ici empêcherait d'ouvrir
    /// l'espace Ressources.
    static func decode(_ json: String) -> AttachmentReportOptions {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let options = try? JSONDecoder().decode(AttachmentReportOptions.self, from: data)
        else { return .defaults }
        return options
    }

    /// Encode pour la colonne. Rend `"{}"` si l'encodage échoue — ce qui se
    /// relit en défauts, jamais en plantage.
    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}

extension Meeting {

    /// Façade typée de `reportAttachmentOptionsJSON`. Même patron que
    /// `participantStatuses` : la vue lit et écrit une valeur, la colonne reste
    /// une chaîne.
    var reportAttachmentOptions: AttachmentReportOptions {
        get { AttachmentReportOptions.decode(reportAttachmentOptionsJSON) }
        set { reportAttachmentOptionsJSON = newValue.encoded() }
    }
}
