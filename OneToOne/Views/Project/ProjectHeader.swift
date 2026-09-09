import SwiftUI

/// L'en-tête de l'écran projet (capture `1d-ecran-projet-pilotage.png`) : fil
/// d'Ariane, nom, rangée de pilules, et les trois commandes de droite.
///
/// **Les pilules réutilisent les tables de teintes du lot 2** — `StatusIcon`,
/// `PhaseBadge`, `RiskBadge` — et non leurs géométries : le tableau du
/// Portfolio dessine des badges de rayon 4 à 11,5 pt, la capture 1d dessine
/// des capsules de 12 pt. Deux formes, une seule table de couleurs ; c'est ce
/// que « badge de phase bleu » doit vouloir dire partout.
struct ProjectHeader: View {

    // MARK: - Libellés et mesures du handoff §1d

    static let racine = "Portfolio"
    static let epingler = "Épingler"
    static let epingle = "Épinglé"
    static let demarrerUneReunion = "Démarrer une réunion"
    static let plus = "···"
    static let archiver = "Archiver"
    static let desarchiver = "Désarchiver"
    static let supprimer = "Supprimer"
    static let ouvrirLaFiche = "Ouvrir la fiche complète"
    static let confirmerLaSuppression = "Supprimer ce projet ?"
    /// Archiver retire le projet du Portfolio et de la barre latérale : ce
    /// n'est pas destructeur, mais c'est un projet qui **disparaît** de tous
    /// les écrans où on le cherchait. La question est donc posée — au
    /// contraire de « Désarchiver », qui ne fait que le ramener.
    static let confirmerLArchivage = "Archiver ce projet ?"
    static let detailDeLArchivage = "Le projet quitte le Portfolio et la barre latérale. "
                                  + "Rien n'est supprimé : « Désarchiver » le ramène."
    static let annuler = "Annuler"
    static let conserver = "Conserver"
    static let detailDeLaSuppression = "Le projet, ses jalons, ses actions et ses pièces "
                                     + "jointes seront supprimés."
    static let sansEntite = "Sans entité"
    static let changerLeStatut = "Changer le statut du projet"
    static let drapeau = "⚑"

    static let tailleFilDAriane: CGFloat = 11
    static let tailleTitre: CGFloat = 21
    static let taillePilule: CGFloat = 12
    static let tailleBouton: CGFloat = 12.5
    static let taillePastilleStatut: CGFloat = 8

    // MARK: - Entrées

    let project: Project
    let etat: ProjectPilotageState
    let onPortfolio: () -> Void
    let onEntite: () -> Void
    let onEpingler: () -> Void
    let onDemarrerUneReunion: () -> Void
    let onArchiver: () -> Void
    let onSupprimer: () -> Void
    let onFicheComplete: () -> Void
    /// Le statut choisi dans le menu de la pilule — la valeur **persistée**
    /// (`Green`, `Yellow`, `Red`, `Unknown`), pas son libellé français.
    var onStatut: (String) -> Void = { _ in }
    /// « Compléter » de la vue « À risque » (lot 5) : le champ à ouvrir, et
    /// le rappel qui le consomme. Seul `.status` concerne cet en-tête.
    var champActif: ProjectField?
    var onChampConsomme: () -> Void = {}

