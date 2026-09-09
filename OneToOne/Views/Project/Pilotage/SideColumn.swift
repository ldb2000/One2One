import SwiftUI

/// La colonne latérale de 330 pt de l'onglet Pilotage (capture
/// `1d-ecran-projet-pilotage.png`) : interlocuteurs, risque, mails liés,
/// identité.
///
/// 330 pt et non `One2OneToken.projectPanelWidth` (430) : le handoff le dit
/// lui-même — « 330 dans le contenu + marges ». C'est la même colonne que le
/// rail d'actions de l'écran de réunion, d'où le jeton partagé.
struct SideColumn: View {

    static let largeur: CGFloat = One2OneToken.actionsRailWidth

    let etat: ProjectPilotageState
    let collaborateurs: [Collaborator]
    /// Le collaborateur que la chaîne libre du xlsx désigne, par rôle —
    /// `ProjectPeople.suggestedManager` / `suggestedArchitect` (décision
    /// **D3**), pour que compléter la fiche soit un clic.
    let suggestions: [String: Collaborator]

    let onOuvrirCollaborateur: (UUID) -> Void
    let onAffecter: (String, Collaborator?) -> Void
    let onSponsor: (String) -> Void
    let onRisque: (String) -> Void
    let onDescriptionDeRisque: (String) -> Void
    let onRattacherLesMails: () -> Void
    let onFicheComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PilotageMetrics.ecartCartes) {
            InterlocutorsCard(personnes: etat.people,
                              collaborateurs: collaborateurs,
                              suggestions: suggestions,
                              onOuvrirCollaborateur: onOuvrirCollaborateur,
                              onAffecter: onAffecter,
                              onSponsor: onSponsor)
            RiskCard(niveau: etat.risk,
                     brut: etat.riskRaw,
                     description: etat.riskDescription,
                     onNiveau: onRisque,
                     onDescription: onDescriptionDeRisque)
            LinkedMailsCard(mails: etat.mails,
                            invite: etat.pendingMailLabel,
                            onRattacher: onRattacherLesMails)
            IdentityCard(lignes: etat.identity, onFicheComplete: onFicheComplete)
        }
        .frame(width: Self.largeur, alignment: .leading)
    }
}

// MARK: - Interlocuteurs

/// « INTERLOCUTEURS » : chef de projet, architecte, sponsor.
///
/// **La relation fait foi** (décision **D3**) : un rôle non pourvu s'affiche
/// en pointillés, même si la colonne libre du xlsx porte un nom — et c'est
/// cette ligne-là qui dit à quoi la fiche est incomplète. Le `＋` la comble :
/// un menu de collaborateurs pour les deux rôles reliés (avec en tête le nom
/// que le xlsx suggère), un champ de saisie pour le sponsor, qui n'est pas
/// une relation.
struct InterlocutorsCard: View {

    static let titre = "INTERLOCUTEURS"
    static let raccourci = "1:1 ▸"
    static let ajouter = "＋"
    static let suggere = "Suggéré"
    static let aucun = "Aucun"
    static let placeholderSponsor = "Nom du sponsor"

    static let tailleNom: CGFloat = 12.5
    /// Le rôle est à 11 pt : trop petit pour `inkMuted` (plancher 11,5), donc
    /// en `ink4`, qui atteint 4,5:1 — même arbitrage qu'au lot 1.
    static let tailleRole: CGFloat = 11
    static let tailleLien: CGFloat = 11

    let personnes: [ProjectPilotageState.PersonRow]
    let collaborateurs: [Collaborator]
    let suggestions: [String: Collaborator]
    let onOuvrirCollaborateur: (UUID) -> Void
    let onAffecter: (String, Collaborator?) -> Void
    let onSponsor: (String) -> Void

