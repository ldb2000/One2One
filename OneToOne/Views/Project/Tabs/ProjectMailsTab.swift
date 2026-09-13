import SwiftUI
import SwiftData

/// L'onglet « Mails » de l'écran projet : les mails rattachés, du plus récent
/// au plus ancien, et le bouton qui ouvre la file de validation du scan
/// automatique.
///
/// `MailBrowserView` et `MailSuggestionService` étaient classés « code mort à
/// arbitrer » dans `architecture.md` §13 : ils ne le sont plus (constat
/// §2.18), et c'est cet onglet qui leur redonne une porte d'entrée.
struct ProjectMailsTab: View {

    static let vide = "Aucun mail rattaché à ce projet."
    static let rattacher = "Rattacher des mails"

    static let tailleSujet: CGFloat = 13
    static let tailleMeta: CGFloat = 11.5
    static let tailleApercu: CGFloat = 12

    let mails: [ProjectMailRow]
    let onRattacher: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PilotageMetrics.ecartCartes) {
                HStack {
                    Spacer(minLength: 0)
                    Button(action: onRattacher) {
                        Text(Self.rattacher)
                            .font(.plexSans(12.5, .medium))
                            .foregroundStyle(One2OneToken.onFilledButton)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: One2OneToken.radiusButton,
                                                 style: .continuous)
                                    .fill(One2OneToken.action)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if mails.isEmpty {
                    Text(Self.vide)
                        .font(.plexSans(12.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                } else {
                    PilotageCard(marges: nil) {
                        ForEach(Array(mails.enumerated()), id: \.element.id) { rang, mail in
                            row(mail).pilotageRowSeparator(rang < mails.count - 1)
                        }
                    }
                }
            }
            .padding(.horizontal, PilotageTab.margeH)
            .padding(.top, PilotageTab.margeHaute)
            .padding(.bottom, PilotageTab.margeBasse)
        }
    }

    private func row(_ mail: ProjectMailRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(mail.sujet)
                .font(.plexSans(Self.tailleSujet, .medium))
                .foregroundStyle(One2OneToken.ink1)
                .lineLimit(1)
            Text(mail.meta)
                .font(.plexSans(Self.tailleMeta))
                .foregroundStyle(One2OneToken.inkMuted)
                .lineLimit(1)
            if !mail.apercu.isEmpty {
                Text(mail.apercu)
                    .font(.plexSans(Self.tailleApercu))
                    .foregroundStyle(One2OneToken.ink3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PilotageMetrics.margeH)
        .padding(.vertical, 10)
    }
}

/// Une ligne de l'onglet « Mails ».
struct ProjectMailRow: Identifiable, Equatable, Sendable {
    var id: PersistentIdentifier
    var sujet: String
    /// « contact@alp.example · 08/09/2026 » — l'expéditeur **entier** ici, à la
    /// différence de la carte de pilotage, qui l'abrège faute de place.
    var meta: String
    var apercu: String

    @MainActor
    init(_ mail: ProjectMail) {
        id = mail.persistentModelID
        sujet = mail.subject.isEmpty ? "Sans objet" : mail.subject
        meta = [mail.sender, ProjectPilotageBuilder.jourMoisAnnee(mail.dateReceived)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        apercu = mail.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }
}
