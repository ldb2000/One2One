import Foundation
import SwiftData

/// Le modèle de vue de l'écran de séance du 1:1 **subi** (capture 5a,
/// spec §6.2) — **pur** : intitulés, tons, listes, comptages. Aucune écriture.
///
/// Même parti que `CommitmentsRailModel` au lot 11 : ce que l'écran ajoute aux
/// services du lot 10 (les titres, les pilules, les invites de vide, la
/// répartition en deux sections) vit ici, testé, plutôt que dans le corps d'une
/// `View` où seul l'œil pourrait le vérifier.
///
/// Ne recalcule rien de ce que le lot 10 sait déjà faire : le niveau d'alerte
/// d'une demande et son historique viennent de `AgendaCarryover`, le tri par
/// retard et le compteur de reports de `CommitmentLedger`, le compte des lignes
/// exclues de `OneOnOneRecapBuilder`.
@MainActor
enum CollaboratorSessionModel {

    // MARK: - Colonne gauche

    static let myTopicsTitle = "CE QUE JE VEUX DIRE"
    /// La pilule en tête de carte (spec §6.2 : « tous `private` par défaut avec
    /// la pilule `● privé` en tête de carte »).
    static let privacyPill = "● privé"
    /// La mention explicite de la spec, au mot près. Affichée **sans
    /// condition** : c'est une promesse faite à celui qui écrit, pas un état de
    /// la carte.
    static let myTopicsMention =
        "Visible de vous seul. Vous choisissez à la fin ce qui part dans le récap partagé."
    static let myTopicsComposerPlaceholder = "Ajouter un sujet…"
    static let dragHint = "glisser pour classer"
    /// La poignée de glissement de la capture.
    static let dragHandle = "⠿"
    static let myTopicsEmptyInvite =
        "Aucun sujet — écrivez ci-dessous ce que vous ne voulez pas oublier de dire."

    static let requestsTitle = "MES DEMANDES EN COURS"
    static let requestsEmptyInvite =
        "Aucune demande suivie — tapez /demande dans les notes pour en poser une."

    // MARK: - Colonne centrale

    static let notesTitle = "Notes de l'entretien"
    /// La pilule violette d'en-tête. Un **état**, pas un bouton : côté
    /// collaborateur, le défaut n'est pas négociable (spec §6.1).
    static let defaultPrivacyPill = "● Privé par défaut"
    /// Le geste explicite du critère n° 2.
    static let shareLinePill = "Partager la ligne"
    static let heardTitle = "CE QU'IL M'A DIT"
    static let saidTitle = "CE QUE J'AI DIT"
    /// Le libellé du bloc privé, côté subi. Le lot 11 nomme l'audience
    /// (`● NOTE PRIVÉE — VOUS SEUL`) ; la capture 5a la nomme autrement, plus
    /// court, parce qu'ici **toutes** les lignes sont privées et que le bloc
    /// n'a pas à répéter le mot.
    static let privateBlockLabel = "● POUR MOI SEUL"
    static let heardEmptyInvite = "Rien encore — écrivez ce qu'il vous dit, tel qu'il le dit."
    static let saidEmptyInvite = "Rien encore — écrivez ce que vous avez posé sur la table."
    static let composerPlaceholder = "Écrire…"

    // MARK: - Colonne droite

    static let promisesTitle = "CE QU'IL M'A PROMIS"
    static let promisesEmptyInvite =
        "Aucune promesse en cours — tapez /promesse quand il s'engage à l'oral."
    static let remindButtonLabel = "Relancer"

    static let closingTitle = "EN SORTANT"
    static let annualFolderButtonLabel = "Verser dans mon dossier annuel"

    // MARK: - Mes sujets

    /// `1`, `2`, `3` — le numéro affiché devant un sujet.
    ///
    /// Une fonction et non une interpolation dans la vue : c'est la
    /// numérotation qui dit que le brouillon a un **ordre**, et que le glisser
    /// le change.
    static func topicNumber(_ index: Int) -> String { "\(index + 1)" }

