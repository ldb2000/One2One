import Foundation

// MARK: - Les commandes 1:1 du composeur

/// Le parseur du lot 2 sait produire une **nature de note**. En 1:1, trois des
/// six commandes produisent autre chose qu'une note : `/engagement` et
/// `/promesse` créent un `Commitment`, `/demande` crée en plus un
/// `OneOnOneAgendaItem`. Cette extension ajoute cette couche **sans toucher**
/// `NoteCommandParser.swift` : le fichier appartient au lot 2, et un `enum`
/// Swift ne gagne pas de cas depuis une extension de toute façon.
extension NoteCommandParser {

    /// Les commandes propres au 1:1 qui n'existent pas dans le parseur de base.
    enum OneOnOneCommand: String, CaseIterable, Sendable {
        case engagement

        var pill: String { "/engagement" }

        /// Écritures acceptées, sous forme repliée (sans accent, minuscules).
        var aliases: [String] { ["engagement"] }
    }

    /// Dans quelle section du centre la ligne est saisie : `③ FEEDBACK — CE QUE
    /// JE LUI DIS` / `CE QU'IL ME DIT` (capture 2a), `CE QU'IL M'A DIT` / `CE
    /// QUE J'AI DIT` (capture 5a).
    ///
    /// C'est la section, et non la commande, qui dit **qui parle** : la même
    /// commande `/feedback` sert dans les deux cartes.
    enum FeedbackSection: Sendable {
        /// Ce que **je** dis.
        case given
        /// Ce que **l'autre** me dit.
        case received
    }

    /// Une ligne de note à créer.
    struct NoteDraft: Equatable, Sendable {
        var kind: MeetingNoteKind
        var text: String
        /// Toujours renseignée en 1:1 : la visibilité par défaut dépend du rôle
        /// (spec §6.1), que `MeetingNoteStore.defaultVisibility(for kind:)` ne
        /// connaît pas quand la réunion a été mal typée.
        var visibility: Visibility
        var authorSide: MeetingSide
    }

    /// Un engagement à créer.
    struct CommitmentDraft: Equatable, Sendable {
        var text: String
        /// Le porteur **par défaut**. Le fil laisse choisir `Moi` / `<Prénom>`
        /// avant de valider (capture 2a) ; `/promesse` seul est figé.
        var ownerSide: OneOnOneSide
        var visibility: Visibility
    }

    /// Un sujet d'ordre du jour à créer.
    struct AgendaDraft: Equatable, Sendable {
        var text: String
        var addedBySide: OneOnOneSide
        var kind: AgendaItemKind
        var visibility: Visibility
    }

    /// Ce qu'une ligne de composeur produit en 1:1 : jusqu'à trois effets,
    /// chacun optionnel. `/demande` en produit deux — une trace horodatée dans
    /// les notes **et** une demande suivie dans la colonne de gauche —, et les
    /// séparer en deux appels obligerait chaque vue à s'en souvenir.
    struct OneOnOneParsed: Equatable, Sendable {
        var basePill: Command?
        var oneOnOnePill: OneOnOneCommand?
        var note: NoteDraft?
        var commitment: CommitmentDraft?
        var agenda: AgendaDraft?
        /// Vrai pour `/privé` : la vue bascule aussi la ligne courante.
        var togglesPrivacy = false
        /// Vrai pour `/action` : le composeur du rail prend la suite.
        var opensActionComposer = false
    }

    /// Analyse une ligne de composeur dans le contexte d'un fil 1:1.
    ///
    /// - Parameters:
    ///   - role: mon rôle dans le fil — il décide de la visibilité par défaut
    ///     et du porteur par défaut d'un engagement.
    ///   - section: la carte où la ligne est saisie, qui décide de `authorSide`.
    static func parseOneOnOne(_ raw: String,
                              role: OneOnOneSide,
                              section: FeedbackSection = .given) -> OneOnOneParsed {
        let defaut = OneOnOneConfidentiality.defaultVisibility(for: role)
        let auteur = authorSide(role: role, section: section)

        // `/engagement` d'abord : le parseur de base ne le connaît pas et
        // rendrait « du texte », ce qui créerait une note au lieu d'un
        // engagement.
        if let (commande, texte) = matchOneOnOneCommand(raw) {
            guard !texte.isEmpty else {
                return OneOnOneParsed(oneOnOnePill: commande)
            }
            return OneOnOneParsed(
                oneOnOnePill: commande,
                commitment: CommitmentDraft(text: texte, ownerSide: role, visibility: defaut)
            )
        }

        let base = parse(raw)

        // `/action` : rien n'est écrit ici, le rail prend la main.
        if base.opensActionComposer {
            return OneOnOneParsed(basePill: base.command, opensActionComposer: true)
        }

        let texte = base.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else {
            return OneOnOneParsed(basePill: base.command,
                                  togglesPrivacy: base.command == .secret)
        }

        let visibilite = base.visibility ?? defaut
        var resultat = OneOnOneParsed(
            basePill: base.command,
            note: NoteDraft(kind: base.kind, text: texte,
                            visibility: visibilite, authorSide: auteur),
            togglesPrivacy: base.command == .secret
        )

        switch base.command {
        case .promise:
            // Spec §6.2 : « les engagements verbaux du manager sont saisis par
            // `/promesse` et créent un `Commitment` côté `manager` ». Toujours
            // côté manager : c'est *lui* qui a promis, quel que soit celui qui
            // tape la ligne.
            resultat.commitment = CommitmentDraft(text: texte, ownerSide: .manager,
                                                  visibility: visibilite)
        case .request:
            // Une demande est un sujet suivi (`MES DEMANDES EN COURS`, capture
            // 5a) autant qu'une ligne de note.
            resultat.agenda = AgendaDraft(text: texte, addedBySide: role,
                                          kind: .request, visibility: visibilite)
        case .action, .decision, .risk, .quote, .secret, .feedback, .proof, .none:
            break
        }
        return resultat
    }

    /// Qui parle, selon la carte où la ligne est saisie.
    private static func authorSide(role: OneOnOneSide, section: FeedbackSection) -> MeetingSide {
        switch section {
        case .given:
            return .me
        case .received:
            switch role {
            case .manager:      return .collaborator
            case .collaborator: return .manager
            }
        }
    }

    /// Reconnaît une commande 1:1 en tête de ligne et rend le texte restant.
    private static func matchOneOnOneCommand(_ raw: String) -> (OneOnOneCommand, String)? {
        let ligne = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ligne.hasPrefix("/") else { return nil }

        let sansBarre = ligne.dropFirst()
        let separateur = sansBarre.firstIndex(where: { $0.isWhitespace })
        let mot = String(separateur.map { sansBarre[..<$0] } ?? sansBarre)
        let reste = separateur.map { String(sansBarre[$0...]) } ?? ""
        let replie = foldForOneOnOne(mot)

        guard let commande = OneOnOneCommand.allCases.first(where: { $0.aliases.contains(replie) })
        else { return nil }
        return (commande, reste.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Forme comparable d'un mot : sans accent, en minuscules.
    ///
    /// Recopié plutôt qu'emprunté : le `fold` du parseur de base est `private`,
    /// et le rendre `internal` modifierait un fichier du lot 2, qui est réécrit
    /// en parallèle.
    static func foldForOneOnOne(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "fr_FR"))
    }
}
