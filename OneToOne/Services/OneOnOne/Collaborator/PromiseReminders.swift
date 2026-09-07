import Foundation
import SwiftData
import UserNotifications
import os

private let relanceLog = Logger(subsystem: "com.onetoone.app", category: "oneonone")

/// Le bouton `Relancer` d'une promesse du manager (spec §6.2 : « `Relancer`
/// (crée un rappel et un item d'ordre du jour pour le prochain 1:1) »).
///
/// Trois effets, et un seul geste : le compteur de relances monte, un sujet
/// privé attend à l'ordre du jour de la séance suivante, et un rappel système
/// se pose si l'autorisation existe.
///
/// **Ce que `Relancer` n'est pas** : un report. `CommitmentLedger.postpone`
/// incrémente `deferralCount`, qui compte les fois où le **manager** a repoussé
/// sa parole. Relancer est mon geste à moi ; le confondre avec le sien
/// gonflerait le compteur de reports d'un chiffre que le manager n'a pas
/// produit, et ce compteur est précisément ce que la spec veut voir affiché
/// « sans exception ».
@MainActor
enum PromiseReminders {

    /// Le sujet d'ordre du jour d'une relance. Lisible seul : il apparaîtra
    /// dans un brouillon de séance, quinze jours plus tard, sans la carte qui
    /// l'a produit sous les yeux.
    static func agendaText(for commitment: Commitment) -> String {
        "Relancer : \(commitment.text)"
    }

    /// Relance la promesse.
    ///
    /// **Idempotent par le texte** : le bouton n'est pas désactivé après le
    /// premier clic (rien ne le dirait à l'écran), donc un second clic
    /// n'ajoute pas un second sujet — il incrémente le compteur du sujet
    /// existant. Même règle que `ReminderRules.toAgendaItems`.
    ///
    /// - Parameters:
    ///   - nextMeeting: la séance suivante du fil, `nil` si aucune n'est
    ///     planifiée. Le sujet est alors créé **sans cible** : un sujet sans
    ///     séance est à l'ordre du jour de la prochaine
    ///     (`AgendaCarryover.items`), ce qui vaut mieux qu'une relance perdue.
    ///   - notify: le poste du rappel système. `nil` = aucun rappel. Injecté
    ///     pour que la règle « une relance, un rappel » soit vérifiable sans
    ///     `UNUserNotificationCenter`, qui n'existe pas hors bundle `.app`.
    ///     Sans valeur par défaut à dessein : une expression par défaut
    ///     s'évalue dans un contexte non isolé, où `postSystemReminder` — qui
    ///     est `@MainActor` — n'est pas appelable.
    /// - Returns: le sujet d'ordre du jour, créé ou retrouvé.
    @discardableResult
    static func remind(_ commitment: Commitment,
                       in thread: OneOnOneThread,
                       nextMeeting: Meeting?,
                       in context: ModelContext,
                       notify: ((String) -> Void)?)
        -> OneOnOneAgendaItem {
        let texte = agendaText(for: commitment)

        let sujet = thread.agendaItems.first { $0.text == texte } ?? {
            let rang = (thread.agendaItems.map(\.order).max() ?? -1) + 1
            let nouveau = OneOnOneAgendaItem(text: texte,
                                             addedBySide: .collaborator,
                                             order: rang,
                                             state: .todo,
                                             visibility: CollaboratorNotePrivacy
                                                 .defaultVisibility,
                                             kind: .topic)
            context.insert(nouveau)
            nouveau.thread = thread
            nouveau.meeting = nextMeeting
            return nouveau
        }()

        // `remindedCount` du sujet, et non du `Commitment` : le modèle ne porte
        // pas de compteur de relances côté engagement, et le sujet est
        // justement la trace persistée de mes relances.
        sujet.remindedCount += 1
        try? context.save()

        notify?(texte)
        relanceLog.info("relance: n=\(sujet.remindedCount)")
        return sujet
    }

    /// La relance de l'écran : celle qui pose aussi le rappel système.
    ///
    /// L'appel que fait la vue. Une surcharge et non une valeur par défaut,
    /// pour la raison ci-dessus.
    @discardableResult
    static func remind(_ commitment: Commitment,
                       in thread: OneOnOneThread,
                       nextMeeting: Meeting?,
                       in context: ModelContext) -> OneOnOneAgendaItem {
        remind(commitment, in: thread, nextMeeting: nextMeeting, in: context,
               notify: postSystemReminder)
    }

    /// Le rappel système, sans dialogue bloquant.
    ///
    /// N'instancie `UNUserNotificationCenter` que dans un bundle `.app` — même
    /// garde, et même raison, que `MeetingNotificationService` : hors
    /// application, `current()` lève une exception que Swift ne rattrape pas.
    /// Ne demande **aucune** autorisation : si elle n'a pas déjà été accordée,
    /// le rappel ne part pas, et l'entretien continue. Le sujet d'ordre du jour
    /// est de toute façon la trace qui compte.
    static func postSystemReminder(_ texte: String) {
        guard Bundle.main.bundleURL.pathExtension.lowercased() == "app" else { return }
        let centre = UNUserNotificationCenter.current()
        centre.getNotificationSettings { reglages in
            guard reglages.authorizationStatus == .authorized else { return }
            let contenu = UNMutableNotificationContent()
            contenu.title = "À relancer au prochain 1:1"
            contenu.body = texte
            contenu.sound = .default
            let requete = UNNotificationRequest(
                identifier: "oneonone.relance.\(UUID().uuidString)",
                content: contenu,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
            centre.add(requete, withCompletionHandler: nil)
        }
    }
}
