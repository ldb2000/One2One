import Foundation
import Observation
import SwiftData

/// L'assistant de réunion, hors de toute vue.
///
/// `MeetingChatView` portait tout : les messages en `@State`, le prompt, le
/// pré-fetch RAG et l'appel LLM. Le mode séance (spec §2.6) doit poser les
/// mêmes questions **avec les mêmes réponses** dans un panneau de 400 px qui
/// n'a ni bulles ni historique déroulant — deux implémentations de la même
/// question finiraient par ne plus répondre pareil.
///
/// Ce contrôleur est donc la logique d'envoi, et `MeetingChatView` lui délègue
/// désormais la construction du prompt (ses tests continuent de passer par ses
/// propres méthodes, qui ne font plus que transmettre).
///
/// Ce qu'il ajoute au passage : les **sources horodatées** que la capture 1b
/// affiche sous la réponse (`1 sept. 08:12 ↗`, `15:20 ↗`). Elles ne sont pas
/// extraites du texte du modèle — un modèle qui cite mal produirait des liens
/// morts — mais du contexte qu'on lui a **effectivement donné** : les chunks
/// RAG retenus et les notes de la séance.
@MainActor
@Observable
final class MeetingAssistantController {

    /// Une source citable sous une réponse.
    struct Source: Identifiable, Sendable, Equatable {
        let id = UUID()
        /// `15:20` pour la séance en cours, `1 sept. 08:12` pour une autre
        /// réunion.
        let libelle: String
        /// `stableID` de la réunion d'origine, `nil` pour la séance en cours.
        let meetingStableID: UUID?
        /// Instant dans cette réunion, `nil` quand aucun n'a pu être retrouvé.
        let t: Double?

        /// Vrai quand la source est dans la séance en cours : le clic replace
        /// alors la tête de lecture au lieu d'ouvrir une autre réunion.
        var estDansLaSeance: Bool { meetingStableID == nil }
    }

    /// Un échange affiché par le panneau de séance : la question et sa réponse.
    struct Echange: Identifiable, Sendable {
        let id = UUID()
        let question: String
        var reponse: String
        var sources: [Source]
    }

    // MARK: - État

    /// Les échanges, du plus ancien au plus récent. Le panneau n'en montre que
    /// le dernier (capture 1b) ; les précédents restent pour le contexte.
    private(set) var echanges: [Echange] = []
    private(set) var phase: LoadingPhase = .idle
    private(set) var erreur: String?

    var enCours: Bool { phase != .idle }

    /// Le dernier échange — celui que le panneau affiche.
    var dernier: Echange? { echanges.last }

    // MARK: - Prompt (pur)

    /// Le prompt monolithique, exactement celui de `MeetingChatView` avant ce
    /// lot : consigne, notes filtrées `.projectTeam`, contexte RAG, historique,
    /// question.
    ///
    /// `static` et pure : c'est ce qui la rend testable sans environnement
    /// SwiftUI, et c'est pour cela que `MeetingChatView.makePrompt` s'y
    /// ramène désormais au lieu d'en garder une copie.
    static func prompt(meetingTitle: String,
                       notesBlock: String,
                       question: String,
                       historicalContext: String,
                       history: String) -> String {
        """
        Tu es l'assistant d'analyse de l'application OneToOne, sollicité pendant la réunion « \(meetingTitle) ».
        Réponds à partir du contexte ci-dessous. Si l'information manque, dis-le clairement.
        Sois concret et concis.
        \(notesBlock.isEmpty ? "" : "\nNotes prises en séance (horodatées):\n\(notesBlock)\n")\(historicalContext.isEmpty ? "" : "\nContexte historique (réunions passées pertinentes):\n\(historicalContext)\n")\(history.isEmpty ? "" : "\nConversation antérieure:\n\(history)\n")
        Question actuelle:
        \(question)
        """
    }

    /// Sérialise la conversation antérieure en blocs `Utilisateur:` /
    /// `Assistant:`, coupée à `maxTurns` paires.
    static func history(_ tours: [(question: String, reponse: String)],
                        maxTurns: Int = 5) -> String {
        tours.suffix(maxTurns)
            .flatMap { ["Utilisateur: \($0.question)", "Assistant: \($0.reponse)"] }
            .joined(separator: "\n\n")
    }

    /// Le libellé d'une source : `15:20` dans la séance, `1 sept. 08:12`
    /// ailleurs, `1 sept.` quand aucun instant n'a pu être retrouvé.
    static func libelleSource(date: Date?, t: Double?) -> String {
        let instant = t.map { MeetingPlayhead.mmss($0) }
        switch (date, instant) {
        case (nil, let instant?):        return instant
        case (let date?, let instant?):  return "\(MeetingAssistantDock.dateCourte(date)) \(instant)"
        case (let date?, nil):           return MeetingAssistantDock.dateCourte(date)
        case (nil, nil):                 return "source"
        }
    }

    /// Retrouve l'instant d'un extrait dans une réunion, par recouvrement de
    /// texte avec ses segments de transcription.
    ///
    /// Les `TranscriptChunk` du RAG **ne portent pas de timecode** : ils sont
    /// découpés par longueur, pas par tour de parole. Plutôt que d'afficher
    /// une source sans instant, on cherche le segment dont le texte commence
    /// l'extrait. Comparaison sur les 40 premiers caractères normalisés : au
    /// mot près, un chunk et un segment ne coïncident jamais.
    static func instant(ofExtract extrait: String,
                        inSegments segments: [(t: Double, texte: String)]) -> Double? {
        let debut = String(extrait.prefix(40)).slashSearchNormalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard debut.count >= 12 else { return nil }
        for segment in segments {
            let normalise = segment.texte.slashSearchNormalized
            if normalise.hasPrefix(debut) || debut.hasPrefix(String(normalise.prefix(40))) {
                return segment.t
            }
        }
        return nil
    }

