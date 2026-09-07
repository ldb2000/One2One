import SwiftData
import SwiftUI

/// La section **`SUR CETTE PLANCHE`** du dock (spec §7.2, capture
/// `6a-atelier-planche.png`) : les objets annotés question / risque, avec
/// `＋ Action depuis la sélection` et `Épingler à mm:ss`.
struct WorkshopBoardInspector: View {

    let meeting: Meeting
    let screen: MeetingScreenModel
    let playheadT: Double

    @Environment(\.modelContext) private var context

    private var state: WorkshopState { screen.workshop }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sur cette planche".uppercased()).sectionLabel()

            if state.annotations.isEmpty {
                // Pas de section vide (règle du programme §2.1) : on dit
                // comment la remplir, puisque c'est un geste peu évident.
                Text("Annotez un objet en question ou en risque : clic droit sur la toile.")
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(state.annotations) { annotation in
                    ligne(annotation)
                }
            }

            boutons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Lignes

    /// `● Jenkins à décommissionner — dépend de la bascule runners` (report) et
    /// `◐ Qui porte la bascule ? question ouverte` (warn) sur la capture.
    private func ligne(_ annotation: BoardAnnotation) -> some View {
        Button {
            Task { await state.reveal(annotation, meeting: meeting) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: annotation.kind == .risk ? "circle.fill" : "circle.lefthalf.filled")
                    .font(.system(size: 9))
                    .foregroundStyle(couleur(annotation.kind))
                    .padding(.top, 3)
                Text(annotation.text.isEmpty ? "Objet sans libellé" : annotation.text)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sélectionner cet objet sur la planche")
        .accessibilityLabel("\(annotation.kind.label) : \(annotation.text)")
    }

    /// Question en `warn`, risque en `report` — les tons de la spec §7.2, pris
    /// aux jetons.
    private func couleur(_ kind: BoardAnnotation.Kind) -> Color {
        switch kind {
        case .question: return One2OneToken.warn
        case .risk:     return One2OneToken.report
        }
    }

    // MARK: - Boutons

    private var boutons: some View {
        HStack(spacing: 8) {
            Button {
                creerAction()
            } label: {
                Text("＋ Action depuis la sélection")
                    .font(.plexSans(11, .medium))
                    .foregroundStyle(One2OneToken.actionInk)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .fill(One2OneToken.actionBg))
            }
            .buttonStyle(.plain)
            .help("Créer une action depuis les objets sélectionnés")

            Button {
                state.pinActiveBoard(t: playheadT, meeting: meeting, context: context)
            } label: {
                Text("Épingler à \(MeetingPlayhead.mmss(playheadT))")
                    .font(.plexSans(11, .medium))
                    .foregroundStyle(One2OneToken.ink3)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .fill(One2OneToken.surfaceAlt))
                    .overlay(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .strokeBorder(One2OneToken.hair, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Poser un repère de cette planche sur la frise")
            .disabled(state.activeBoard(of: meeting) == nil)

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    /// Le titre de l'action vient de la sélection de la toile : les libellés
    /// des objets sélectionnés, ou à défaut celui du premier objet annoté — la
    /// spec dit « depuis la sélection », et une action sans titre ne se crée
    /// pas (`WorkshopState.createAction` rend alors `nil`).
    private func creerAction() {
        Task {
            let titre = await titreDeLaSelection()
            state.createAction(title: titre,
                               t: playheadT,
                               screen: screen,
                               meeting: meeting,
                               context: context)
        }
    }

    private func titreDeLaSelection() async -> String {
        let pont = state.bridge(for: meeting.ensuredStableID)
        guard let ids = try? await pont.selection(), !ids.isEmpty,
              let scene = try? await pont.scene()
        else {
            return state.annotations.first?.text ?? ""
        }
        let libelles = BoardScene.labels(in: scene, selectedIDs: ids)
        guard !libelles.isEmpty else { return state.annotations.first?.text ?? "" }
        return libelles.joined(separator: " — ")
    }
}
