import Foundation
import SwiftData

/// Ce que la capture `2a-1to1-manager-seance.png` montre **en plus** du jeu du
/// lot 10 : les quatre cartes d'engagement de la séance, la criticité de
/// l'arbitrage, la charge de la formation, l'ancienneté de Laurent, et la
/// deuxième ligne de `TENUS DEPUIS LE DERNIER 1:1`.
///
/// Complète, ne remplace pas : `seedOneOnOneThreads` (lot 10) reste le point
/// d'entrée du domaine, et son fichier n'est pas touché. Tout est **idempotent**
/// — les ajouts sont gardés par leur texte, les ajustements sont des
/// affectations.
@MainActor
extension RefonteDemoSeed {

    /// Nom de l'utilisateur de l'application dans le jeu de démonstration :
    /// c'est lui qui porte les initiales `YP` de la capture.
    static let sessionOwnerName = collaboratorThreadManager

    /// Ancienneté de Laurent NOMINÉ : `dans l'équipe depuis 3 ans`.
    static let managerThreadSeniorityYears: Double = 3.2

    /// Point d'entrée du lot 11.
    ///
    /// - Returns: le fil manager et sa dernière séance — celle de la capture.
    @discardableResult
    static func seedLot11(in context: ModelContext) -> (thread: OneOnOneThread,
                                                        meeting: Meeting)? {
        let fils = seedOneOnOneThreads(in: context)
        let fil = fils.manager
        guard let seance = OneOnOneThreadStore.meetings(of: fil, now: oneOnOneSeedDate).last
        else { return nil }

        seedOwnerName(in: context)
        seedSeniority(fil)
        seedSessionCommitments(fil, seance, in: context)
        seedLedgerLine(fil)
        try? context.save()
        return (fil, seance)
    }

    // MARK: - L'utilisateur de l'application

    /// Sans `ownerName`, les avatars de « Moi · 2 » afficheraient `?` : le rail
    /// tire ses initiales de l'utilisateur de l'application, pas du fil.
    private static func seedOwnerName(in context: ModelContext) {
        let tous = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        let reglages: AppSettings
        if let existants = tous.canonicalSettings {
            reglages = existants
        } else {
            reglages = AppSettings()
            context.insert(reglages)
        }
        guard reglages.ownerName.isEmpty else { return }
        reglages.ownerName = sessionOwnerName
    }

    // MARK: - Ancienneté

    private static func seedSeniority(_ fil: OneOnOneThread) {
        guard let laurent = fil.collaborator, laurent.joinedAt == nil else { return }
        laurent.joinedAt = oneOnOneSeedDate
            .addingTimeInterval(-managerThreadSeniorityYears * 365.25 * 86_400)
    }

    // MARK: - Les quatre cartes du rail

    /// `ENGAGEMENTS DE CETTE SÉANCE` : deux par côté.
    ///
    /// Le lot 10 en sème déjà deux (l'arbitrage du Webcast et la formation
    /// Admin) ; les deux autres manquaient, et deux détails de la capture
    /// n'existaient pas encore comme données : la criticité `Bloquant pour lui`
    /// et la charge `4h`.
    private static func seedSessionCommitments(_ fil: OneOnOneThread,
                                               _ seance: Meeting,
                                               in context: ModelContext) {
        // L'arbitrage : échéance **le jour de la séance** (vendredi 4
        // septembre), pour que la pilule affiche `Vendredi` comme la capture —
        // un « vendredi » ne veut dire quelque chose que dans la semaine où il
        // est prononcé. Et il bloque Laurent : c'est ce qui justifie la pilule
        // rouge.
        if let arbitrage = engagement("Arbitrer renfort ou décalage du Webcast", in: fil) {
            arbitrage.dueAt = oneOnOneSeedDate
            arbitrage.blocksOther = true
            arbitrage.promisedInMeeting = seance
        }

        // La formation porte une charge : elle vient d'une action liée, jamais
        // d'une estimation inventée depuis le texte.
        if let formation = engagement("Cadrer la formation Admin (plan + 2 dates)", in: fil) {
            formation.promisedInMeeting = seance
            if formation.linkedAction == nil {
                let action = ActionTask(title: "Cadrer la formation Admin (plan + 2 dates)")
                action.effortMinutes = 240
                action.collaborator = fil.collaborator
                action.createdAt = oneOnOneSeedDate
                context.insert(action)
                formation.linkedAction = action
            }
        }

        let manquants: [(texte: String, cote: OneOnOneSide, echeance: Double,
                         visibilite: Visibility)] = [
            // La carte `● privé 30 sept.` : un engagement que je prends sur un
            // sujet dont je ne veux pas encore parler à Laurent.
            ("Ouvrir le sujet mobilité archi avec Claire-Amélie", .manager, 26, .private),
            ("Chiffrer la reprise AP restante", .collaborator, 5, .shared)
        ]
        for ligne in manquants where engagement(ligne.texte, in: fil) == nil {
            let nouveau = Commitment(
                text: ligne.texte,
                ownerSide: ligne.cote,
                dueAt: oneOnOneSeedDate.addingTimeInterval(ligne.echeance * 86_400),
                state: .open,
                promisedAt: oneOnOneSeedDate,
                visibility: ligne.visibilite
            )
            context.insert(nouveau)
            nouveau.thread = fil
            nouveau.promisedInMeeting = seance
        }
    }

    // MARK: - Tenus depuis le dernier 1:1

    /// La deuxième ligne de la capture (`✓ Accès environnement recette — YP`)
    /// est un engagement **du manager**, soldé depuis la dernière séance.
    ///
    /// Le lot 10 l'avait semé côté collaborateur et soldé deux mois plus tôt,
    /// pour tenir l'arithmétique de la capture 2b : « 8 tenus sur 11 » ne
    /// change pas ici (l'état reste `kept`), seuls le porteur et la date de
    /// solde bougent — c'est ce qui le fait entrer dans la fenêtre « depuis le
    /// dernier 1:1 ».
    private static func seedLedgerLine(_ fil: OneOnOneThread) {
        guard let acces = engagement("Accès environnement recette", in: fil) else { return }
        acces.ownerSide = .manager
        acces.settledAt = oneOnOneSeedDate.addingTimeInterval(-10 * 86_400)
    }

    // MARK: - Outils

    private static func engagement(_ texte: String, in fil: OneOnOneThread) -> Commitment? {
        fil.commitments.first { $0.text == texte }
    }
}
