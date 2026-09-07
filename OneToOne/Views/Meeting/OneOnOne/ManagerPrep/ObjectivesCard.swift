import SwiftUI
import SwiftData

/// La carte `OBJECTIFS S2` de la capture 2b : libellé, pourcentage, barre
/// colorée par avancement, et la date de revue en pied.
struct ObjectivesCardModel: Equatable, Sendable {

    struct Row: Equatable, Sendable, Identifiable {
        var id: PersistentIdentifier
        var label: String
        /// 0 à 100.
        var progress: Int
        var tone: OneOnOneTone

        /// La progression telle que `ProgressBar` l'attend, de 0 à 1.
        var ratio: Double { Double(progress) / 100 }
        /// `70%` — la capture n'espace pas le signe, contrairement au reste du
        /// domaine : c'est une valeur dans une colonne étroite, pas une phrase.
        var percentLabel: String { "\(progress)%" }
    }

    var rows: [Row]
    /// `Revue prévue le 18 sept.`, `nil` si aucun objectif n'a de date.
    var reviewLabel: String?

    var isEmpty: Bool { rows.isEmpty }

    @MainActor
    static func build(_ thread: OneOnOneThread) -> ObjectivesCardModel {
        let tries = OneOnOneObjectiveList.sorted(thread.objectives)
        return ObjectivesCardModel(
            rows: tries.map { objectif in
                Row(id: objectif.persistentModelID,
                    label: objectif.label,
                    progress: objectif.clampedProgress,
                    tone: objectif.tone)
            },
            reviewLabel: OneOnOneObjectiveList.reviewLabel(thread.objectives)
        )
    }
}

/// La carte `OBJECTIFS S2` (capture 2b), avec ajout et édition inline.
///
/// L'édition est **inline et non modale** : un objectif se corrige en passant,
/// pendant qu'on prépare l'entretien. Ouvrir une feuille pour changer « 25 »
/// en « 40 » ferait perdre la vue d'ensemble qui est tout l'intérêt de la
/// carte.
struct ObjectivesCard: View {

    let model: ObjectivesCardModel
    /// Ajoute un objectif (libellé, pourcentage).
    let onAdd: (String, Int) -> Void
    /// Change le pourcentage d'un objectif existant.
    let onUpdateProgress: (PersistentIdentifier, Int) -> Void
    /// Change le libellé d'un objectif existant.
    let onUpdateLabel: (PersistentIdentifier, String) -> Void

    /// La ligne en cours d'édition, `nil` quand aucune ne l'est.
    @State private var editing: PersistentIdentifier?
    @State private var draftLabel = ""
    @State private var draftProgress = ""
    /// Le composeur d'ajout est déplié.
    @State private var isAdding = false
    @State private var newLabel = ""
    @State private var newProgress = ""

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Objectifs S2").sectionLabel()
                    Spacer(minLength: 8)
                    Button { isAdding.toggle() } label: {
                        Image(systemName: isAdding ? "minus" : "plus")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(One2OneToken.oneOnOneInk)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(One2OneToken.oneOnOneBg))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isAdding ? "Fermer" : "Ajouter un objectif")
                }

                if model.isEmpty && !isAdding {
                    MeetingEmptyInvite(
                        titre: "Aucun objectif posé",
                        invite: "Un objectif tient en une phrase et un pourcentage. "
                              + "Ils cadrent l'entretien annuel autant que le prochain 1:1.",
                        libelleAction: "Ajouter un objectif"
                    ) { isAdding = true }
                } else {
                    ForEach(model.rows) { ligne in
                        if editing == ligne.id {
                            editeur(ligne)
                        } else {
                            lecture(ligne)
                        }
                    }
                }

                if isAdding { composeur }

                if let revue = model.reviewLabel {
                    Text(revue)
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Lignes

    private func lecture(_ ligne: ObjectivesCardModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(ligne.label)
                    .font(.plexSans(12.5))
                    .foregroundStyle(One2OneToken.ink2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(ligne.percentLabel)
                    .font(.plexSans(12, .medium))
                    .foregroundStyle(One2OneToken.ink2)
            }
            ProgressBar(valeur: ligne.ratio, teinte: ligne.tone.color)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            draftLabel = ligne.label
            draftProgress = "\(ligne.progress)"
            editing = ligne.id
        }
        .help("Modifier cet objectif")
    }

    private func editeur(_ ligne: ObjectivesCardModel.Row) -> some View {
        HStack(spacing: 7) {
            champ("Objectif", texte: $draftLabel)
            champPourcentage($draftProgress)
            Button("OK") {
                onUpdateLabel(ligne.id, draftLabel)
                if let valeur = Int(draftProgress) { onUpdateProgress(ligne.id, valeur) }
                editing = nil
            }
            .buttonStyle(.plain)
            .font(.plexSans(11, .medium))
            .foregroundStyle(One2OneToken.oneOnOneInk)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private var composeur: some View {
        HStack(spacing: 7) {
            champ("Nouvel objectif…", texte: $newLabel)
            champPourcentage($newProgress)
            Button("Ajouter") {
                onAdd(newLabel, Int(newProgress) ?? 0)
                newLabel = ""
                newProgress = ""
                isAdding = false
            }
            .buttonStyle(.plain)
            .font(.plexSans(11, .medium))
            .foregroundStyle(One2OneToken.oneOnOneInk)
            .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func champ(_ invite: String, texte: Binding<String>) -> some View {
        TextField(invite, text: texte)
            .textFieldStyle(.plain)
            .font(.plexSans(12))
            .foregroundStyle(One2OneToken.ink2)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                    .fill(One2OneToken.surfaceAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                    .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
            )
    }

    private func champPourcentage(_ texte: Binding<String>) -> some View {
        TextField("%", text: texte)
            .textFieldStyle(.plain)
            .font(.plexMono(11, .medium))
            .foregroundStyle(One2OneToken.ink2)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 6)
            .frame(width: 46, height: 24)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                    .fill(One2OneToken.surfaceAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                    .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
            )
    }
}
