import SwiftUI
import SwiftData

/// La carte `MORAL — 6 DERNIERS 1:1` de la capture 2b, traduite en lignes
/// prêtes à dessiner.
///
/// **C'est ce modèle qui porte le critère d'acceptation n° 3 du chantier 2** :
/// « le moral saisi en séance alimente immédiatement l'histogramme de
/// préparation suivant ». Il est pur et se reconstruit à chaque rendu depuis
/// `MoodTrend.series` : rien n'est mis en cache, donc rien ne peut être
/// périmé — et le test le vérifie sans écran.
struct MoodHistogramModel: Equatable, Sendable {

    /// Une barre de l'histogramme.
    struct Bar: Equatable, Sendable, Identifiable {
        /// Rang dans la série, de 0 (la plus ancienne) à 5.
        var id: Int
        var value: Int
        /// `12/06` — la date sous la barre.
        var dateLabel: String
        var level: MoodLevel
        /// La barre de la séance la plus récente : la seule colorée.
        var isLast: Bool

        /// Hauteur relative de la barre, de 0,2 (cran 1) à 1 (cran 5).
        var heightRatio: Double { Double(value) / Double(MoodLevel.tresBien.rawValue) }
    }

    var bars: [Bar]
    var direction: MoodTrend.Direction
    /// `en baisse` / `en hausse`, `nil` quand la tendance est stable.
    var trendLabel: String?
    var trendTone: OneOnOneTone?
    /// `Cause citée 5 fois : Charge de travail.` (`MoodTrend.explanation`) —
    /// la phrase que la spec §3.4 demande sous l'histogramme : « le sujet
    /// récurrent le plus cité sur la période ».
    var explanation: String?

    var isEmpty: Bool { bars.isEmpty }

    // MARK: - Construction

    @MainActor
    static func build(_ thread: OneOnOneThread, now: Date) -> MoodHistogramModel {
        let serie = MoodTrend.series(thread)
        let dernierRang = serie.count - 1
        let bars = serie.enumerated().map { index, point in
            Bar(id: index,
                value: point.value,
                dateLabel: OneOnOneDateFormat.shortSlashed(point.recordedAt),
                level: point.level,
                isLast: index == dernierRang)
        }
        let sens = MoodTrend.direction(serie.map(\.value))
        let sujets = RecurringTopicsBuilder.build(thread, now: now, since: nil)
            .map { (label: $0.label, count: $0.count) }

        return MoodHistogramModel(
            bars: bars,
            direction: sens,
            trendLabel: sens.label,
            trendTone: tone(for: sens),
            explanation: MoodTrend.explanation(sujets)
        )
    }

    /// La teinte d'un cran. Le cran le plus bas est un signal de rapport, pas
    /// une alerte de charge : `Difficile` n'est pas « à surveiller », c'est
    /// « déjà arrivé ».
    static func tone(for level: MoodLevel) -> OneOnOneTone {
        switch level {
        case .difficile:   return .report
        case .sousTension: return .warn
        case .caVa:        return .oneOnOne
        case .bien:        return .oneOnOne
        case .tresBien:    return .ok
        }
    }

    /// La teinte du libellé de tendance (`en baisse` en `accent/report`,
    /// `en hausse` en `accent/ok`, rien quand c'est stable).
    static func tone(for direction: MoodTrend.Direction) -> OneOnOneTone? {
        switch direction {
        case .enBaisse: return .report
        case .stable:   return nil
        case .enHausse: return .ok
        }
    }

}

/// L'histogramme `MORAL — 6 DERNIERS 1:1` (capture 2b) : six barres, la
/// dernière à la teinte de son cran, les dates en mono sous les barres et la
/// tendance en haut à droite.
struct MoodHistogram: View {

    /// Hauteur de la zone des barres, hors dates.
    static let plotHeight: CGFloat = 96
    /// Opacité des barres antérieures. La dernière est pleine : c'est elle
    /// qu'on lit, les autres donnent la pente.
    static let pastBarOpacity: Double = 0.28

    let model: MoodHistogramModel

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text("Moral — 6 derniers 1:1").sectionLabel()
                    Spacer(minLength: 8)
                    if let libelle = model.trendLabel, let ton = model.trendTone {
                        Text(libelle)
                            .font(.plexSans(11, .medium))
                            .foregroundStyle(ton.color)
                    }
                }

                if model.isEmpty {
                    MeetingEmptyInvite(
                        titre: "Aucun moral relevé",
                        invite: "En séance, la question « Comment ça va » écrit un cran par entretien : "
                              + "l'histogramme se remplit tout seul."
                    )
                } else {
                    barres
                    if let phrase = model.explanation {
                        Text(phrase)
                            .font(.plexSans(11.5))
                            .foregroundStyle(One2OneToken.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var barres: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(model.bars) { barre in
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(couleur(barre))
                        .frame(height: max(6, Self.plotHeight * barre.heightRatio))
                        .help("\(barre.dateLabel) · \(barre.level.label)")
                    Text(barre.dateLabel)
                        .font(.plexMono(10, barre.isLast ? .semibold : .medium))
                        .foregroundStyle(barre.isLast
                                         ? MoodHistogramModel.tone(for: barre.level).color
                                         : One2OneToken.ink4)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Self.plotHeight + 20, alignment: .bottom)
    }

    private func couleur(_ barre: MoodHistogramModel.Bar) -> Color {
        barre.isLast
            ? MoodHistogramModel.tone(for: barre.level).color
            : One2OneToken.oneOnOne.opacity(Self.pastBarOpacity)
    }
}

#Preview("MoodHistogram") {
    MoodHistogram(model: MoodHistogramModel(
        bars: [(3, "12/06"), (4, "26/06"), (5, "10/07"),
               (4, "24/07"), (4, "21/08"), (2, "04/09")]
            .enumerated()
            .map { index, couple in
                MoodHistogramModel.Bar(id: index, value: couple.0, dateLabel: couple.1,
                                       level: MoodLevel.clamped(couple.0), isLast: index == 5)
            },
        direction: .enBaisse,
        trendLabel: "en baisse",
        trendTone: .report,
        explanation: "Cause citée 5 fois : Charge de travail."))
        .frame(width: 380)
        .padding(20)
        .background(One2OneToken.bgCanvas)
}
