import Foundation
import SwiftData

/// Source-of-truth for the 8 shipped templates. Lives in Swift (not DB)
/// so PRs can review prompt changes diff-side and "Restaurer défaut" has
/// a stable target.
enum BuiltInTemplates {

    struct Seed {
        let name: String
        let kind: ReportTemplateKind
        let preamble: String
        let sections: [TemplateSection]
        let historyMode: HistoryMode
        let historyN: Int
        let historyK: Int
        let promptBody: String
    }

    /// Keyed by `name` (also the SwiftData lookup key for `seedIfNeeded`).
    static let dict: [String: Seed] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    static let all: [Seed] = [
        d1_global,
        d2_oneToOne,
        d3_manager,
        d4_copil,
        d5_cosui,
        d6_codir,
        d7_preparation,
        d8_restitution,
        d9_workshop
    ]

    /// Idempotent seeding. Inserts only missing built-in templates by name.
    /// Never overwrites existing rows (preserves user edits — see spec §8.1).
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingNames = Set(existing.map { $0.name })
        for seed in all where !existingNames.contains(seed.name) {
            let t = ReportTemplate(
                name: seed.name,
                kind: seed.kind,
                promptBody: seed.promptBody,
                preamble: seed.preamble,
                sections: seed.sections,
                historyMode: seed.historyMode,
                historyN: seed.historyN,
                historyK: seed.historyK,
                isBuiltIn: true
            )
            context.insert(t)
        }

