import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les cartes du poste de pilotage : la détection du porteur d'une décision, et
/// le critère d'acceptation n° 1 du chantier 1 — « aucun espace ne peut
/// afficher une zone vide sans invite d'action ».
///
/// Ce dernier ne se vérifie pas par l'état d'un modèle : une carte qui teste
/// `isEmpty` et rend un `Spacer` passerait toutes les autres suites. La garde
/// **lit les sources** du dossier `Review/`, comme `ActionsRailNoModalTests`
/// lit celles du rail — et un premier test vérifie que le dossier lu est bien
/// celui du mode Relire, sans quoi les autres ne prouveraient rien en passant.
@Suite("Cartes du poste de pilotage")
@MainActor
struct ReviewCardsInviteTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    // MARK: - Porteur d'une décision

    @Test("Un nom en fin de phrase après un tiret cadratin est un porteur")
    func ownerAfterDash() {
        let (texte, porteur) = DecisionsCard.separerPorteur(
            "Le partenaire finalise la migration — Olivier Freund")
        #expect(texte == "Le partenaire finalise la migration")
        #expect(porteur == "Olivier Freund")
    }

    @Test("Un nom entre parenthèses en fin de phrase est un porteur")
    func ownerInParentheses() {
        let (texte, porteur) = DecisionsCard.separerPorteur(
            "Le partenaire finalise lui-même la migration (Olivier Freund).")
        #expect(texte == "Le partenaire finalise lui-même la migration.")
        #expect(porteur == "Olivier Freund")
    }

    @Test("Un tiret suivi d'une suite de phrase n'est pas un porteur")
    func dashInSentence() {
        let (texte, porteur) = DecisionsCard.separerPorteur(
            "40k déjà payés, rien de finalisé — reste à chiffrer la fin Marine")
        #expect(porteur == nil)
        #expect(texte == "40k déjà payés, rien de finalisé — reste à chiffrer la fin Marine")
    }

    @Test("Un segment final en minuscules n'est pas un porteur")
    func lowercaseTail() {
        #expect(DecisionsCard.separerPorteur("Budget gelé — à confirmer").porteur == nil)
    }

    @Test("Un segment final ponctué est une réserve, pas un porteur")
    func punctuatedTail() {
        let (_, porteur) = DecisionsCard.separerPorteur(
            "Le partenaire reprend la migration — Olivier Freund, sous réserve")
        #expect(porteur == nil)
    }

    @Test("Un segment final trop long n'est pas un porteur")
    func tooManyWords() {
        let (_, porteur) = DecisionsCard.separerPorteur(
            "Décision actée — Olivier Freund Nathalie Lefèvre Cédric Payet Lucas Sylvain")
        #expect(porteur == nil)
    }

    @Test("Une phrase sans tiret ni parenthèse est rendue telle quelle")
    func plainSentence() {
        let (texte, porteur) = DecisionsCard.separerPorteur("Pas de rallonge budgétaire sur cette phase")
        #expect(texte == "Pas de rallonge budgétaire sur cette phase")
        #expect(porteur == nil)
    }

    // MARK: - Lignes de la carte

    @Test("Les décisions sont les notes horodatées, triées par timecode")
    func decisionLinesFromNotes() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "[P25_110] Partage statut final")
        context.insert(reunion)
        // Semées dans le désordre : l'ordre d'une relation SwiftData n'est pas
        // garanti, donc le tri doit se faire ici.
        let brutes: [(Double, String, MeetingNoteKind)] = [
            (1_215, "Webcast développeurs lancé cette semaine", .decision),
            (252, "Gros morceau = AP.", .note),
            (663, "Le partenaire finalise la migration — Olivier Freund", .decision),
            (820, "Pas de rallonge budgétaire sur cette phase", .decision)
        ]
        for (index, ligne) in brutes.enumerated() {
            let note = MeetingNote(t: ligne.0, text: ligne.1, kind: ligne.2, orderIndex: index)
            context.insert(note)
            note.meeting = reunion
        }

        let lignes = DecisionsCard.lignes(for: reunion)
        #expect(lignes.count == 3)
        #expect(lignes.map { $0.t } == [663, 820, 1_215])
        #expect(lignes[0].porteur == "Olivier Freund")
        #expect(lignes[0].texte == "Le partenaire finalise la migration")
        #expect(lignes[1].porteur == nil)
    }

    @Test("Sans note horodatée, les décisions du rapport servent de repli sans timecode")
    func decisionLinesFallback() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Réunion importée")
        reunion.decisions = ["Le partenaire finalise la migration (Olivier Freund)",
                             "Pas de rallonge budgétaire"]
        context.insert(reunion)

        let lignes = DecisionsCard.lignes(for: reunion)
        #expect(lignes.count == 2)
        #expect(lignes.allSatisfy { $0.t == nil })
        #expect(lignes[0].porteur == "Olivier Freund")
    }

    @Test("Une réunion sans décision ne rend aucune ligne")
    func noDecisions() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Réunion")
        context.insert(reunion)
        #expect(DecisionsCard.lignes(for: reunion).isEmpty)
    }

    // MARK: - Le résumé garde son gras

    @Test("Le gras du résumé survit au rendu")
    func summaryKeepsBold() {
        let riche = OneSentenceCard.texteRiche(
            "Point de situation sur les migrations **AP** et **Marine**.")
        // Le balisage a disparu, le texte est intact.
        #expect(!String(riche.characters).contains("**"))
        #expect(String(riche.characters).contains("AP"))
        // Un markdown mal formé retombe sur le texte brut plutôt que sur rien.
        #expect(!String(OneSentenceCard.texteRiche("**non fermé").characters).isEmpty)
    }

    // MARK: - Aucune zone vide sans invite

    /// Le dossier des surfaces du mode Relire, dérivé de `#filePath` — comme
    /// `ActionsRailNoModalTests` pour le rail.
    private var dossierReview: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/
            .deletingLastPathComponent()          // racine
            .appendingPathComponent("OneToOne/Views/Meeting/Spaces/Review")
    }

    private func sources() throws -> [(nom: String, contenu: String)] {
        let fichiers = try FileManager.default
            .contentsOfDirectory(at: dossierReview, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try fichiers.map { (nom: $0.lastPathComponent,
                                   contenu: try String(contentsOf: $0, encoding: .utf8)) }
    }

    @Test("Le dossier lu est bien celui du mode Relire")
    func readsTheRightFolder() throws {
        let noms = try sources().map(\.nom)
        // Sans cette vérification, tous les tests de source ci-dessous
        // passeraient sur un dossier vide.
        #expect(noms.contains("ReviewSidebarNav.swift"))
        #expect(noms.contains("ReviewHeader.swift"))
        #expect(noms.contains("OneSentenceCard.swift"))
        #expect(noms.contains("DecisionsCard.swift"))
        #expect(noms.count >= 4)
    }

    /// Les fichiers du dossier qui ne rendent **aucune zone** susceptible
    /// d'être vide, avec la raison. Toute autre surface doit porter une invite.
    ///
    /// La liste est fermée, et c'est là son intérêt : un fichier de carte
    /// ajouté demain sans invite ne peut passer qu'en s'y déclarant
    /// explicitement — donc en assumant la décision, pas en l'oubliant.
    private static let sansZone: [String: String] = [
        "ReviewState.swift": "état d'écran, ne rend rien",
        "ReviewHeader.swift": "en-tête : chaque champ a un repli (« Réunion », « Transcrire + Rapport »)",
        "ReviewAudioTimeline.swift": "l'invite « Aucun audio » vit dans AudioTimelineStrip"
    ]

    @Test("Toute surface du mode Relire porte une invite d'état vide")
    func everySurfaceHasAnInvite() throws {
        for fichier in try sources() {
            if let raison = Self.sansZone[fichier.nom] {
                #expect(!raison.isEmpty)
                continue
            }
            // Trois primitives d'invite, et pas une de plus : le bloc centré
            // (`MeetingEmptyInvite`), la pilule (`InvitePill`) et le `＋` de la
            // nav latérale, dont les 190 px ne tiennent aucun des deux autres.
            let propose = fichier.contenu.contains("MeetingEmptyInvite")
                || fichier.contenu.contains("InvitePill")
                || fichier.contenu.contains("case invite")
            #expect(propose,
                    "\(fichier.nom) rend une zone sans invite — ajoutez-la, ou déclarez le fichier dans `sansZone` avec sa raison")
        }
    }

    @Test("Aucune couleur nommée hors des jetons dans le mode Relire")
    func onlyTokenColors() throws {
        let interdits = ["Color.red", "Color.blue", "Color.green", "Color.orange",
                         "Color.gray", "Color.black", "Color.white", "Color(hex:",
                         ".foregroundColor(.red)", ".foregroundColor(.blue)"]
        for fichier in try sources() {
            for interdit in interdits {
                #expect(!fichier.contenu.contains(interdit),
                        "\(fichier.nom) nomme une couleur hors One2OneToken : \(interdit)")
            }
        }
    }

    @Test("Aucune modale dans le mode Relire : tout s'édite sur place")
    func noModals() throws {
        // Critère d'acceptation n° 3 du chantier 1, transposé au tableau dense :
        // l'édition inline par cellule ne doit pas ouvrir de feuille. La frise
        // audio en est la seule exception assumée — `✂ Éditer` ouvre la modale
        // d'édition audio **existante**, ce que la spec §2.7 demande
        // explicitement, et elle passe par `MeetingMenuActions`, donc sans
        // `.sheet(` dans ce dossier.
        let interdits = [".sheet(", ".popover(", ".confirmationDialog(", ".fullScreenCover("]
        for fichier in try sources() {
            for interdit in interdits {
                #expect(!fichier.contenu.contains(interdit),
                        "\(fichier.nom) ouvre une modale : \(interdit)")
            }
        }
    }
}
