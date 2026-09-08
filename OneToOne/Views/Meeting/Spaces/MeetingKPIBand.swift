import SwiftUI

/// Le bandeau de quatre indicateurs de l'espace Réunion (spec §2.3, capture
/// `1a-cockpit.png`).
///
/// Grille de quatre colonnes égales, `gap 10`, carte 10 × 12 px. Chaque carte :
/// libellé mono, valeur 20 px/600, complément, puis une micro-visualisation.
///
/// **Un compteur à zéro n'efface pas la carte** : il remplace la
/// micro-visualisation par l'invite de `MeetingEmptyInvite.Catalogue`
/// (« Aucune décision — /décision dans les notes »). C'est le critère
/// d'acceptation n° 1 appliqué au bandeau : le vide dit quoi faire.
///
/// Ne calcule rien : `MeetingKPIBuilder` a déjà tout fait, et c'est lui qui
/// est testé.
struct MeetingKPIBand: View {

    /// Écart entre les cartes (spec §2.3).
    static let gap: CGFloat = 10
    /// Padding interne d'une carte : 10 horizontal, 12 vertical (spec §2.3).
    static let cardPaddingH: CGFloat = 10
    static let cardPaddingV: CGFloat = 12
    /// Diamètre d'un point de risque.
    static let riskDot: CGFloat = 7