    // MARK: - Envoi

    /// Pose une question sur `meeting`. Ajoute l'échange, puis le complète.
    ///
    /// Rien n'est jeté en cas d'erreur : la question reste affichée avec son
    /// message d'échec, parce qu'on veut pouvoir la reposer sans la retaper.
    func demander(_ question: String,
                  meeting: Meeting,
                  settings: AppSettings,
                  context: ModelContext) {
        let propre = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty, !enCours else { return }

        let anterieurs = echanges.map { (question: $0.question, reponse: $0.reponse) }
        echanges.append(Echange(question: propre, reponse: "", sources: []))
        phase = .loadingContext
        erreur = nil

        let titre = meeting.title
        let notes = MeetingNoteStore.contextBlock(for: meeting, audience: .projectTeam)
        let utiliseOutils = settings.chatbotToolCallingEnabled

        Task { [weak self] in
            guard let self else { return }
            let resultats = await self.chercher(meeting: meeting, context: context)
            let contexte = Self.contextBlock(resultats)
            let sources = self.sources(from: resultats, meeting: meeting)
            let prompt = Self.prompt(meetingTitle: titre,
                                     notesBlock: notes,
                                     question: propre,
                                     historicalContext: contexte,
                                     history: Self.history(anterieurs))
            self.phase = .waitingLLM
            do {
                let reponse: String
                if utiliseOutils {
                    reponse = try await AIClient.sendWithToolLoop(prompt: prompt,
                                                                  settings: settings,
                                                                  tools: ToolCatalog.all,
                                                                  modelContext: context,
                                                                  maxTurns: 5)
                } else {
                    reponse = try await AIClient.send(prompt: prompt, settings: settings)
                }
                self.completer(reponse: reponse.trimmingCharacters(in: .whitespacesAndNewlines),
                               sources: sources)
            } catch {
                self.completer(reponse: "", sources: [])
                self.erreur = error.localizedDescription
            }
        }
    }

    private func completer(reponse: String, sources: [Source]) {
        if !echanges.isEmpty {
            echanges[echanges.count - 1].reponse = reponse
            echanges[echanges.count - 1].sources = sources
        }
        phase = .idle
    }

    /// Le pré-fetch RAG, repris de `MeetingChatView.fetchHistoricalContext` :
    /// scope selon le kind, réunion courante exclue pour ne pas se nourrir
    /// d'elle-même. Fail-soft : erreur ou base vide → aucun résultat.
    private func chercher(meeting: Meeting, context: ModelContext) async -> [RAGQuery.Result] {
        var scope = RAGQuery.Scope()
        scope.excludeMeetingPID = meeting.persistentModelID

        switch meeting.kind {
        case .project:
            scope.projectPID = meeting.project?.persistentModelID
            guard scope.projectPID != nil else { return [] }
        case .oneToOne, .manager:
            scope.collaboratorPID = meeting.participants.first?.persistentModelID
            guard scope.collaboratorPID != nil else { return [] }
        case .global, .work, .note, .workshop:
            return []
        }

        let requete = String(meeting.mergedTranscript.prefix(2000))
        guard !requete.isEmpty else { return [] }
        return (try? await RAGQuery.search(query: requete, topK: 5,
                                           scope: scope, context: context)) ?? []
    }

    /// Le bloc de contexte historique, au format que le prompt attend.
    static func contextBlock(_ resultats: [RAGQuery.Result]) -> String {
        guard !resultats.isEmpty else { return "" }
        return resultats.enumerated().map { index, resultat in
            let date = resultat.chunk.meeting?.date
                .formatted(date: .abbreviated, time: .omitted) ?? "?"
            let titre = resultat.chunk.meeting?.title ?? "réunion sans titre"
            return "[\(index + 1)] \(date) — \(titre): \(resultat.chunk.text)"
        }.joined(separator: "\n\n")
    }

    /// Les sources citables : les réunions d'où viennent les chunks retenus,
    /// puis la dernière décision de la séance en cours si elle en porte une.
    ///
    /// Dédoublonnées par libellé : deux chunks de la même minute d'une même
    /// réunion sont une source, pas deux.
    private func sources(from resultats: [RAGQuery.Result], meeting: Meeting) -> [Source] {
        var trouvees: [Source] = []
        var vus = Set<String>()

        for resultat in resultats {
            guard let origine = resultat.chunk.meeting else { continue }
            let segments = origine.transcriptSegments
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { (t: $0.startSeconds, texte: $0.text) }
            let t = Self.instant(ofExtract: resultat.chunk.text, inSegments: segments)
            let libelle = Self.libelleSource(date: origine.date, t: t)
            guard vus.insert(libelle).inserted else { continue }
            trouvees.append(Source(libelle: libelle,
                                   meetingStableID: origine.ensuredStableID,
                                   t: t))
        }

        // La séance en cours : la dernière note horodatée citée par le
        // contexte. C'est le `15:20 ↗` de la capture — une source « ici », qui
        // replace la tête de lecture au lieu d'ouvrir une réunion.
        if let derniere = MeetingNoteStore.sorted(meeting.timedNotes)
            .last(where: { $0.t > 0 && !$0.text.isEmpty }) {
            let libelle = Self.libelleSource(date: nil, t: derniere.t)
            if vus.insert(libelle).inserted {
                trouvees.append(Source(libelle: libelle, meetingStableID: nil, t: derniere.t))
            }
        }
        return trouvees
    }
}
