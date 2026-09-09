import Testing
import Foundation
@testable import OneToOne

/// Les quatre listes de valeurs d'un projet (décision **D14**) : phase, statut,
/// type et niveau de risque.
///
/// Elles restent des **chaînes libres** dans `Project` (constat §2.7 : le semis
/// historique écrit `phase: "Réalisation"`, l'import xlsx écrit ce que le
/// portfolio externe contient). Ces enums ne sont donc pas persistées : elles
/// nomment les valeurs connues, en donnent le libellé, et rendent `nil` pour
/// tout le reste — ce que la vue affichera en badge neutre.
@Suite("Listes de valeurs d'un projet — D14")
struct ProjectPhaseTests {

    // MARK: - Phase

    @Test("Les quatre phases sont celles des listes en dur qu'elles remplacent")
    func phasesConnues() {
        #expect(ProjectPhase.allLabels == ["Cadrage", "Design", "Build", "Run"])
        #expect(ProjectPhase.allCases.map(\.label) == ProjectPhase.allLabels)
    }

    @Test("Une phase se lit quelle que soit sa casse")
    func phaseInsensibleCasse() {
        #expect(ProjectPhase(raw: "cadrage") == .cadrage)
        #expect(ProjectPhase(raw: "Cadrage") == .cadrage)
        #expect(ProjectPhase(raw: "DESIGN") == .design)
        #expect(ProjectPhase(raw: "  run  ") == .run)
    }

    /// La valeur que le semis historique écrit : elle **doit** rendre `nil`,
    /// c'est le cas qui prouve que l'enum ne remplace pas la chaîne persistée.
    @Test("« Réalisation » n'est pas une phase connue — badge neutre, jamais un crash")
    func phaseInconnue() {
        #expect(ProjectPhase(raw: "Réalisation") == nil)
        #expect(ProjectPhase(raw: "") == nil)
        #expect(ProjectPhase(raw: "Build & Run") == nil)
    }

    // MARK: - Statut

    @Test("Les quatre statuts gardent leurs valeurs persistées anglaises")
    func statutsConnus() {
        #expect(ProjectStatus.allLabels == ["Green", "Yellow", "Red", "Unknown"])
        #expect(ProjectStatus(raw: "green") == .green)
        #expect(ProjectStatus(raw: "Unknown") == .unknown)
        #expect(ProjectStatus(raw: "Vert") == nil)
    }

    // MARK: - Type

    @Test("Les trois types de projet se lisent sans leurs accents")
    func typesConnus() {
        #expect(ProjectType.allLabels == ["Métier", "Transverse", "Technique"])
        #expect(ProjectType(raw: "Métier") == .metier)
        #expect(ProjectType(raw: "metier") == .metier)
        #expect(ProjectType(raw: "MÉTIER") == .metier)
        #expect(ProjectType(raw: "Infra") == nil)
    }

    // MARK: - Risque

    @Test("Les quatre niveaux de risque se lisent sans leurs accents")
    func risquesConnus() {
        #expect(RiskLevel.allLabels == ["Faible", "Modéré", "Élevé", "Critique"])
        #expect(RiskLevel(raw: "Modéré") == .modere)
        #expect(RiskLevel(raw: "modere") == .modere)
        #expect(RiskLevel(raw: "Élevé") == .eleve)
        #expect(RiskLevel(raw: "eleve") == .eleve)
        #expect(RiskLevel(raw: "ELEVE") == .eleve)
        #expect(RiskLevel(raw: "Critique") == .critique)
    }

    /// La colonne `RISQUE` de la capture 1a affiche un tiret quand le champ est
    /// vide : c'est l'absence de valeur, pas un niveau « Faible » supposé.
    @Test("Un risque absent n'est pas « Faible »")
    func risqueAbsent() {
        #expect(RiskLevel(raw: "") == nil)
        #expect(RiskLevel(raw: "—") == nil)
        #expect(RiskLevel(raw: "Inconnu") == nil)
    }

    /// L'ordre des cas est l'ordre de gravité : le filtre « Risque ≥ Modéré »
    /// de la capture 1a s'appuie dessus (lot 2).
    @Test("L'ordre des niveaux de risque est celui de la gravité croissante")
    func ordreDeGravite() {
        #expect(RiskLevel.faible.severity < RiskLevel.modere.severity)
        #expect(RiskLevel.modere.severity < RiskLevel.eleve.severity)
        #expect(RiskLevel.eleve.severity < RiskLevel.critique.severity)
    }

    /// Le libellé rend exactement la valeur à écrire dans la colonne persistée :
    /// un aller-retour `label` → `init?(raw:)` doit être l'identité.
    @Test("Le libellé de chaque cas se relit en ce même cas")
    func allerRetour() {
        for cas in ProjectPhase.allCases { #expect(ProjectPhase(raw: cas.label) == cas) }
        for cas in ProjectStatus.allCases { #expect(ProjectStatus(raw: cas.label) == cas) }
        for cas in ProjectType.allCases { #expect(ProjectType(raw: cas.label) == cas) }
        for cas in RiskLevel.allCases { #expect(RiskLevel(raw: cas.label) == cas) }
    }
}
