import SwiftUI

/// Les quatre tuiles de tête de l'onglet « Pilotage » (capture
/// `1d-ecran-projet-pilotage.png`) : actions ouvertes, dernière réunion,
/// rythme, charge.
///
/// La tuile **RYTHME** remplace la heatmap de 52 semaines de
/// `ProjectDetailView` (handoff, §Vue d'ensemble n° 4). Huit barres sur douze
/// semaines disent la même chose — « ce projet se réunit-il encore ? » — dans
/// un quart de la place, et sans faire croire qu'on lit une année.
///
/// Aucune tuile ne calcule : tout vient de `ProjectPilotageState` (D11).
struct KPITiles: View {

    // MARK: - Mesures du handoff §1d

    static let gap: CGFloat = 10
    static let tailleValeur: CGFloat = 22
    static let tailleSousLigne: CGFloat = 11.5
    /// Le « / 60 j » qui suit le nombre de jours consommés.
    static let tailleSuffixe: CGFloat = 12
    static let hauteurBarres: CGFloat = 26
    static let largeurBarre: CGFloat = 7
    static let ecartBarres: CGFloat = 3
    static let hauteurJauge: CGFloat = 4

    static let labelActions = "ACTIONS OUVERTES"
    static let labelDerniereReunion = "DERNIÈRE RÉUNION"
    static let labelRythme = "RYTHME"
    static let labelCharge = "CHARGE"
    /// Ce qu'affiche la tuile « DERNIÈRE RÉUNION » d'un projet qui n'en a
    /// aucune. Pas un vide : « jamais » est une information.
    static let jamais = "jamais"

    let etat: ProjectPilotageState

    var body: some View {
        HStack(alignment: .top, spacing: Self.gap) {
            tuileDesActions
            tuileDeLaDerniereReunion
            tuileDuRythme
            tuileDeLaCharge
        }
    }

    // MARK: - Actions ouvertes

    private var tuileDesActions: some View {
        tuile(Self.labelActions) {
            valeur("\(etat.openActions)")
            if etat.lateActions > 0 {
                sousLigne("\(etat.lateActions) en retard", teinte: One2OneToken.reportInk)
            } else {
                sousLigne("aucune en retard", teinte: One2OneToken.inkMuted)
            }
        }
    }

    // MARK: - Dernière réunion

    private var tuileDeLaDerniereReunion: some View {
        tuile(Self.labelDerniereReunion) {
            valeur(etat.lastMeeting?.label ?? Self.jamais)
            if let derniere = etat.lastMeeting {
                sousLigne(derniere.kindLine, teinte: One2OneToken.inkMuted)
            }
        }
    }

    // MARK: - Rythme

    private var tuileDuRythme: some View {
        tuile(Self.labelRythme) {
            HStack(alignment: .bottom, spacing: Self.ecartBarres) {
                ForEach(Array(etat.rhythm.enumerated()), id: \.offset) { _, compte in
                    Rectangle()
                        .fill(Self.teinteDeBarre(compte, maximum: maximumDuRythme))
                        .frame(width: Self.largeurBarre,
                               height: Self.hauteurDeBarre(compte, maximum: maximumDuRythme))
                }
            }
            .frame(height: Self.hauteurBarres, alignment: .bottom)
            .padding(.top, 7)
            sousLigne(etat.rhythmLabel, teinte: One2OneToken.inkMuted)
                .padding(.top, 4)
        }
    }

    private var maximumDuRythme: Int { max(etat.rhythm.max() ?? 0, 1) }

    /// La hauteur d'une barre, proportionnelle au nombre de réunions. Une
    /// semaine sans réunion garde **2 pt** : une barre absente se lirait comme
    /// un trou dans les données, pas comme un creux d'activité.
    static func hauteurDeBarre(_ compte: Int, maximum: Int) -> CGFloat {
        let minimale: CGFloat = 2
        guard compte > 0 else { return minimale }
        return minimale + (hauteurBarres - minimale) * CGFloat(compte) / CGFloat(max(maximum, 1))
    }

    /// La teinte d'une barre : le dégradé `okBg → ok` du handoff, parcouru par
    /// la hauteur. Deux jetons et une interpolation, aucune couleur nommée
    /// hors `One2OneToken`.
    static func teinteDeBarre(_ compte: Int, maximum: Int) -> Color {
        guard compte > 0 else { return One2OneToken.okBg }
        let part = Double(compte) / Double(max(maximum, 1))
        return One2OneToken.okBg.mix(with: One2OneToken.ok, by: part)
    }

    // MARK: - Charge

    private var tuileDeLaCharge: some View {
        tuile(Self.labelCharge) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                valeur(etat.charge.spentLabel ?? ProjectPilotageBuilder.tiret)
                if let prevu = etat.charge.plannedLabel {
                    Text(prevu)
                        .font(.plexSans(Self.tailleSuffixe))
                        .foregroundStyle(One2OneToken.inkMuted)
                }
            }
            if let ratio = etat.charge.ratio {
                jauge(ratio)
                    .padding(.top, 6)
            }
        }
    }

    private func jauge(_ ratio: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(One2OneToken.hair)
                Capsule().fill(One2OneToken.ok)
                    .frame(width: max(geo.size.width * ratio, 0))
            }
        }
        .frame(height: Self.hauteurJauge)
    }

    // MARK: - Châssis

    private func tuile<Contenu: View>(_ libelle: String,
                                      @ViewBuilder contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(libelle).sectionLabel()
            contenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
    }

    private func valeur(_ texte: String) -> some View {
        Text(texte)
            .font(.plexSans(Self.tailleValeur, .semibold))
            .foregroundStyle(One2OneToken.ink1)
            .lineLimit(1)
            .padding(.top, 5)
    }

    private func sousLigne(_ texte: String, teinte: Color) -> some View {
        Text(texte)
            .font(.plexSans(Self.tailleSousLigne))
            .foregroundStyle(teinte)
            .lineLimit(1)
    }
}