    let kpi: MeetingKPI
    /// Clic sur la carte Présence → gestion des participants (spec §2.3).
    let onManageParticipants: () -> Void
    /// Clic sur la carte Décisions → filtre les notes sur `kind:'decision'`.
    let onFilterDecisions: () -> Void
    /// Clic sur la carte Risques → onglet Risques du rail (lot 3).
    let onOpenRisks: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Self.gap) {
            presenceCard
            actionsCard
            decisionsCard
            risksCard
        }
    }

    // MARK: - Présence

    private var presenceCard: some View {
        card(action: onManageParticipants) {
            entete("PRÉSENCE",
                   valeur: "\(kpi.presence.percent) %",
                   complement: kpi.presence.total > 0
                       ? "\(kpi.presence.present)/\(kpi.presence.total)"
                       : nil)
            if kpi.presence.total == 0 {
                invite(.presence)
            } else {
                // Les noms viennent du calcul, pas de la relation : c'est lui
                // qui fixe l'ordre, et les infobulles doivent suivre les
                // pastilles.
                AvatarStack(noms: kpi.presence.names,
                            initiales: MeetingKPIBuilder.initials)
            }
        }
    }

    // MARK: - Actions

    private var actionsCard: some View {
        card(action: nil) {
            entete("ACTIONS",
                   valeur: "\(kpi.actions.total)",
                   complement: kpi.actions.unassigned > 0
                       ? "\(kpi.actions.unassigned) non assignée\(kpi.actions.unassigned > 1 ? "s" : "")"
                       : nil,
                   complementTeinte: One2OneToken.report)
            if kpi.actions.total == 0 {
                invite(.actions)
            } else {
                ProgressBar(valeur: kpi.actions.doneFraction)
            }
        }
    }

    // MARK: - Décisions

    private var decisionsCard: some View {
        card(action: kpi.decisions.count > 0 ? onFilterDecisions : nil) {
            entete("DÉCISIONS",
                   valeur: "\(kpi.decisions.count)",
                   complement: kpi.decisions.budgetCount > 0
                       ? "dont \(kpi.decisions.budgetCount) budget"
                       : nil)
            if let premiere = kpi.decisions.first {
                Text(premiere)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.ink3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                invite(.decisions)
            }
        }
    }

    // MARK: - Risques

    private var risksCard: some View {
        card(action: kpi.risks.count > 0 ? onOpenRisks : nil) {
            entete("RISQUES",
                   valeur: "\(kpi.risks.count)",
                   complement: kpi.risks.criticalCount > 0
                       ? "\(kpi.risks.criticalCount) critique\(kpi.risks.criticalCount > 1 ? "s" : "")"
                       : nil,
                   complementTeinte: One2OneToken.report)
            if kpi.risks.levels.isEmpty {
                invite(.risks)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(kpi.risks.levels.enumerated()), id: \.offset) { _, niveau in
                        Circle()
                            .fill(Self.teinte(niveau))
                            .frame(width: Self.riskDot, height: Self.riskDot)
                    }
                    if kpi.risks.overflow > 0 {
                        Text("+\(kpi.risks.overflow)")
                            .font(.plexMono(10))
                            .foregroundStyle(One2OneToken.ink4)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 12)
            }
        }
    }

    /// Teinte d'un point de risque. Aucune couleur hors `One2OneToken` :
    /// `report` pour le critique, `warn` pour l'élevé, `action` pour le
    /// modéré, `ink/4` pour le faible.
    static func teinte(_ niveau: MeetingKPI.Level) -> Color {
        switch niveau {
        case .critique: return One2OneToken.report
        case .eleve:    return One2OneToken.warn
        case .modere:   return One2OneToken.action
        case .faible:   return One2OneToken.ink4
        }
    }

    // MARK: - Fabrique de carte

    /// Une carte du bandeau. `action` nulle = carte non cliquable (la spec ne
    /// donne de cible qu'à trois des quatre).
    private func card<Content: View>(action: (() -> Void)?,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        let corps = VStack(alignment: .leading, spacing: 7) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.cardPaddingH)
        .padding(.vertical, Self.cardPaddingV)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )

        return Group {
            if let action {
                Button(action: action) { corps.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            } else {
                corps
            }
        }
    }

    /// Libellé mono, valeur 20 px/600 et complément, sur deux lignes.
    @ViewBuilder
    private func entete(_ libelle: String,
                        valeur: String,
                        complement: String?,
                        complementTeinte: Color = One2OneToken.ink3) -> some View {
        Text(libelle).sectionLabel()
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(valeur)
                .font(.plexSans(20, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            if let complement {
                Text(complement)
                    .font(.plexSans(11.5))
                    .foregroundStyle(complementTeinte)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// L'invite d'un compteur à zéro. Jamais de carte vide (spec §2.3).
    private func invite(_ kpiVide: MeetingEmptyInvite.Catalogue.KPI) -> some View {
        Text(MeetingEmptyInvite.Catalogue.kpiInvite(for: kpiVide))
            .font(.plexSans(11.5))
            .foregroundStyle(One2OneToken.inkMuted)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Bandeau KPI — plein") {
    MeetingKPIBand(
        kpi: MeetingKPI(
            presence: .init(present: 6, total: 6, percent: 100,
                            names: ["Camille Aubert", "Cédric Payet", "Laurent Deberti",
                                    "Lucas Sylvain", "Nathalie Lefèvre", "Pierre-Yves Nallet"],
                            initials: ["CA", "CP", "LD", "LS", "NL", "PY"]),
            actions: .init(total: 12, unassigned: 9, done: 3, doneFraction: 0.25),
            decisions: .init(count: 3, budgetCount: 1,
                             first: "Migration finalisée par le partenaire"),
            risks: .init(count: 5, criticalCount: 2,
                         levels: [.critique, .critique, .eleve, .modere, .faible],
                         overflow: 0)
        ),
        onManageParticipants: {}, onFilterDecisions: {}, onOpenRisks: {}
    )
    .padding(14)
    .frame(width: 1080)
    .background(One2OneToken.bgCanvas)
}

#Preview("Bandeau KPI — tout à zéro") {
    MeetingKPIBand(kpi: MeetingKPI(),
                   onManageParticipants: {}, onFilterDecisions: {}, onOpenRisks: {})
        .padding(14)
        .frame(width: 1080)
        .background(One2OneToken.bgCanvas)
}