    var body: some View {
        PilotageCard {
            Text(Self.titre).sectionLabel()
                .padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(personnes) { personne in
                    row(personne)
                }
            }
        }
    }

    private func row(_ personne: ProjectPilotageState.PersonRow) -> some View {
        HStack(spacing: 9) {
            avatar(personne)
            VStack(alignment: .leading, spacing: 1) {
                Text(personne.nom)
                    .font(personne.aRenseigner
                          ? .plexSansItalic(Self.tailleNom)
                          : .plexSans(Self.tailleNom))
                    .foregroundStyle(personne.aRenseigner ? One2OneToken.inkMuted : One2OneToken.ink1)
                    .lineLimit(1)
                Text(personne.role)
                    .font(.plexSans(Self.tailleRole))
                    .foregroundStyle(One2OneToken.ink4)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            action(personne)
        }
    }

    @ViewBuilder
    private func avatar(_ personne: ProjectPilotageState.PersonRow) -> some View {
        if personne.aRenseigner {
            Circle()
                .strokeBorder(One2OneToken.dashedBorder,
                              style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: AvatarStack.diametreProjet, height: AvatarStack.diametreProjet)
        } else {
            AvatarStack(noms: [personne.nom], diametre: AvatarStack.diametreProjet)
        }
    }

    @ViewBuilder
    private func action(_ personne: ProjectPilotageState.PersonRow) -> some View {
        if let id = personne.collaboratorID {
            Button { onOuvrirCollaborateur(id) } label: {
                Text(Self.raccourci)
                    .font(.plexSans(Self.tailleLien))
                    .foregroundStyle(One2OneToken.actionInk)
            }
            .buttonStyle(.plain)
            .help("Ouvrir la fiche de \(personne.nom)")
        } else if personne.aRenseigner, personne.role == "Sponsor" {
            EditableInPlace(valeur: "",
                            placeholder: Self.placeholderSponsor,
                            fonte: .plexSans(Self.tailleNom),
                            onValider: onSponsor) {
                Text(Self.ajouter)
                    .font(.plexSans(Self.tailleLien))
                    .foregroundStyle(One2OneToken.actionInk)
            }
        } else if personne.aRenseigner {
            Menu {
                if let suggere = suggestions[personne.role] {
                    Button("\(suggere.name) · \(Self.suggere)") {
                        onAffecter(personne.role, suggere)
                    }
                    Divider()
                }
                ForEach(collaborateurs) { collaborateur in
                    Button(collaborateur.name) { onAffecter(personne.role, collaborateur) }
                }
            } label: {
                Text(Self.ajouter)
                    .font(.plexSans(Self.tailleLien))
                    .foregroundStyle(One2OneToken.actionInk)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Affecter un \(personne.role.lowercased())")
        }
    }
}

// MARK: - Risque

/// « RISQUE » : le niveau, sa pastille, sa description, et « Modifier ».
///
/// « Modifier » est un **menu**, pas une bascule d'édition : changer un niveau
/// de risque, c'est choisir dans une liste de quatre valeurs plus l'absence.
/// La description, elle, s'édite au clic comme le périmètre (décision **D9**).
struct RiskCard: View {

    static let titre = "RISQUE"
    static let modifier = "Modifier"
    static let aucun = "Aucun risque déclaré"
    static let placeholder = "Décrire le risque…"
    static let inviteDescription = "Cliquer pour décrire le risque"

    static let taillePastille: CGFloat = 9
    static let tailleNiveau: CGFloat = 13
    static let tailleDescription: CGFloat = 12.5
    static let tailleLien: CGFloat = 11
    /// Interligne 1.5 du handoff, exprimé en points ajoutés.
    static var interligne: CGFloat { tailleDescription * 0.5 }

    let niveau: RiskLevel?
    /// La valeur persistée : affichée telle quelle si elle est hors table
    /// (décision **D14**).
    let brut: String
    let description: String
    let onNiveau: (String) -> Void
    let onDescription: (String) -> Void

    var body: some View {
        PilotageCard {
            HStack(spacing: 8) {
                Text(Self.titre).sectionLabel()
                Spacer(minLength: 8)
                menu
            }
            .padding(.bottom, 9)
            niveauRow
            EditableInPlace(valeur: description,
                            placeholder: Self.placeholder,
                            mode: .paragraphe,
                            fonte: .plexSans(Self.tailleDescription),
                            onValider: onDescription) {
                Text(description.isEmpty ? Self.inviteDescription : description)
                    .font(.plexSans(Self.tailleDescription))
                    .foregroundStyle(description.isEmpty ? One2OneToken.inkMuted : One2OneToken.ink2)
                    .lineSpacing(Self.interligne)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 7)
        }
    }

    private var menu: some View {
        Menu {
            ForEach(RiskLevel.allCases, id: \.self) { valeur in
                Button(valeur.label) { onNiveau(valeur.label) }
            }
            Divider()
            Button(Self.aucun) { onNiveau("") }
        } label: {
            Text(Self.modifier)
                .font(.plexSans(Self.tailleLien))
                .foregroundStyle(One2OneToken.actionInk)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var niveauRow: some View {
        HStack(spacing: 7) {
            if let niveau {
                Circle()
                    .fill(RiskBadge.teinte(niveau))
                    .frame(width: Self.taillePastille, height: Self.taillePastille)
                Text(niveau.label)
                    .font(.plexSans(Self.tailleNiveau, .medium))
                    .foregroundStyle(RiskBadge.encre(niveau))
            } else if !brut.isEmpty {
                Circle()
                    .fill(One2OneToken.inkMuted)
                    .frame(width: Self.taillePastille, height: Self.taillePastille)
                Text(brut)
                    .font(.plexSans(Self.tailleNiveau, .medium))
                    .foregroundStyle(One2OneToken.ink4)
            } else {
                Text(Self.aucun)
                    .font(.plexSans(Self.tailleNiveau))
                    .foregroundStyle(One2OneToken.inkMuted)
            }
        }
    }
}

// MARK: - Mails liés

/// « MAILS LIÉS » : les trois derniers mails du projet, et l'invite de
/// rattachement quand le scan automatique en a repéré d'autres.
struct LinkedMailsCard: View {

    static let titre = "MAILS LIÉS"
    static let vide = "Aucun mail rattaché à ce projet."
    static let etincelle = "✦"

    static let tailleSujet: CGFloat = 12.5
    /// Même arbitrage que la carte Interlocuteurs : 11 pt, donc `ink4`.
    static let tailleSousLigne: CGFloat = 11
    static let tailleInvite: CGFloat = 11.5

    let mails: [ProjectPilotageState.MailRow]
    let invite: String?
    let onRattacher: () -> Void

    var body: some View {
        PilotageCard {
            Text(Self.titre).sectionLabel()
                .padding(.bottom, 9)
            VStack(alignment: .leading, spacing: 9) {
                if mails.isEmpty {
                    Text(Self.vide)
                        .font(.plexSans(Self.tailleInvite))
                        .foregroundStyle(One2OneToken.inkMuted)
                }
                ForEach(mails) { mail in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mail.sujet)
                            .font(.plexSans(Self.tailleSujet))
                            .foregroundStyle(One2OneToken.ink1)
                            .lineLimit(1)
                        Text(mail.sousLigne)
                            .font(.plexSans(Self.tailleSousLigne))
                            .foregroundStyle(One2OneToken.ink4)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let invite {
                    encart(invite)
                }
            }
        }
    }

    private func encart(_ texte: String) -> some View {
        Button(action: onRattacher) {
            HStack(spacing: 7) {
                Text(Self.etincelle)
                    .font(.plexSans(Self.tailleInvite))
                    .foregroundStyle(One2OneToken.actionInk)
                Text(texte)
                    .font(.plexSans(Self.tailleInvite))
                    .foregroundStyle(One2OneToken.actionInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                    .fill(One2OneToken.actionBg)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ouvrir la file de validation des mails")
    }
}

// MARK: - Identité

/// « IDENTITÉ » : code, domaine, jours, fin de design, DAT / DIT — et le lien
/// vers l'onglet « Fiche complète », qui porte tout le reste.
struct IdentityCard: View {

    static let titre = "IDENTITÉ"
    static let lien = "Voir la fiche complète ▸"

    static let tailleLibelle: CGFloat = 12.5
    static let tailleValeur: CGFloat = 12.5
    static let tailleCode: CGFloat = 12
    static let tailleLien: CGFloat = 11.5
    /// Largeur de la colonne des libellés : « Fin design » est le plus long.
    static let largeurLibelle: CGFloat = 86

    let lignes: [ProjectPilotageState.IdentityRow]
    let onFicheComplete: () -> Void

    var body: some View {
        PilotageCard {
            Text(Self.titre).sectionLabel()
                .padding(.bottom, 9)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lignes) { ligne in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(ligne.libelle)
                            .font(.plexSans(Self.tailleLibelle))
                            .foregroundStyle(One2OneToken.ink4)
                            .frame(width: Self.largeurLibelle, alignment: .leading)
                        Text(ligne.valeur)
                            .font(ligne.mono
                                  ? .plexMono(Self.tailleCode, .medium)
                                  : .plexSans(Self.tailleValeur))
                            .foregroundStyle(ligne.absente ? One2OneToken.inkMuted : One2OneToken.ink2)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            Button(action: onFicheComplete) {
                Text(Self.lien)
                    .font(.plexSans(Self.tailleLien))
                    .foregroundStyle(One2OneToken.actionInk)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }
}