    /// Le menu de statut est-il déplié ?
    @State private var menuDeStatut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            filDAriane
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(project.name.isEmpty ? "Projet sans nom" : project.name)
                        .font(.plexSans(Self.tailleTitre, .semibold))
                        .foregroundStyle(One2OneToken.ink1)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    pilules
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                commandes
            }
        }
        .onAppear { honorer(champActif) }
        .onChange(of: champActif) { _, nouveau in honorer(nouveau) }
    }

    /// Honore la consigne venue de la vue « À risque » et la consomme.
    private func honorer(_ champ: ProjectField?) {
        guard champ == .status else { return }
        menuDeStatut = true
        onChampConsomme()
    }

    // MARK: - Fil d'Ariane

    /// `Portfolio / ASP / P25_193`. Les deux premiers segments sont
    /// cliquables ; le code ne l'est pas — il désigne l'écran affiché.
    private var filDAriane: some View {
        HStack(spacing: 6) {
            segment(Self.racine, action: onPortfolio)
            separateur
            segment(entite, action: onEntite)
            separateur
            Text(project.code.isEmpty ? ProjectPilotageBuilder.tiret : project.code)
                .font(.plexMono(Self.tailleFilDAriane, .medium))
                .foregroundStyle(One2OneToken.inkMuted)
        }
        .lineLimit(1)
    }

    /// L'entité affichée : la relation, à défaut le domaine — la même règle
    /// que la colonne « Entité » du Portfolio.
    var entite: String {
        for candidat in [project.entity?.name, project.domain] {
            if let net = candidat?.trimmingCharacters(in: .whitespacesAndNewlines), !net.isEmpty {
                return net
            }
        }
        return Self.sansEntite
    }

    private func segment(_ texte: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(texte)
                .font(.plexMono(Self.tailleFilDAriane, .medium))
                .foregroundStyle(One2OneToken.actionInk)
        }
        .buttonStyle(.plain)
    }

    private var separateur: some View {
        Text("/")
            .font(.plexMono(Self.tailleFilDAriane, .medium))
            .foregroundStyle(One2OneToken.inkMuted)
    }

    // MARK: - Pilules

    private var pilules: some View {
        HStack(spacing: 8) {
            piluleDeStatut
            if !project.phase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let phase = ProjectPhase(raw: project.phase)
                pilule("Phase \(phase?.label ?? project.phase)",
                       fond: PhaseBadge.fond(phase),
                       encre: PhaseBadge.encre(phase),
                       graisse: .medium)
            }
            if !project.projectType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                piluleNeutre(project.projectType)
            }
            piluleNeutre(entite)
            if let alerte = etat.deadlineAlert {
                Text("\(Self.drapeau) \(alerte)")
                    .font(.plexSans(Self.taillePilule, .medium))
                    .foregroundStyle(One2OneToken.reportInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// « ● Au vert » : la pastille de `StatusIcon` et le libellé français de
    /// `ProjectStatus.displayLabel`, posé au lot 0 pour cette rangée.
    private var piluleDeStatut: some View {
        let statut = ProjectStatus(raw: project.status)
        return Button { menuDeStatut = true } label: {
            HStack(spacing: 6) {
                StatusIcon(status: project.status, size: Self.taillePastilleStatut)
                Text(statut?.displayLabel ?? project.status)
                    .font(.plexSans(Self.taillePilule, .medium))
            }
            .foregroundStyle(Self.encreDeStatut(statut))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(Self.fondDeStatut(statut)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Self.changerLeStatut)
        // Un `popover` et non un `Menu` : « Compléter » de la vue « À risque »
        // (lot 5) doit pouvoir l'ouvrir **par programme**, ce qu'un menu ne
        // permet pas.
        .popover(isPresented: $menuDeStatut, arrowEdge: .bottom) {
            StatusPicker(courant: project.status) { valeur in
                menuDeStatut = false
                onStatut(valeur)
            }
        }
    }

    /// Le fond de la pilule de statut : `okBg` / `warnBg` / `reportBg`
    /// (handoff §1d), `surfaceAlt` pour un statut inconnu — le neutre que la
    /// règle D14 impose à toute valeur hors table.
    static func fondDeStatut(_ statut: ProjectStatus?) -> Color {
        switch statut {
        case .green?:  return One2OneToken.okBg
        case .yellow?: return One2OneToken.warnBg
        case .red?:    return One2OneToken.reportBg
        case .unknown?, nil: return One2OneToken.surfaceAlt
        }
    }

    /// L'encre de la pilule de statut : la version foncée de chaque accent.
    static func encreDeStatut(_ statut: ProjectStatus?) -> Color {
        switch statut {
        case .green?:  return One2OneToken.okDeep
        case .yellow?: return One2OneToken.warnInk
        case .red?:    return One2OneToken.reportInk
        case .unknown?, nil: return One2OneToken.ink4
        }
    }

    private func pilule(_ texte: String,
                        fond: Color,
                        encre: Color,
                        graisse: PlexWeight) -> some View {
        Text(texte)
            .font(.plexSans(Self.taillePilule, graisse))
            .foregroundStyle(encre)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(fond))
    }

    /// La pilule bordée des valeurs sans accent — le type et l'entité.
    private func piluleNeutre(_ texte: String) -> some View {
        Text(texte)
            .font(.plexSans(Self.taillePilule))
            .foregroundStyle(One2OneToken.ink3)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(One2OneToken.bgApp))
            .overlay(Capsule().strokeBorder(One2OneToken.cardBorder, lineWidth: 1))
    }

    // MARK: - Commandes

    private var commandes: some View {
        HStack(spacing: 8) {
            boutonEpingler
            boutonDemarrer
            menu
        }
        .fixedSize()
    }

    private var boutonEpingler: some View {
        Button(action: onEpingler) {
            HStack(spacing: 5) {
                Image(systemName: project.pinned ? "star.fill" : "star")
                    .font(.system(size: 11))
                Text(project.pinned ? Self.epingle : Self.epingler)
                    .font(.plexSans(Self.tailleBouton))
            }
            .foregroundStyle(One2OneToken.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                    .fill(One2OneToken.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                    .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(project.pinned ? "Retirer des épinglés" : "Épingler dans la barre latérale")
    }

    private var boutonDemarrer: some View {
        Button(action: onDemarrerUneReunion) {
            Text(Self.demarrerUneReunion)
                .font(.plexSans(Self.tailleBouton, .medium))
                .foregroundStyle(One2OneToken.onFilledButton)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.action)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var menu: some View {
        Menu {
            Button(project.isArchived ? Self.desarchiver : Self.archiver, action: onArchiver)
            Button(Self.ouvrirLaFiche, action: onFicheComplete)
            Divider()
            Button(Self.supprimer, role: .destructive, action: onSupprimer)
        } label: {
            Text(Self.plus)
                .font(.plexSans(Self.tailleBouton))
                .foregroundStyle(One2OneToken.ink3)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        // `.borderlessButton` fait redessiner l'étiquette par un bouton AppKit,
        // qui jette tout ce qui n'est pas un titre ou une image (correction du
        // lot 2 sur les chips du Portfolio). `.button` + `.plain` la rend
        // telle qu'elle est écrite.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Sélecteur de statut

/// Le menu de la pilule de statut : les quatre valeurs de `ProjectStatus`,
/// avec leur pastille et leur libellé français.
///
/// **La valeur rendue est celle qui se persiste** (`Green`, `Yellow`, `Red`,
/// `Unknown`) : `Project.status` reste une `String` libre (contrainte
/// globale), et l'énumération D14 n'est qu'une lecture.
///
/// Un `popover` et non un `Menu`, pour que « Compléter » de la vue
/// « À risque » (lot 5) puisse l'ouvrir sans clic.
struct StatusPicker: View {

    static let titre = "STATUT"
    static let largeur: CGFloat = 200
    static let taillePastille: CGFloat = 9
    static let tailleLibelle: CGFloat = 12.5

    /// La valeur persistée courante, pour marquer la ligne active.
    let courant: String
    let onChoisir: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.titre).sectionLabel()
                .padding(.horizontal, 10)
                .padding(.top, 10)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(ProjectStatus.allCases, id: \.self) { statut in
                    ligne(statut)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(width: Self.largeur)
        .background(One2OneToken.surface)
    }

    private func ligne(_ statut: ProjectStatus) -> some View {
        let actif = ProjectStatus(raw: courant) == statut
        return Button { onChoisir(statut.label) } label: {
            HStack(spacing: 8) {
                StatusIcon(status: statut.label, size: Self.taillePastille)
                Text(statut.displayLabel)
                    .font(.plexSans(Self.tailleLibelle))
                    .foregroundStyle(One2OneToken.ink1)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                    .fill(actif ? One2OneToken.actionBg : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
