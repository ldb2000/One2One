import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Ce que la bande de captures décide (spec §5.3, capture 4a) : ordre,
/// légendes, titres, invites, colonne d'état.
@Suite("CaptureStripModel", .serialized)
@MainActor
struct CaptureStripModelTests {

    private let container: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    private func capture(index: Int = 1,
                         t: Double? = 252,
                         trigger: CaptureTrigger = .shareChange,
                         ocr: String = "") -> SlideCapture {
        let capture = SlideCapture(index: index, capturedAt: Date(), imagePath: "/tmp/slide-\(index).png")
        capture.t = t
        capture.trigger = trigger
        capture.ocrText = ocr
        container.mainContext.insert(capture)
        return capture
    }

    // MARK: - Ordre

    @Test("les captures sont triées par timecode, celles sans t reléguées en fin de bande")
    func sortedByTimecode() {
        let tardive = capture(index: 3, t: 728)
        let precoce = capture(index: 1, t: 252)
        let sansT = capture(index: 2, t: nil)
        let ordre = CaptureStripModel.sorted([tardive, precoce, sansT])
        // Une capture sans `t` n'a pas de place sur l'axe : elle ne peut pas
        // s'insérer entre deux captures horodatées sans mentir sur l'ordre des
        // événements, donc elle passe en fin de bande.
        #expect(ordre.map(\.index) == [1, 3, 2])
    }

    @Test("à timecode égal, l'index tranche")
    func sortedByIndexOnTie() {
        let a = capture(index: 5, t: 100)
        let b = capture(index: 2, t: 100)
        #expect(CaptureStripModel.sorted([a, b]).map(\.index) == [2, 5])
    }

    // MARK: - Légendes