        // Backfill: ensure all existing built-in templates have a non-empty preamble.
        let existingBuiltIns = (try? context.fetch(FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true }
        ))) ?? []
        for tpl in existingBuiltIns {
            if tpl.preamble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tpl.preamble = "Tu es l'assistant de synthèse de OneToOne."
            }
        }

        // Backfill ciblé : d2_oneToOne révision 2026-05-23
        // Écrase preamble/promptBody/sections une fois. UserDefaults marker
        // évite la ré-application à chaque lancement. Pour pousser un nouveau
        // backfill plus tard : bumper `d2OneToOneRevisionTarget`.
        let d2Key = "BuiltInTemplates.d2OneToOneRevision"
        let d2Target = 3
        if UserDefaults.standard.integer(forKey: d2Key) < d2Target {
            if let row = existingBuiltIns.first(where: { $0.kindRaw == ReportTemplateKind.oneToOne.rawValue }) {
                row.preamble = d2_oneToOne.preamble
                row.promptBody = d2_oneToOne.promptBody
                row.sections = d2_oneToOne.sections
                row.historyMode = d2_oneToOne.historyMode
                row.historyN = d2_oneToOne.historyN
                row.updatedAt = Date()
            }
            UserDefaults.standard.set(d2Target, forKey: d2Key)
        }

        try? context.save()
    }

    // MARK: - D1 Global

    static let d1_global = Seed(
        name: "Global",
        kind: .general,
        preamble: "Tu es l'assistant de synthèse de OneToOne.",
        sections: [
            .init(title: "Contexte général", hint: "Ce qui se passe au moment de la réunion (top actions, alertes, sujets actifs)."),
            .init(title: "Résumé", hint: "Synthèse en 3-5 lignes."),
            .init(title: "Décisions", hint: "Décisions actées avec porteur si possible."),
            .init(title: "Actions", hint: "Liste numérotée avec assignee et échéance."),
            .init(title: "Faits marquants", hint: "Ce qui sort du quotidien.")
        ],
        historyMode: .none,
        historyN: 0,
        historyK: 0,
        promptBody: """
        Type: {{kind}} · Date: {{date}} · Participants: {{participants}}

        Contexte projet (à n'utiliser que comme arrière-plan, NE PAS recopier
        dans le rapport — ne mentionne une action/alerte que si elle est
        explicitement reprise dans la transcription) :
        {{contexte_general}}

        {{custom_prompt}}

        Transcription brute (sortie STT + notes live):
        {{transcript}}

        Notes manuelles:
        {{notes}}

        Règles de rédaction:
        - Tout le contenu doit provenir de la transcription + notes. N'invente
          rien.
        - Pour chaque action, identifie un porteur nommé parmi les participants
          réels ; si inconnu, écris "À préciser" (jamais "Équipe de pilotage").
        - Garde la section "Contexte général" courte et factuelle : objet de
          la réunion + participants effectifs. N'y mets PAS d'actions ou
          d'alertes provenant d'autres projets.
        """
    )

    // MARK: - D2 1:1 Collaborateur

    static let d2_oneToOne = Seed(
        name: "1:1 Collaborateur",
        kind: .oneToOne,
        preamble: """
        Tu es l'assistant de synthèse de réunions 1:1 manager/collaborateur.
        Ton factuel, opérationnel, en français.

        Règles strictes :
        - N'INVENTE JAMAIS. Si une info est ambiguë, ne pas l'inclure.
        - IGNORE en silence les passages personnels off-topic (équipement perso,
          vacances, météo, sport, lunettes, télé…). Ne mentionne pas qu'ils ont
          été ignorés.
        - Regroupe les échanges par bloc thématique métier explicite (un H3 par
          thème). Sois EXHAUSTIF sur les sujets pro — n'omets rien d'important.
        - Distingue clairement : décisions actées vs idées exploratoires vs
          sujets ouverts à trancher.
        - Action = verbe à l'infinitif + porteur explicite + échéance si mentionnée.
          Porteur possible : (1) le collaborateur, (2) le manager (toi, rédacteur),
          (3) un tiers nommé.
        - Capture les engagements pris dans CE 1:1 (manager ET collaborateur).
          N'inclus PAS les tâches perso du manager qui n'ont pas été discutées
          ici, même si elles sont en cours par ailleurs.
        - La transcription audio (STT) peut contenir des homophones et des
          coquilles. Corrige silencieusement les évidences (noms propres,
          acronymes connus) mais ne reformule pas le sens.
        """,
        sections: [
            .init(title: "Suivi du précédent",
                  hint: "Pour chaque action ouverte héritée, indique son statut : discutée, mise à jour (nouvelle échéance / précisions), ou non évoquée. Si pas d'historique : 'Pas de suivi disponible.'"),
            .init(title: "Sujets abordés",
                  hint: "Un H3 par thème métier (catalogue, projet X, RH/IAM, infra…). Pour chaque thème : contexte bref + points discutés. Exhaustif sur les sujets pro, ignore l'off-topic personnel."),
            .init(title: "Décisions",
                  hint: "Uniquement les décisions formellement actées en séance. Phrase courte au passé. Vide si rien d'acté."),
            .init(title: "Actions",
                  hint: "Engagements pris dans CE 1:1. Verbe à l'infinitif, porteur explicite (le collaborateur, le manager toi-même, ou un tiers nommé), échéance précise si mentionnée sinon '—'. N'inclus PAS les tâches perso du manager non discutées ici."),
            .init(title: "Ressenti / Climat",
                  hint: "Signaux faibles sur motivation, charge, blocages, points sensibles. Descriptif, sans jugement ni interprétation. Vide si rien à signaler.")
        ],
        historyMode: .lastN,
        historyN: 2,
        historyK: 0,
        promptBody: """
        1:1 avec {{collab.name}} ({{collab.role}}) — {{date}}

        Tu rédiges le compte-rendu de ce 1:1. Le manager est le rédacteur.

        Actions ouvertes héritées de {{collab.name}} :
        {{collab.actions_ouvertes}}

        Projets dont {{collab.name}} est architecte ou chef de projet :
        {{collab.projects_context}}

        Derniers 1:1 (pour suivi des actions précédentes) :
        {{historique_n}}

        {{custom_prompt}}

        Transcription audio (peut contenir des erreurs STT) :
        {{transcript}}

        Notes prises en live (sources fiables) :
        {{notes}}
        """
    )

    // MARK: - D3 1:1 Manager

    static let d3_manager = Seed(
        name: "1:1 Manager",
        kind: .manager,
        preamble: "Tu es l'assistant de synthèse de OneToOne.",
        sections: [
            .init(title: "Suivi semaine", hint: "Points repris du précédent 1:1 manager."),
            .init(title: "Sujets", hint: "Sujets abordés."),
            .init(title: "Demandes du manager", hint: "Ce que le manager demande / attend."),
            .init(title: "Actions", hint: "Mes engagements avec échéance."),
            .init(title: "Points d'attention", hint: "Risques, signaux faibles.")
        ],
        historyMode: .lastN,
        historyN: 1,
        historyK: 0,
        promptBody: """
        1:1 Manager · {{date}}

        Items en cours (suivi manager):
        {{manager.items_actuels}}

        Dernier CR manager:
        {{manager.dernier_cr}}

        Historique:
        {{historique_n}}

        {{custom_prompt}}

        Transcription:
        {{transcript}}

        Notes:
        {{notes}}
        """
    )

    // MARK: - D4 COPIL

    static let d4_copil = Seed(
        name: "COPIL",
        kind: .copil,
        preamble: "Tu es l'assistant de synthèse de OneToOne.",
        sections: [
            .init(title: "Contexte projet", hint: "Rappel rapide du contexte."),
            .init(title: "Avancement", hint: "Où on en est sur le planning."),
            .init(title: "Décisions", hint: "Décisions actées par le comité."),
            .init(title: "Risques", hint: "Risques identifiés + niveau."),
            .init(title: "Prochaines étapes", hint: "Avec porteur et échéance.")
        ],
        historyMode: .lastN,
        historyN: 1,
        historyK: 0,
        promptBody: """
        COPIL {{project.name}} ({{project.code}}) · {{date}} · Phase: {{project.phase}}

        Planning projet:
        {{project.planning}}

        Actions ouvertes:
        {{project.actions_ouvertes}}

        Dernier COPIL:
        {{historique_n}}

        {{custom_prompt}}

        Transcription:
        {{transcript}}

        Notes:
        {{notes}}
        """
    )

    // MARK: - D5 COSUI

    static let d5_cosui = Seed(
        name: "COSUI",
        kind: .cosui,
        preamble: "Tu es l'assistant de synthèse de OneToOne.",
        sections: [
            .init(title: "Avancement par sujet", hint: "Un bloc par sujet abordé."),
            .init(title: "Points bloquants", hint: ""),
            .init(title: "Actions", hint: "Avec porteur et échéance."),
            .init(title: "Indicateurs", hint: "KPIs / chiffres mentionnés.")
        ],
        historyMode: .lastN,
        historyN: 2,
        historyK: 0,
        promptBody: """
        COSUI {{project.name}} · {{date}}

        Actions ouvertes:
        {{project.actions_ouvertes}}

        Historique des 2 derniers COSUI:
        {{historique_n}}

        {{custom_prompt}}

        Transcription:
        {{transcript}}

        Notes:
        {{notes}}
        """
    )

    // MARK: - D6 CODIR

    static let d6_codir = Seed(
        name: "CODIR",
        kind: .codir,
        preamble: "Tu es l'assistant de synthèse de OneToOne.",
        sections: [
            .init(title: "Synthèse stratégique", hint: "Vision haut niveau."),
            .init(title: "Décisions", hint: ""),
            .init(title: "Arbitrages", hint: "Choix entre options."),
            .init(title: "Suite", hint: "Prochaines étapes au niveau direction.")
        ],
        historyMode: .lastN,
        historyN: 1,
        historyK: 0,
        promptBody: """
        CODIR · {{date}}

        Actions overdue (alertes top):
        {{actions_overdue}}

        Dernier CODIR:
        {{historique_n}}

        {{custom_prompt}}

        Transcription:
        {{transcript}}

        Notes:
        {{notes}}
        """
    )

    // MARK: - D7 Préparation

    static let d7_preparation = Seed(
        name: "Préparation",
        kind: .preparation,
        preamble: "Tu es l'assistant de synthèse de OneToOne.",
        sections: [
            .init(title: "Objectifs", hint: "Ce qu'on cherche à obtenir."),
            .init(title: "Points à aborder", hint: ""),
            .init(title: "Questions", hint: ""),
            .init(title: "Documents pertinents", hint: "Liens / refs.")
        ],
        historyMode: .lastN,
        historyN: 1,
        historyK: 0,
        promptBody: """
        Préparation: {{title}} · {{date}}

        Dernier rapport pertinent:
        {{historique_n}}

        {{custom_prompt}}

        Notes utilisateur:
        {{notes}}
        """
    )

    // MARK: - D8 Restitution / Démo

    static let d8_restitution = Seed(
        name: "Restitution / Démo",
        kind: .restitution,
        preamble: "Tu es l'assistant de synthèse de OneToOne.",
        sections: [
            .init(title: "Contexte", hint: "Ce qu'on présente et pourquoi."),
            .init(title: "Démo", hint: "Ce qui a été montré."),
            .init(title: "Feedbacks", hint: "Retours du public."),
            .init(title: "Suite", hint: "Prochaines actions identifiées.")
        ],
        historyMode: .none,
        historyN: 0,
        historyK: 0,
        promptBody: """
        Restitution {{project.name}} · {{date}} · Audience: {{participants}}

        {{custom_prompt}}

        Transcription:
        {{transcript}}

        Notes:
        {{notes}}
        """
    )

    // MARK: - D9 Séance de travail / Workshop
    //
    // Pour les sessions longues, denses, multi-sujets (architecture, gouvernance,
    // groupes de travail). Produit un CR structuré façon document de référence :
    // objet, contexte, discussion détaillée, définitions, décisions numérotées,
    // points ouverts, actions avec porteurs nommés, annexe cas illustratifs.

    static let d9_workshop = Seed(
        name: "Séance de travail / Workshop",
        kind: .workshop,
        preamble: "Tu es l'assistant de synthèse de OneToOne.",
        sections: [
            .init(title: "Objet & contexte",
                  hint: "1–3 lignes : sujet traité, raison de la séance, format."),
            .init(title: "Discussion",
                  hint: "Restitution riche des sujets abordés, idéalement en sous-points thématiques (ne pas résumer en 3 lignes — préserver la nuance et les points de désaccord)."),
            .init(title: "Définitions retenues",
                  hint: "Si la séance a fixé du vocabulaire (technologie vs solution, frontières…), liste les définitions actées. Sinon, omets cette section."),
            .init(title: "Décisions",
                  hint: "Numérotées D1, D2… avec libellé court et clair. Une seule décision par puce."),
            .init(title: "Points ouverts à trancher",
                  hint: "Numérotés O1, O2… Sujets identifiés mais non tranchés en séance, à instruire plus tard."),
            .init(title: "Actions",
                  hint: "Numérotées A1, A2… avec porteur **nommément identifié parmi les participants réels** et échéance (ou « À préciser »)."),
            .init(title: "Cas illustratifs",
                  hint: "Si la séance s'est appuyée sur des cas concrets (outil X, projet Y, exemples), récapitule-les en 1 ligne chacun avec l'enseignement tiré.")
        ],
        historyMode: .lastN,
        historyN: 2,
        historyK: 0,
        promptBody: """
        Séance de travail · {{date}} · Participants: {{participants}}
        Projet : {{project.name}}

        Contexte projet (arrière-plan uniquement — NE PAS recopier dans le
        rapport, n'utiliser que pour comprendre les références) :
        {{contexte_general}}

        Séances précédentes du projet :
        {{historique_n}}

        {{custom_prompt}}

        Transcription brute (sortie STT + notes live) :
        {{transcript}}

        Notes manuelles :
        {{notes}}

        Consignes de rédaction — IMPORTANT :
        - Tout le contenu sort de la transcription + notes. N'invente AUCUN
          chiffre, date, porteur, sujet qui ne soit pas explicitement présent.
        - Préserve la nuance technique : si deux participants ont nuancé un
          point, restitue les deux côtés (ex. : « X estime que… ; Y nuance que… »).
        - Pour les porteurs d'actions : utilise uniquement les noms des
          participants réels listés ci-dessus. Si le porteur n'est pas clair,
          écris exactement « À préciser ». N'écris JAMAIS « Équipe de pilotage »
          ou autres formules génériques.
        - Numérote décisions (D1…), points ouverts (O1…), actions (A1…).
        - Si une section est vide pour cette séance (ex. aucune définition
          retenue), omets-la entièrement plutôt que d'écrire « (aucune) ».
        - Le bloc "Contexte projet" ci-dessus est de l'arrière-plan : ne le
          recopie pas dans le rapport. Ne mentionne une action/alerte existante
          que si elle est explicitement reprise dans la séance.
        """
    )
}
