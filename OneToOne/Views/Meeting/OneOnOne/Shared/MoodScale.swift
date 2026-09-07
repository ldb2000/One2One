import SwiftUI
import SwiftData

/// Ce que l'échelle `① COMMENT ÇA VA` lit et écrit — **pur** hors de l'écriture
/// elle-même, qui passe par `MoodTrend.record` (lot 10).
///
/// Aucune règle n'est réécrite ici : la borne des crans, le remplacement du
/// relevé de la séance et le calcul du delta sont ceux de `MoodTrend`. Ce
/// modèle n'existe que pour que la vue n'ait pas à connaître `MoodEntry`.
@MainActor
enum MoodScaleModel {

    static let title = "① COMMENT ÇA VA"

    /// Le cran choisi pour cette séance, ou `nil` si rien n'a été saisi.
    /// Aucune valeur par défaut : « Ça va » affiché d'office serait une réponse
    /// que personne n'a donnée.
    static func selected(for meeting: Meeting, in thread: OneOnOneThread) -> MoodLevel? {
        MoodTrend.entry(for: meeting, in: thread).map { MoodLevel.clamped($0.clampedValue) }
    }

    /// Le libellé du dernier cran du fil (`Sous tension` de la capture).
    static func selectedLabel(of thread: OneOnOneThread) -> String? {
        MoodTrend.series(thread, limit: Int.max).last?.level.label
    }

    /// Enregistre le cran, **en remplaçant** le relevé de la séance.
    @discardableResult
    static func record(_ level: MoodLevel,
                       for meeting: Meeting,
                       in thread: OneOnOneThread,
                       in context: ModelContext) -> MoodEntry {
        MoodTrend.record(level.rawValue, for: meeting, in: thread, in: context)
    }

    static func tone(_ level: MoodLevel) -> OneOnOneTone {
        OneOnOneMoodTone.tone(level)
    }
}

/// `① COMMENT ÇA VA` — les cinq crans, le cran choisi **bordé de sa couleur**,
/// et le delta par rapport au 1:1 précédent (capture 2a, spec §3.3).
///
/// Le cran choisi est bordé et non rempli : la capture montre un contour ambre
/// sur `Sous tension`, sur un fond resté clair. Un fond plein ferait de
/// l'échelle la chose la plus voyante de l'écran, alors que ce qui compte est
/// écrit juste en dessous.
struct MoodScale: View {

    let meeting: Meeting
    let thread: OneOnOneThread

    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(MoodScaleModel.title)
            HStack(spacing: 6) {
                ForEach(MoodLevel.allCases) { cran in
                    bouton(cran)
                }
                if let delta = MoodTrend.deltaLabel(thread) {
                    Text(delta)
                        .font(.plexSans(11))
                        .foregroundStyle(One2OneToken.ink4)
                        .padding(.leading, 4)
                        .help("Comparé au cran du 1:1 précédent")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func bouton(_ cran: MoodLevel) -> some View {
        let choisi = MoodScaleModel.selected(for: meeting, in: thread) == cran
        let ton = MoodScaleModel.tone(cran)
        let teinte = OneOnOneMoodTone.isDeep(cran) ? One2OneToken.okDeep : ton.color
        return Button {
            MoodScaleModel.record(cran, for: meeting, in: thread, in: context)
        } label: {
            Text(cran.label)
                .font(.plexSans(11.5, choisi ? .medium : .regular))
                .foregroundStyle(choisi ? ton.inkColor : One2OneToken.ink3)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusPill, style: .continuous)
                        .fill(choisi ? ton.backgroundColor : One2OneToken.surfaceAlt)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusPill, style: .continuous)
                        .strokeBorder(choisi ? teinte : One2OneToken.hair,
                                      lineWidth: choisi ? 1.5 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(choisi ? "Cran choisi pour cet entretien" : "Noter « \(cran.label) » pour cet entretien")
    }
}
