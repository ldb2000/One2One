import SwiftUI
import SwiftData

/// La carte `SUJETS RÉCURRENTS` de la capture 2b : des chips `label · n`
/// colorées par famille.
struct RecurringTopicsCardModel: Equatable, Sendable {

    var topics: [RecurringTopic]

    var isEmpty: Bool { topics.isEmpty }

    @MainActor
    static func build(_ thread: OneOnOneThread, now: Date) -> RecurringTopicsCardModel {
        RecurringTopicsCardModel(topics: RecurringTopicsBuilder.build(thread, now: now,
                                                                     since: nil))
    }

    /// Le ton d'une chip, tel que la famille le porte (`RecurringTopicFamily`) :
    /// charge et astreintes en `warn`, carrière et formation en violet,
    /// reconnaissance en `ok`.
    static func tone(of topic: RecurringTopic) -> ChipTon {
        switch topic.family.tone {
        case .warn:     return .warn
        case .oneOnOne: return .oneOnOne
        case .ok:       return .ok
        case .report:   return .report
        }
    }
}

/// La carte `SUJETS RÉCURRENTS` (capture 2b).
struct RecurringTopicsCard: View {

    let model: RecurringTopicsCardModel

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("Sujets récurrents").sectionLabel()

                if model.isEmpty {
                    MeetingEmptyInvite(
                        titre: "Aucun sujet récurrent",
                        invite: "Les thèmes de l'ordre du jour et des notes se comptent tout "
                              + "seuls : un sujet revenu trois fois remonte ici."
                    )
                } else {
                    // Un flux et non une grille : les chips ont des largeurs
                    // très différentes (« Reconnaissance · 2 » fait le double
                    // de « Formation · 2 »), et une grille laisserait des
                    // trous que la capture n'a pas.
                    ChipFlow(spacing: 6, lineSpacing: 6) {
                        ForEach(model.topics) { sujet in
                            Chip(RecurringTopicsBuilder.chipLabel(sujet),
                                 ton: RecurringTopicsCardModel.tone(of: sujet))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Une disposition en flux : les éléments s'alignent et passent à la ligne
/// quand la largeur manque.
///
/// `Layout` et non un `HStack` dans une `ScrollView` horizontale : la carte de
/// la capture est étroite (320 px) et montre **deux lignes** de chips. Un
/// défilement horizontal cacherait la moitié des sujets récurrents, qui sont
/// précisément ce que l'écran veut faire voir d'un coup d'œil.
struct ChipFlow: Layout {

    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? .infinity
        let lignes = rows(subviews: subviews, maxWidth: largeur)
        let hauteur = lignes.reduce(CGFloat.zero) { total, ligne in
            total + ligne.height
        } + max(0, CGFloat(lignes.count - 1)) * lineSpacing
        let plusLarge = lignes.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? plusLarge, height: hauteur)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        var y = bounds.minY
        for ligne in rows(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in ligne.indices {
                let taille = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (ligne.height - taille.height) / 2),
                                      anchor: .topLeading,
                                      proposal: ProposedViewSize(taille))
                x += taille.width + spacing
            }
            y += ligne.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var lignes: [Row] = []
        var courante = Row()
        for index in subviews.indices {
            let taille = subviews[index].sizeThatFits(.unspecified)
            let largeurAvec = courante.indices.isEmpty
                ? taille.width
                : courante.width + spacing + taille.width
            if !courante.indices.isEmpty && largeurAvec > maxWidth {
                lignes.append(courante)
                courante = Row()
                courante.indices = [index]
                courante.width = taille.width
                courante.height = taille.height
            } else {
                courante.indices.append(index)
                courante.width = largeurAvec
                courante.height = max(courante.height, taille.height)
            }
        }
        if !courante.indices.isEmpty { lignes.append(courante) }
        return lignes
    }
}
