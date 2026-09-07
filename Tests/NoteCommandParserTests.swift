import Testing
@testable import OneToOne

/// Les commandes `/` du composeur de notes (spec §1.4 et §2.4 : « composeur en
/// bas avec les commandes `/` visibles en permanence, pas de découverte
/// cachée »).
///
/// Le parseur est pur pour une raison précise : c'est lui qui décide de la
/// **nature** d'une ligne, donc de sa barre de couleur, de son comptage dans le
/// bandeau d'indicateurs et — pour `/privé` — de sa sortie vers un rapport.
/// Cette décision ne doit pas dépendre d'un état de vue.
@Suite("Commandes / du composeur de notes")
struct NoteCommandParserTests {

    @Test("/décision donne la nature decision et retire la commande")
    func decision() {
        let p = NoteCommandParser.parse("/décision le partenaire finalise la migration")
        #expect(p.command == .decision)
        #expect(p.kind == .decision)
        #expect(p.text == "le partenaire finalise la migration")
        #expect(p.opensActionComposer == false)
    }

    @Test("Sans accent et en majuscules, la commande est reconnue")
    func sansAccent() {
        #expect(NoteCommandParser.parse("/decision X").kind == .decision)
        #expect(NoteCommandParser.parse("/DÉCISION X").kind == .decision)
        #expect(NoteCommandParser.parse("/Risque X").kind == .risk)
    }

    @Test("/action pose l'intention d'ouvrir le composeur d'action, pas une note")
    func action() {
        let p = NoteCommandParser.parse("/action Vérifier l'état des comptes GitLab")
        #expect(p.command == .action)
        #expect(p.opensActionComposer)
        #expect(p.kind == .note)
        #expect(p.text == "Vérifier l'état des comptes GitLab")
    }

    @Test("Un texte sans commande passe intact")
    func texteSimple() {
        let p = NoteCommandParser.parse("40k déjà payés, rien de finalisé")
        #expect(p.command == nil)
        #expect(p.kind == .note)
        #expect(p.text == "40k déjà payés, rien de finalisé")
        #expect(p.visibility == nil)
    }

    @Test("/privé ne change pas la nature mais impose la visibilité")
    func prive() {
        let p = NoteCommandParser.parse("/privé à ne pas mettre dans le CR")
        #expect(p.command == .secret)
        #expect(p.kind == .note)
        #expect(p.visibility == .private)
        #expect(p.text == "à ne pas mettre dans le CR")
    }

    @Test("Une commande seule garde la nature et rend un texte vide")
    func commandeSeule() {
        let p = NoteCommandParser.parse("/décision")
        #expect(p.kind == .decision)
        #expect(p.text.isEmpty)
    }

    @Test("Les espaces de tête sont tolérés")
    func espaces() {
        #expect(NoteCommandParser.parse("   /risque compte désactivé").kind == .risk)
    }

    @Test("Une barre au milieu du texte n'est pas une commande")
    func barreAuMilieu() {
        let p = NoteCommandParser.parse("prod/preprod à aligner")
        #expect(p.command == nil)
        #expect(p.text == "prod/preprod à aligner")
    }

    @Test("Une commande inconnue n'est pas mangée")
    func commandeInconnue() {
        // Rendre `nil` **et** conserver le texte : sinon une faute de frappe
        // (« /décison ») effacerait silencieusement la ligne saisie.
        let p = NoteCommandParser.parse("/inconnu texte")
        #expect(p.command == nil)
        #expect(p.text == "/inconnu texte")
    }

    @Test("/citer conserve le texte cité en nature note")
    func citer() {
        let p = NoteCommandParser.parse("/citer « il faut vérifier les droits » — Laurent, 04:12")
        #expect(p.command == .quote)
        #expect(p.kind == .note)
        #expect(p.text == "« il faut vérifier les droits » — Laurent, 04:12")
    }

    @Test("Les natures 1:1 sont reconnues, elles existent déjà dans MeetingNoteKind")
    func natures1a1() {
        #expect(NoteCommandParser.parse("/feedback bon réflexe").kind == .feedback)
        #expect(NoteCommandParser.parse("/promesse je relance").kind == .promise)
        #expect(NoteCommandParser.parse("/demande une revue").kind == .request)
        #expect(NoteCommandParser.parse("/preuve le lien du livrable").kind == .proof)
    }

    @Test("Les quatre pilules visibles sont celles de la capture")
    func pilules() {
        #expect(NoteCommandParser.visiblePills.map(\.pill)
                == ["/action", "/décision", "/risque", "/citer"])
    }

    @Test("Un composeur vide ne produit rien à insérer")
    func vide() {
        let p = NoteCommandParser.parse("    ")
        #expect(p.command == nil)
        #expect(p.text.isEmpty)
    }
}