    @Test("la légende reprend le timecode et le déclencheur de la capture 4a")
    func legends() {
        #expect(CaptureStripModel.legend(for: capture(t: 252, trigger: .shareChange), interval: nil)
                == "04:12 · auto")
        #expect(CaptureStripModel.legend(for: capture(t: 728, trigger: .manual), interval: nil)
                == "12:08 · ⌘⇧S")
    }

    @Test("le cas périodique affiche l'intervalle réel, pas le mot « périodique »")
    func periodicLegendUsesRealInterval() {
        let capture = capture(t: 535, trigger: .interval)
        #expect(CaptureStripModel.legend(for: capture, interval: .seconds(120)) == "08:55 · 2 min")
        #expect(CaptureStripModel.legend(for: capture, interval: .seconds(300)) == "08:55 · 5 min")
        // Sans réglage connu, on retombe sur le libellé neutre du modèle
        // plutôt que d'inventer une durée.
        #expect(CaptureStripModel.legend(for: capture, interval: nil) == "08:55 · 2 min")
    }

    @Test("une capture sans timecode affiche --:-- et non 00:00")
    func noTimecodeShowsDashes() {
        #expect(CaptureStripModel.legend(for: capture(t: nil, trigger: .manual), interval: nil)
                == "--:-- · ⌘⇧S")
    }

    // MARK: - Titre et texte extrait

    @Test("le titre reprend le timecode et la première ligne d'OCR")
    func titleUsesFirstOCRLine() {
        let capture = capture(t: 728, ocr: "tableau de chiffrage\nReprise AP : 3 j-h")
        #expect(CaptureStripModel.title(for: capture) == "Capture 12:08 — tableau de chiffrage")
    }

    @Test("sans OCR, le titre reste lisible")
    func titleWithoutOCR() {
        #expect(CaptureStripModel.title(for: capture(t: 252)) == "Capture 04:12")
        #expect(CaptureStripModel.title(for: capture(index: 4, t: nil)) == "Capture 4")
    }

    @Test("un titre trop long est tronqué, jamais laissé déborder")
    func titleIsTruncated() {
        let long = String(repeating: "chiffrage ", count: 20)
        let titre = CaptureStripModel.title(for: capture(t: 0.0, ocr: long), maxLength: 20)
        #expect(titre.hasSuffix("…"))
        #expect(titre.count < 45)
    }

    @Test("la première ligne d'OCR ignore les lignes vides")
    func firstOCRLineSkipsBlanks() {
        let avecTexte = capture(ocr: "\n   \nReprise AP : 3 j-h\nMarine : 21 000 €")
        #expect(CaptureStripModel.firstOCRLine(of: avecTexte) == "Reprise AP : 3 j-h")
        #expect(CaptureStripModel.firstOCRLine(of: capture(index: 2, ocr: "")) == nil)
    }

    @Test("la ligne « Texte extrait » de la carte de note reprend la capture 4a")
    func extractedTextLine() {
        let avecTexte = capture(ocr: "Reprise AP : 3 j-h · Marine : 21 000 €")
        #expect(CaptureStripModel.extractedTextLine(of: avecTexte)
                == "Texte extrait : « Reprise AP : 3 j-h · Marine : 21 000 € »")
        #expect(CaptureStripModel.extractedTextLine(of: capture(index: 2, ocr: "")) == nil)
    }

    // MARK: - Colonne d'état

    @Test("la colonne d'état de la capture 4a : texte cherchable, timecode, rapport")
    func statusLinesMatchScreenshot() {
        let capture = capture(t: 728, ocr: "tableau de chiffrage")
        let lignes = CaptureStripModel.statusLines(for: capture)
        #expect(lignes.map(\.label) == ["Texte extrait et cherchable",
                                        "Rattaché au timecode de la note",
                                        "Joindre au rapport"])
        #expect(lignes[0].mark == .done)
        #expect(lignes[1].mark == .done)
        // La case n'est pas cochée par défaut : joindre d'office toutes les
        // captures à un rapport diffusé serait un choix qu'on n'a pas fait.
        #expect(lignes[2].mark == .toggle)
    }

    @Test("la colonne d'état dit la vérité : ni texte inventé, ni timecode inventé")
    func statusLinesTellTheTruth() {
        let lignes = CaptureStripModel.statusLines(for: capture(t: nil, ocr: ""))
        #expect(lignes[0].mark == .missing)
        #expect(lignes[0].label == "Aucun texte extrait")
        #expect(lignes[1].mark == .missing)
        #expect(lignes[1].label.contains("hors séance"))
    }

    @Test("une capture jointe au rapport le montre")
    func statusLineFollowsIncludeInReport() {
        let capture = capture()
        capture.includeInReport = true
        #expect(CaptureStripModel.statusLines(for: capture)[2].mark == .done)
    }

    @Test("sans sélection, la colonne d'état est vide plutôt que menteuse")
    func statusLinesEmptyWithoutSelection() {
        #expect(CaptureStripModel.statusLines(for: nil).isEmpty)
    }

    // MARK: - Bande vide

    @Test("l'invite de bande vide dépend du type de réunion")
    func emptyInviteDependsOnKind() {
        let atelier = CaptureStripModel.emptyInvite(kind: .workshop,
                                                    detectsAutomatically: true,
                                                    hasSource: true)
        #expect(atelier.contains("2 minutes"))

        let archi = CaptureStripModel.emptyInvite(kind: .work,
                                                  detectsAutomatically: true,
                                                  hasSource: true)
        #expect(archi.contains("schéma"))

        let projet = CaptureStripModel.emptyInvite(kind: .project,
                                                   detectsAutomatically: true,
                                                   hasSource: true)
        #expect(projet.contains("partage"))
    }

    @Test("sans source choisie, l'invite dit quoi faire")
    func emptyInviteWithoutSource() {
        let invite = CaptureStripModel.emptyInvite(kind: .project,
                                                   detectsAutomatically: true,
                                                   hasSource: false)
        #expect(invite.contains("choisissez") || invite.contains("Choisissez") || invite.contains("fenêtre"))
    }

    @Test("détection coupée, l'invite annonce le geste manuel et pas une capture qui ne viendra pas")
    func emptyInviteWithoutDetection() {
        let invite = CaptureStripModel.emptyInvite(kind: .oneToOne,
                                                   detectsAutomatically: false,
                                                   hasSource: true)
        #expect(invite.contains("⌘⇧S"))
        #expect(!invite.contains("dès qu'un partage se stabilise"))
    }

    @Test("aucune invite n'est vide : un écran vide est interdit (spec §1.1)")
    func everyKindHasAnInvite() {
        for kind in MeetingKind.allCases {
            for auto in [true, false] {
                for source in [true, false] {
                    let invite = CaptureStripModel.emptyInvite(kind: kind,
                                                               detectsAutomatically: auto,
                                                               hasSource: source)
                    #expect(!invite.isEmpty)
                }
            }
        }
    }
}
