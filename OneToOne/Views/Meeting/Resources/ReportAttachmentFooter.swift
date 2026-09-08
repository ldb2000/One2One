import SwiftUI

/// Le pied `À L'ENVOI DU RAPPORT` du tiroir (spec §4.1, capture
/// `3a-tiroir-ressources.png`).
///
/// Trois cases, les deux premières cochées par défaut. Elles vivent **là**, au
/// bas du tiroir, et non dans l'espace Rapport : c'est en regardant ses pièces
/// qu'on décide de leur diffusion, pas en relisant un compte-rendu.
///
/// Les libellés portent des nombres réels (`les 2 pièces épinglées`, `les 6
/// participants`) : une case qui dit « joindre les pièces épinglées » alors
/// qu'il n'y en a aucune promet quelque chose de vide.
struct ReportAttachmentFooter: View {
    @Binding var options: AttachmentReportOptions
    /// Nombre de pièces épinglées dans la séance.
    let pinnedCount: Int
    /// Nombre de participants présents.
    let participantCount: Int
    /// Nom du projet, `nil` quand la réunion n'est rattachée à aucun — la
    /// troisième case disparaît alors : verser dans les documents d'un projet
    /// inexistant n'a pas de sens.
    let projectName: String?
    /// L'enregistrement de la valeur, débattu par l'appelant.
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("À L'ENVOI DU RAPPORT").sectionLabel()
            case_(cochee: options.attachPinned, libelle: libellePieces) {
                options.attachPinned.toggle()
                onChange()
            }
            case_(cochee: options.grantAccessToParticipants, libelle: libelleAcces) {
                options.grantAccessToParticipants.toggle()
                onChange()
            }
            if projectName != nil {
                case_(cochee: options.pushToProject, libelle: "Verser dans les documents du projet") {
                    options.pushToProject.toggle()
                    onChange()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(One2OneToken.bgApp)
        .overlay(alignment: .top) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    private var libellePieces: String {
        switch pinnedCount {
        case 0:  return "Joindre les pièces épinglées (aucune pour l'instant)"
        case 1:  return "Joindre la pièce épinglée"
        default: return "Joindre les \(pinnedCount) pièces épinglées"
        }
    }

    private var libelleAcces: String {
        participantCount <= 1
            ? "Donner l'accès aux participants"
            : "Donner l'accès aux \(participantCount) participants"
    }

    /// Une case à cocher au dessin de la capture : `✓` en `accent/ok` quand
    /// elle est cochée, `○` en encre discrète sinon. Pas de `Toggle` système —
    /// il impose un interrupteur bleu de 51 px de large, incompatible avec la
    /// densité d'un tiroir de 396 px.
    private func case_(cochee: Bool,
                       libelle: String,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: cochee ? "checkmark" : "circle")
                    .font(.system(size: cochee ? 10 : 8, weight: .semibold))
                    .foregroundStyle(cochee ? One2OneToken.okDeep : One2OneToken.ink4)
                    .frame(width: 12)
                Text(libelle)
                    .font(.plexSans(11.5))
                    .foregroundStyle(cochee ? One2OneToken.ink2 : One2OneToken.ink4)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(cochee ? [.isSelected] : [])
    }
}

#Preview("Pied du tiroir") {
    struct Apercu: View {
        @State private var options = AttachmentReportOptions.defaults
        var body: some View {
            ReportAttachmentFooter(options: $options, pinnedCount: 2, participantCount: 6,
                                   projectName: "S/D — Modernisation CI/CD", onChange: {})
                .frame(width: One2OneToken.resourcesDrawerWidth)
        }
    }
    return Apercu()
}