    /// Les sujets de brouillon de la séance, dans l'ordre manuel.
    ///
    /// Les demandes en sont **exclues** : elles ont leur propre carte, et une
    /// demande qui apparaîtrait deux fois donnerait l'impression de deux
    /// sujets distincts (même règle que `ManagerAgendaModel.pendingEntries`).
    static func myTopics(_ thread: OneOnOneThread,
                         for meeting: Meeting) -> [OneOnOneAgendaItem] {
        AgendaCarryover.items(of: thread, for: meeting).filter { $0.kind == .topic }
    }

    /// Les demandes suivies du fil, toutes séances confondues.
    ///
    /// Le fil et non la séance : une demande posée en juillet est « en cours »
    /// tant qu'elle n'a pas de réponse, et c'est précisément son ancienneté que
    /// la carte montre.
    static func requests(_ thread: OneOnOneThread) -> [OneOnOneAgendaItem] {
        AgendaCarryover.requests(of: thread)
    }

    /// Le ton d'une demande (spec §6.2). Traduit le niveau du lot 10 en ton de
    /// pilule : la règle des 60 jours vit dans `AgendaCarryover`, pas ici.
    static func requestTone(_ item: OneOnOneAgendaItem, now: Date) -> ChipTon {
        switch AgendaCarryover.requestLevel(item, now: now) {
        case .ok:     return .ok
        case .warn:   return .warn
        case .report: return .report
        }
    }

    // MARK: - Les deux sections de notes

    /// `CE QU'IL M'A DIT` : les lignes dont l'auteur est le **manager**.
    static func heardSectionNotes(_ meeting: Meeting) -> [MeetingNote] {
        spokenNotes(meeting).filter { $0.authorSide == .manager }
    }

    /// `CE QUE J'AI DIT` : tout le reste.
    ///
    /// `authorSide != .manager` plutôt que `== .me` : une ligne importée d'un
    /// `liveNotes` ancien porte `.me`, une ligne saisie côté collaborateur peut
    /// porter `.collaborator`, et aucune des deux ne doit disparaître de
    /// l'écran (spec §1.1 : aucune ligne n'appartient à aucune section).
    static func saidSectionNotes(_ meeting: Meeting) -> [MeetingNote] {
        spokenNotes(meeting).filter { $0.authorSide != .manager }
    }

