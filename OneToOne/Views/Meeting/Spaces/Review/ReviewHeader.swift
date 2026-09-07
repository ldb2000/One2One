import SwiftUI

/// L'en-tête du poste de pilotage (spec §2.7 : « en-tête de réunion (titre +
/// métadonnées sur une ligne : `ref · type · date · durée · n participants`) »,
/// capture `1c-poste-de-pilotage.png`).
///
/// Les trois boutons de droite sont ceux de la capture : `Capture`,
/// `Exporter ⌄` — les entrées d'export existantes, regroupées — et
/// `Rapport ✓ 6:20`. Rien n'est réécrit : ce sont les closures de
/// `MeetingMenuActions`, la source de vérité unique des actions secondaires
/// d'une réunion, déjà partagée par le menu `⋯` et les menus natifs.
///
/// Le sélecteur de mode (`Préparer / En séance / Relire`) est ici parce que la
/// barre d'espaces est masquée dans ce mode (plan §1, décision D0) : sans lui,
/// on entrerait en relecture sans pouvoir en sortir.
struct ReviewHeader: View {

    /// `P25_110 · Projet · 4 sept. 2026 · 9:15 · 23 min · 6 participants`
    ///
    /// Les segments absents **disparaissent** au lieu de laisser un point
    /// médian orphelin : une réunion hors projet n'a pas de référence, et
    /// « · Projet · » se lirait comme une donnée manquante plutôt qu'inexistante.
    static func metadonnees(for meeting: Meeting,
                            locale: Locale = .current,
                            calendar: Calendar = .current) -> String {
        var segments: [String] = []
        if let code = meeting.project?.code, !code.isEmpty { segments.append(code) }
        segments.append(meeting.kind.label)
        var jour = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        jour.locale = locale
        jour.timeZone = calendar.timeZone
        segments.append(meeting.date.formatted(jour))
        // `9:15` et non `09:15` : c'est ce que montre la capture, et
        // `Date.FormatStyle.hour(.defaultDigits(amPM: .omitted))` rend deux
        // chiffres en français. L'heure est donc composée depuis le calendrier,
        // qui porte aussi le fuseau — sans quoi le test dépendrait du poste.
        let composantes = calendar.dateComponents([.hour, .minute], from: meeting.date)
        segments.append("\(composantes.hour ?? 0):\(String(format: "%02d", composantes.minute ?? 0))")
        let minutes = ReviewSidebarNav.minutes(of: meeting)
        if minutes > 0 { segments.append("\(minutes) min") }
        let n = meeting.participants.count
        if n > 0 { segments.append("\(n) participant\(n > 1 ? "s" : "")") }
        return segments.joined(separator: " · ")
    }

    /// `Rapport ✓ 6:20`, `Rapport`, `Transcrire + Rapport`.
    ///
    /// Même règle que `MeetingTopChromeBar.reportLabel` : la coche dit
    /// « généré », la durée est le temps de génération (spec §2.1). Dupliquée
    /// ici plutôt que rendue publique là-bas parce que ce lot n'a pas le droit
    /// de toucher à la barre du haut ; le test la fixe des deux côtés.
    static func libelleRapport(for meeting: Meeting) -> String {
        if meeting.rawTranscript.isEmpty { return "Transcrire + Rapport" }
        if meeting.summary.isEmpty { return "Rapport" }
        let secondes = Int(meeting.reportGenerationDurationSeconds.rounded())
        guard secondes > 0 else { return "Rapport ✓" }
        return "Rapport ✓ \(secondes / 60):\(String(format: "%02d", secondes % 60))"
    }

    /// `Capture`, `Capture 4`
    static func libelleCapture(count: Int) -> String {
        count > 0 ? "Capture \(count)" : "Capture"
    }

    // MARK: - Entrées

    let meeting: Meeting
    let screen: MeetingScreenModel
    /// Les actions secondaires de la réunion (export, édition audio, rapport).
    let menuActions: MeetingMenuActions
    /// Nombre de captures déjà prises.
    let capturesCount: Int
    /// Ouvre la galerie de captures ou sa configuration.
    let onShowCaptures: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                let modes = MeetingSpaceRouting.modes(for: meeting.kind)
                if !modes.isEmpty {
                    SegmentedMode(
                        selection: Binding(get: { screen.mode }, set: { screen.mode = $0 }),
                        options: modes,
                        libelle: \.label
                    )
                }
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title.isEmpty ? "Réunion" : titreSansReference)
                        .font(.plexSans(14, .semibold))
                        .foregroundStyle(One2OneToken.ink1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(Self.metadonnees(for: meeting))
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.ink4)
                        .lineLimit(1)
                }
                .frame(minWidth: 0, alignment: .leading)
                Spacer(minLength: 8)
                boutonCapture
                menuExport
                boutonRapport
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// Le titre sans son préfixe `[P25_110] ` : la référence est déjà dans la
    /// ligne de métadonnées juste au-dessous, et la répéter mange la largeur du
    /// sujet.
    private var titreSansReference: String {
        ReviewSidebarNav.titreCourt(meeting.title)
    }

    // MARK: - Boutons

    private var boutonCapture: some View {
        Button(action: onShowCaptures) {
            Text(Self.libelleCapture(count: capturesCount))
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(One2OneToken.ink2)
                .padding(.horizontal, 11)
                .frame(height: 26)
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
        .help(capturesCount > 0 ? "Voir les captures" : "Configurer la capture d'écran")
    }

    /// `Exporter ⌄` : les cinq destinations existantes, sans en réécrire une.
    private var menuExport: some View {
        Menu {
            Button(action: menuActions.exportMarkdown) {
                Label("Copier Markdown", systemImage: "doc.text")
            }
            Button(action: menuActions.exportPDF) {
                Label("Exporter PDF", systemImage: "doc.richtext")
            }
            Menu {
                optionsMail(menuActions.exportMail)
            } label: { Label("Envoyer via Apple Mail", systemImage: "envelope") }
            Menu {
                optionsMail(menuActions.exportOutlook)
            } label: { Label("Envoyer via Microsoft Outlook", systemImage: "paperplane") }
            Menu {
                optionsMail(menuActions.exportAppleNotes)
            } label: { Label("Exporter vers Apple Notes", systemImage: "note.text") }
        } label: {
            Text("Exporter")
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(One2OneToken.ink2)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 92, height: 26)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
        )
        .disabled(!menuActions.isEnabled(.exportMarkdown))
        .help(menuActions.hasReport
              ? "Exporter le compte-rendu"
              : "Générez le rapport avant d'exporter")
    }

    /// Les quatre variantes d'un export e-mail ou Notes, identiques à celles du
    /// menu `⋯` et des menus natifs.
    @ViewBuilder
    private func optionsMail(_ action: @escaping (MeetingMailExportOptions) -> Void) -> some View {
        Button("Rapport seul") { action([]) }
        Button("Rapport + slides (PDF)") { action(.includeSlidesPDF) }
        Button("Rapport + transcript") { action([.includeTranscript]) }
        Button("Rapport + transcript + slides") { action([.includeTranscript, .includeSlidesPDF]) }
    }

    private var boutonRapport: some View {
        let actif = menuActions.isEnabled(.generateReport)
        return Button(action: menuActions.generateReport) {
            Text(Self.libelleRapport(for: meeting))
                .font(.plexSans(10.5, .semibold))
                .foregroundStyle(One2OneToken.onFilledButton)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                        .fill(actif ? One2OneToken.report : One2OneToken.report.opacity(0.45))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .help(meeting.summary.isEmpty ? "Générer le compte-rendu" : "Régénérer le compte-rendu")
    }
}
