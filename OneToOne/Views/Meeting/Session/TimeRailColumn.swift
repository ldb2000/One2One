import SwiftUI
import SwiftData

/// La **colonne temps** de 78 px du mode séance (spec §2.6, capture
/// `1b-mode-seance.png`).
///
/// « Axe vertical 3 px, portion écoulée `#e04b3f` ; marqueurs — rond
/// `dark/accent action` pour une note, carré 3 px de rayon `accent/report`
/// pour une décision, trait plein `dark/ink` pour la position courante.
/// Libellé mono à gauche, aligné à 30 px du rail. »
///
/// Aucun calcul ici : tout vient de `TimeRailGeometry`, testé à part. La vue
/// dessine et déclenche.
struct TimeRailColumn: View {

    let meeting: Meeting
    let screen: MeetingScreenModel

    @Environment(\.one2OneTheme) private var theme
    @Environment(\.modelContext) private var context
    private var c: One2OneColors { theme.colors }

    /// Durée de l'axe. Celle de la tête de lecture si elle en connaît une,
    /// sinon celle de la réunion : sans échelle, la colonne serait muette.
    private var duree: Double {
        max(screen.playhead.duration, Double(meeting.durationSeconds))
    }

    private var reperes: [MeetingPlayhead.Marker] {
        screen.playhead.markers
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Temps").sectionLabel()
                .padding(.top, 12)
                .padding(.bottom, 10)
            axe
                .frame(maxHeight: .infinity)
            boutonMarquer
                .padding(.bottom, 16)
        }
        .frame(width: TimeRailGeometry.columnWidth)
        .background(c.base)
    }

    // MARK: - Axe

    private var axe: some View {
        GeometryReader { geo in
            let longueur = geo.size.height
            let position = TimeRailGeometry.y(t: screen.playhead.t,
                                              duration: duree,
                                              length: longueur)
            ZStack(alignment: .topLeading) {
                // Le rail au repos, sur toute la hauteur.
                Rectangle()
                    .fill(c.hair)
                    .frame(width: TimeRailGeometry.axisWidth, height: longueur)
                    .position(x: TimeRailGeometry.axisCenterX, y: longueur / 2)

                // La portion écoulée. `#e04b3f` : la spec §2.6 la nomme, et ce
                // n'est pas `accent/report`.
                Rectangle()
                    .fill(One2OneToken.railElapsed)
                    .frame(width: TimeRailGeometry.axisWidth, height: max(position, 0))
                    .position(x: TimeRailGeometry.axisCenterX, y: max(position, 0) / 2)

                ForEach(reperes) { repere in
                    forme(for: repere)
                        .position(x: TimeRailGeometry.axisCenterX,
                                  y: TimeRailGeometry.y(t: repere.t,
                                                        duration: duree,
                                                        length: longueur))
                }

                // Le trait de position, dessiné **après** les repères : on doit
                // voir où l'on est même quand une note est posée juste là.
                Rectangle()
                    .fill(c.ink1)
                    .frame(width: TimeRailGeometry.positionWidth,
                           height: TimeRailGeometry.positionHeight)
                    .position(x: TimeRailGeometry.axisCenterX, y: position)

                ForEach(TimeRailGeometry.labels(markers: reperes,
                                                position: screen.playhead.t,
                                                duration: duree,
                                                length: longueur)) { libelle in
                    Text(libelle.text)
                        .font(.plexMono(10, .medium))
                        .monospacedDigit()
                        .foregroundStyle(libelle.isPosition ? c.ink1 : c.ink4)
                        .frame(width: TimecodeLabel.width, alignment: .leading)
                        .position(x: TimeRailGeometry.labelX + TimecodeLabel.width / 2,
                                  y: libelle.y)
                }
            }
            .frame(width: geo.size.width, height: longueur, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { point in
                let t = TimeRailGeometry.t(y: point.y, duration: duree, length: longueur)
                screen.playhead.seek(to: t)
            }
        }
    }

    /// Rond pour une note, carré à coins arrondis pour une décision
    /// (spec §2.6).
    @ViewBuilder
    private func forme(for repere: MeetingPlayhead.Marker) -> some View {
        switch TimeRailGeometry.shape(for: repere.kind) {
        case .dot:
            Circle()
                .fill(c.action)
                .frame(width: TimeRailGeometry.noteDiameter,
                       height: TimeRailGeometry.noteDiameter)
                .help(aide(for: repere))
        case .square:
            RoundedRectangle(cornerRadius: TimeRailGeometry.decisionCornerRadius,
                             style: .continuous)
                .fill(One2OneToken.report)
                .frame(width: TimeRailGeometry.decisionSide,
                       height: TimeRailGeometry.decisionSide)
                .help(aide(for: repere))
        }
    }

    private func aide(for repere: MeetingPlayhead.Marker) -> String {
        let texte = repere.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let instant = MeetingPlayhead.mmss(repere.t)
        return texte.isEmpty ? instant : "\(instant) — \(texte)"
    }

    // MARK: - Marquer

    /// `⊕ Marquer ⌘M` en pied de colonne (capture 1b, spec §1.4 : « `⌘M` —
    /// marqueur sur l'axe temps à l'instant courant »).
    ///
    /// Le marqueur est une `MeetingNote(kind: .note, text: "")` — décision D4.1
    /// du lot : la colonne de notes ne l'affiche pas tant qu'il est vide, mais
    /// `MeetingTimelineMarkers` le lit déjà et le repère apparaît sur l'axe.
    /// Un type « marqueur pur » aurait demandé une colonne, une migration et un
    /// second chemin de repère pour le même besoin.
    private var boutonMarquer: some View {
        VStack(spacing: 5) {
            Button(action: marquer) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(c.ink2)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(c.pill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Poser un marqueur à l'instant courant (⌘M)")

            Text("Marquer")
                .font(.plexSans(10.5))
                .foregroundStyle(c.ink3)
            Text("⌘M")
                .font(.plexMono(9.5))
                .foregroundStyle(c.ink4)
        }
        .overlay {
            // Le raccourci vit dans la surface qui le rend possible. L'item de
            // menu `⌘M` (`MeetingCommands`) reste en place pour le mode
            // fenêtré ; ici c'est la colonne qui le porte, et c'est elle qui
            // sait à quelle réunion l'attacher.
            Button("") { marquer() }
                .keyboardShortcut("m", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private func marquer() {
        let note = MeetingNote(t: screen.playhead.t,
                               text: "",
                               kind: .note,
                               visibility: MeetingNoteStore.defaultVisibility(for: meeting.kind),
                               orderIndex: MeetingNoteStore.nextOrderIndex(at: screen.playhead.t,
                                                                          in: meeting))
        context.insert(note)
        note.meeting = meeting
        try? context.save()
        // Le repère doit apparaître tout de suite : la frise et cette colonne
        // lisent `playhead.markers`, que seul un recalcul remplit.
        screen.playhead.markers = MeetingTimelineMarkers.markers(for: meeting)
    }
}
