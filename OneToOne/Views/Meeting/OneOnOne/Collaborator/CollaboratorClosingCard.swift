import SwiftUI
import SwiftData

/// `EN SORTANT` (capture 5a, pied de la colonne droite) : les deux sorties d'un
/// 1:1 subi, et le compte des lignes qui n'en font pas partie.
///
/// Deux sorties et non trois : côté collaborateur, ce n'est pas moi qui
/// planifie le prochain entretien (spec §6.1, ligne « Clôture »). Ce qui
/// s'ajoute, en revanche, c'est le **dossier annuel** — le récap d'audience
/// `.me`, celui que je relirai avant l'entretien annuel, et qui n'a de sens que
/// de ce côté de la table.
struct CollaboratorClosingCard: View {

    let meeting: Meeting
    let thread: OneOnOneThread
    var now: Date = Date()

    @State private var recapEnvoye: Bool?
    @State private var dossierEcrit: String?
    @State private var echecDuDossier = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(CollaboratorSessionModel.closingTitle)
            boutonPrimaire
            boutonSecondaire
            pied
        }
    }

    // MARK: - Envoyer mon récap

    private var boutonPrimaire: some View {
        Button {
            recapEnvoye = OneOnOneRecapActions.sendRecap(
                for: meeting,
                thread: thread,
                audience: OneOnOneConfidentiality.recapAudience(for: thread.myRole),
                now: now)
        } label: {
            Text(CollaboratorSessionModel.recapButtonLabel(for: thread))
                .font(.plexSans(12, .semibold))
                .foregroundStyle(One2OneToken.onFilledButton)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                        .fill(One2OneToken.oneOnOne)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ouvre un brouillon de mail avec le récap filtré — vos lignes privées n'y sont pas")
    }

    // MARK: - Verser dans mon dossier annuel

    private var boutonSecondaire: some View {
        Button {
            verser()
        } label: {
            Text(CollaboratorSessionModel.annualFolderButtonLabel)
                .font(.plexSans(12, .medium))
                .foregroundStyle(One2OneToken.ink2)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                        .fill(One2OneToken.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                        .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Écrit le récap complet — vos notes privées comprises — dans votre dossier annuel")
    }

    /// Audience `.me` côté service : c'est *mon* dossier, celui que je relirai
    /// avant l'entretien annuel, et y verser une version tronquée serait
    /// s'auto-censurer ses propres notes.
    private func verser() {
        do {
            let fichier = try OneOnOneRecapActions.archiveToAnnualFolder(for: meeting,
                                                                         thread: thread,
                                                                         now: now)
            dossierEcrit = fichier.lastPathComponent
            echecDuDossier = false
        } catch {
            dossierEcrit = nil
            echecDuDossier = true
        }
    }

    // MARK: - Pied

    /// Le compte des lignes exclues, **affiché systématiquement** dès qu'il y a
    /// quelque chose à compter (spec §3.2). C'est ce chiffre qui rend le
    /// bouton d'envoi honnête : je sais ce qui part et ce qui reste.
    private var pied: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let compte = CollaboratorSessionModel.excludedLinesLabel(for: meeting,
                                                                         in: thread) {
                Text(compte)
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(One2OneToken.oneOnOneInk)
            }
            // Aucun dialogue bloquant : un refus d'autorisation ou une adresse
            // manquante se dit sur place (`OneOnOneRecapActions` rend `false`).
            if recapEnvoye == false {
                Text("Le brouillon n'a pas pu s'ouvrir — vérifiez l'adresse de la fiche.")
                    .font(.plexSans(10.5))
                    .foregroundStyle(One2OneToken.reportInk)
            }
            if let fichier = dossierEcrit {
                Text("Versé dans votre dossier annuel — \(fichier)")
                    .font(.plexSans(10.5))
                    .foregroundStyle(One2OneToken.inkMuted)
            }
            if echecDuDossier {
                Text("Le dossier annuel n'a pas pu être écrit — vérifiez l'espace disque.")
                    .font(.plexSans(10.5))
                    .foregroundStyle(One2OneToken.reportInk)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