    /// Les lignes de la séance, triées et **nettoyées des lignes vides**.
    ///
    /// Une ligne vide est un marqueur d'axe temps posé par `⌘M` (lot 4, D4.1) :
    /// elle porte un repère, pas une phrase, et l'afficher dans une section
    /// donnerait une ligne muette (même règle que `OneOnOneNoteSections`).
    private static func spokenNotes(_ meeting: Meeting) -> [MeetingNote] {
        MeetingNoteStore.sorted(meeting.timedNotes)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Ce qu'il m'a promis

    /// Les promesses du manager encore à obtenir, **triées par retard
    /// décroissant** (spec §6.2).
    ///
    /// Une promesse `kept` quitte la carte : ce n'est plus quelque chose à
    /// obtenir. Une promesse `missed` y reste — c'est justement ce qu'il faut
    /// remettre sur la table.
    static func promises(_ thread: OneOnOneThread, now: Date) -> [Commitment] {
        let promesses = CommitmentLedger.all(thread, side: .manager)
            .filter { $0.state != .kept }
        return CommitmentLedger.byLatenessDescending(promesses, now: now)
    }

    /// Vrai quand la promesse est en retard : barre gauche `accent/report` et
    /// pilule d'échéance rouge (spec §6.2).
    static func isLate(_ commitment: Commitment, now: Date) -> Bool {
        commitment.state == .missed || CommitmentLedger.isOverdue(commitment, now: now)
    }

    /// `1 en retard` de l'en-tête. `nil` quand rien n'est en retard : le
    /// compteur est une alerte, pas un décompte permanent.
    static func lateBadge(_ thread: OneOnOneThread, now: Date) -> String? {
        let compte = promises(thread, now: now).filter { isLate($0, now: now) }.count
        guard compte > 0 else { return nil }
        return "\(compte) en retard"
    }

    /// `Promise le 24 juil.` — la date de la parole donnée, jamais l'échéance :
    /// c'est l'ancienneté de la promesse qui pèse dans un entretien, et
    /// `dueAt` peut avoir été repoussée trois fois depuis.
    static func promisedAtPill(_ commitment: Commitment) -> String {
        "Promise le \(OneOnOneDateFormat.dayMonthOrdinal(commitment.promisedAt))"
    }

    /// `2 reports`, `1 report`, ou `nil` quand rien n'a été reporté.
    ///
    /// Écrit autrement que `CommitmentLedger.deferralLabel` (`2× reporté`) : la
    /// capture 5a nomme le **nombre de reports** comme un fait, pas comme un
    /// état du verbe. Ce sont les deux libellés des deux captures, et chacune
    /// garde le sien.
    static func deferralPill(_ commitment: Commitment) -> String? {
        guard commitment.deferralCount > 0 else { return nil }
        return commitment.deferralCount == 1
            ? "1 report"
            : "\(commitment.deferralCount) reports"
    }

    /// L'échéance, quand elle existe : `Vendredi` dans la semaine de la
    /// séance, `24 juil.` au-delà. Reprend la règle du lot 11 plutôt que d'en
    /// écrire une seconde.
    static func duePill(_ commitment: Commitment, now: Date) -> String? {
        CommitmentsRailModel.duePill(commitment, now: now)
    }

    // MARK: - En sortant

    /// `Envoyer mon récap à Yann` (bouton primaire `accent/oneonone`).
    static func recapButtonLabel(for thread: OneOnOneThread) -> String {
        let prenom = OneOnOneThreadStore.firstName(of: thread)
        guard !prenom.isEmpty else { return "Envoyer mon récap" }
        return "Envoyer mon récap à \(prenom)"
    }

    /// `3 lignes privées seront exclues.` — notes, engagements et sujets
    /// confondus, pour l'audience du récap collaborateur (`.manager`).
    ///
    /// `nil` quand rien n'est exclu : « 0 ligne privée » attirerait l'œil pour
    /// dire qu'il n'y a rien à dire.
    static func excludedLinesLabel(for meeting: Meeting,
                                   in thread: OneOnOneThread) -> String? {
        let audience = OneOnOneConfidentiality.recapAudience(for: thread.myRole)
        let compte = OneOnOneRecapBuilder.excludedLinesCount(for: meeting, thread: thread,
                                                              audience: audience)
        return OneOnOneConfidentiality.excludedLinesLabel(compte)
    }

    // MARK: - Barre assistant

    /// `« Qu'ai-je livré depuis juillet ? »` — la suggestion de la capture.
    ///
    /// Le mois est celui du **dernier point tenu**, pas un mois figé : la
    /// question doit rester vraie six mois plus tard. Sans séance précédente,
    /// elle se pose sans mois plutôt que d'inventer une borne.
    static func assistantSuggestion(_ thread: OneOnOneThread,
                                    for meeting: Meeting) -> String {
        guard let precedente = OneOnOneThreadStore.previousMeeting(before: meeting,
                                                                   in: thread) else {
            return "« Qu'ai-je livré depuis le dernier point ? »"
        }
        return "« Qu'ai-je livré depuis \(monthName(precedente.date)) ? »"
    }

    /// `juillet` — le mois en clair, locale forcée `fr_FR` comme
    /// `OneOnOneDateFormat` (un poste réglé en anglais afficherait `July`).
    private static func monthName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }
}
