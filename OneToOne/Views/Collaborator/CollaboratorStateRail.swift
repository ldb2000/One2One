import SwiftUI
import SwiftData

/// Colonne d'état, à droite, **hors du `ScrollView` du fil** : quelle que soit
/// la position dans l'historique, l'état courant reste visible. C'est elle qui
/// répond à « où en est cette personne » sans faire défiler.
///
/// Aucun bloc ne défile : chacun montre un nombre fixe de lignes et renvoie à
/// l'écran dédié.
struct CollaboratorStateRail: View {
    @Bindable var collaborator: Collaborator
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nextOneToOne
            separator
            engagements
            separator
            actions
            separator
            projects
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FicheTokens.railBg)
    }

    private var separator: some View {
        Rectangle().fill(FicheTokens.divider).frame(height: 1)
    }

    private func title(_ text: String, trailing: String? = nil) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6).textCase(.uppercase)
                .foregroundStyle(FicheTokens.inkTertiary)
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 11)).foregroundStyle(FicheTokens.link)
            }
        }
    }

    // MARK: - Prochain 1:1

    private var nextOneToOne: some View {
        VStack(alignment: .leading, spacing: 6) {
            title("Prochain 1:1", trailing: prochain != nil ? "Ouvrir" : nil)
            if let prochain {
                Text(prochain.date.formatted(date: .complete, time: .shortened))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(FicheTokens.ink)
            } else {
                // Pas d'alerte ici : quelqu'un qu'on n'a jamais vu n'est pas
                // « en retard », il y a un rythme à commencer.
                Text(invite)
                    .font(.system(size: 11.5))
                    .foregroundStyle(OneToOneRhythm.isLate(for: collaborator, now: .now)
                                     ? FicheTokens.warn : FicheTokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    private var prochain: Meeting? {
        collaborator.meetings
            .filter { $0.kind == .oneToOne && $0.date > .now }
            .min(by: { $0.date < $1.date })
    }

    private var invite: String {
        guard let semaines = OneToOneRhythm.weeksSinceLast(for: collaborator, now: .now) else {
            return "Aucun échange à ce jour — planifier le premier"
        }
        return "Planifier — dernier échange il y a \(semaines) semaine\(semaines > 1 ? "s" : "")"
    }

    // MARK: - Engagements

    /// Ce qui a été promis de vive voix et qui traîne. Distinct des actions
    /// juste en dessous : confiance d'un côté, charge de l'autre.
    private var engagements: some View {
        let pending = EngagementLedger.pending(for: collaborator)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                title("Engagements")
                Text("\(pending.count)")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(EngagementLedger.level(count: pending.count) == .alerte
                                     ? FicheTokens.late : FicheTokens.inkSecondary)
            }
            if pending.isEmpty {
                calme("Rien promis qui traîne")
            } else {
                ForEach(pending.prefix(4)) { engagement in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "circle").font(.system(size: 10))
                            .foregroundStyle(FicheTokens.inkTertiary).padding(.top, 2)
                        Text(engagement.text)
                            .font(.system(size: 11.5)).foregroundStyle(FicheTokens.ink)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if pending.count > 4 {
                    Text("+ \(pending.count - 4) autres")
                        .font(.system(size: 11)).foregroundStyle(FicheTokens.link)
                }
            }
        }
        .padding(14)
    }

    // MARK: - Actions

    private var actions: some View {
        let ouvertes = collaborator.assignedTasks
            .filter { !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                title("Actions")
                Text("\(ouvertes.count)").font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(FicheTokens.link)
            }
            if ouvertes.isEmpty {
                // Une bonne nouvelle, pas un manque.
                calme("Rien en cours", icon: "checkmark.circle.fill", tint: FicheTokens.ok)
            } else {
                ForEach(ouvertes.prefix(4)) { task in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "square").font(.system(size: 11))
                            .foregroundStyle(FicheTokens.inkTertiary).padding(.top, 1)
                        Text(task.title).font(.system(size: 11.5))
                            .foregroundStyle(FicheTokens.ink)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if let due = task.dueDate {
                            Text(due.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(due < .now ? FicheTokens.late : FicheTokens.inkSecondary)
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    // MARK: - Projets

    private var projects: some View {
        // « Suivis », pas « portés » : le calcul lit une implication —
        // réunions et actions assignées —, pas une responsabilité désignée.
        // Un libellé qui promet plus que le calcul ne tient est un mensonge
        // qui survit au code.
        let portes = CollaboratorProjects.involved(in: collaborator)
        return VStack(alignment: .leading, spacing: 7) {
            title("Projets suivis")
            if portes.isEmpty {
                calme("Aucun projet suivi")
            } else {
                ForEach(portes.prefix(4)) { projet in
                    HStack(spacing: 7) {
                        Circle().fill(FicheTokens.ok).frame(width: 6, height: 6)
                        Text(projet.code).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(FicheTokens.inkSecondary)
                        Text(projet.name).font(.system(size: 11.5))
                            .foregroundStyle(FicheTokens.ink).lineLimit(1)
                    }
                }
                if portes.count > 4 {
                    Text("+ \(portes.count - 4) autres · tout voir")
                        .font(.system(size: 11)).foregroundStyle(FicheTokens.link)
                }
            }
        }
        .padding(14)
    }

    private func calme(_ text: String, icon: String? = nil, tint: Color = .clear) -> some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 11)).foregroundStyle(tint) }
            Text(text).font(.system(size: 11.5)).foregroundStyle(FicheTokens.inkSecondary)
        }
    }
}
