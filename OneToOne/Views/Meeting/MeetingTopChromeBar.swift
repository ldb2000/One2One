import SwiftUI
import SwiftData

/// Barre du haut de l'écran réunion, **sur une seule ligne** (spec §2.1,
/// capture `1a-cockpit.png`).
///
/// Hauteur 38 px, fond `bg/app` (teinté `accent/oneonone bg` pour les deux
/// types 1:1), bordure basse `border/card`, padding 9 × 14. De gauche à droite :
/// bouton panneau, fil d'Ariane (le segment projet est bordé `accent/action` et
/// ouvre la fiche projet), titre `flex:1` en ellipsis éditable au double-clic,
/// pilule audio `ink/1` de rayon 16, menu de type, menu de template, bouton
/// `Rapport ✓ (m:ss)` en `accent/report`, et `⋯`.
///
/// La deuxième ligne d'avant — le `MeetingTagEditor` — a déménagé dans la
/// feuille « Détails de la réunion » : la spec impose une ligne, et les thèmes
/// avaient besoin de toute la largeur pour passer à la ligne.
///
/// Vue purement présentationnelle : toute la logique métier est déléguée au
/// parent par les callbacks `on…` et par `MeetingMenuActions`.
struct MeetingTopChromeBar: View {

    // MARK: - Géométrie (spec §2.1)

    /// Hauteur de la barre. Une seule ligne, jamais deux.
    static let height: CGFloat = 38
    static let paddingVertical: CGFloat = 9
    static let paddingHorizontal: CGFloat = 14
    /// Largeur du bouton `⋯`, fixée par la spec §2.1.
    static let moreButtonWidth: CGFloat = 28

    /// Le libellé du bouton `Rapport` (`Transcrire + Rapport`,
    /// `Rapport ✓ (m:ss)`) : c'est l'action principale de la barre, et la
    /// capture `1a-cockpit.png` la montre au corps de §1.2 — 12 px, pas les
    /// 10,5 d'une pilule d'état. Le `fixedSize` de `controlsGroup` garantit
    /// qu'elle ne s'écrase pas pour autant à 1 280 px : c'est le titre qui cède.
    static let reportLabelSize: CGFloat = 12
    /// Les deux pilules-menus (`Architecture ⌄`, `Auto ⌄`) : des commandes,
    /// donc la même mesure que le bouton `Rapport` — c'est ce que montrent
    /// `Projet ⌄` et `Global ⌄` sur la capture.
    static let menuPillLabelSize: CGFloat = 12

    /// Le chevron du segment projet (capture `3b-fiche-projet.png`). Il dit que
    /// le segment ouvre quelque chose : sans lui, un cadre `accent/action`
    /// ressemble à une sélection, pas à un bouton.
    static let projectSegmentChevron = "⌄"
    static let projectSegmentHelp = "Ouvrir la fiche du projet"

    /// Fond de la barre. Les deux types 1:1 sont teintés
    /// `accent/oneonone bg` (`#f4f1f6`) : c'est le signal permanent que la
    /// séance est privée (spec §1.2, §3.2).
    static func tint(for kind: MeetingKind) -> Color {
        switch kind {
        case .oneToOne, .manager: return One2OneToken.oneOnOneBg
        case .global, .project, .work, .note, .workshop: return One2OneToken.bgApp
        }
    }

    /// Badge de type affiché dans le fil d'Ariane. `nil` pour les types qui
    /// n'en portent pas : seul le 1:1 en a un sur les captures, et un badge
    /// « Projet » redondant avec le segment projet ne dirait rien de plus.
    static func typeBadge(for kind: MeetingKind) -> String? {
        switch kind {
        case .oneToOne, .manager: return "1:1"
        case .global, .project, .work, .note, .workshop: return nil
        }
    }

    /// La pilule de rôle, **obligatoire** pour un 1:1 subi (D4, spec §6.1).
    ///
    /// `nil` ailleurs — y compris pour le 1:1 mené : la spec dit « badge de
    /// rôle : implicite » côté manager. Le rôle mené est déjà lisible au fait
    /// qu'aucune pilule ne contredit le badge `1:1`, et une pilule « Je suis le
    /// manager » sur tous les entretiens deviendrait du décor qu'on ne lit
    /// plus — ce qui ferait rater la seule qui compte.
    static func collaboratorPillLabel(for kind: MeetingKind) -> String? {
        kind == .manager ? "Je suis le collaborateur" : nil
    }

    // MARK: - Écran de séance 1:1 (lot 11, capture 2a)

    /// Le segment `Mon équipe` du fil d'Ariane d'un 1:1 **mené**.
    ///
    /// `nil` pour un 1:1 subi : la personne d'en face n'est pas dans mon
    /// équipe, c'est moi qui suis dans la sienne. Son fil d'Ariane appartient à
    /// la capture 5a (lot 13).
    static func teamSegmentLabel(for kind: MeetingKind) -> String? {
        kind == .oneToOne ? "Mon équipe" : nil
    }

    // MARK: - Écran de séance du 1:1 subi (lot 13, capture 5a)

    /// Le segment `Mes 1:1` du fil d'Ariane d'un 1:1 **subi**.
    ///
    /// `nil` pour un 1:1 mené : celui-là se range sous `Mon équipe`. Les deux
    /// segments s'excluent, et c'est le propos — le fil d'Ariane dit de quel
    /// côté de la table on est avant même qu'on lise la pilule de rôle.
    static func myOneOnOnesSegmentLabel(for kind: MeetingKind) -> String? {
        kind == .manager ? "Mes 1:1" : nil
    }

    /// `Avec Yann PENVEN — 4 septembre` (capture 5a).
    ///
    /// Dérivé de la personne et de la date, jamais stocké — même règle que
    /// `oneOnOneSessionHeading`, dont c'est le pendant côté subi. Sert de
    /// **placeholder** du titre : renommer son propre entretien doit rester
    /// possible.
    ///
    /// Sans nom, la phrase reste une phrase (`Mon 1:1 du 4 septembre`) : un
    /// « Avec  — 4 septembre » afficherait un tiret nu.
    static func collaboratorSessionHeading(person: String, date: Date) -> String {
        let jour = OneOnOneDateFormat.dayFullMonth(date)
        let nom = person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nom.isEmpty else { return "Mon 1:1 du \(jour)" }
        return "Avec \(nom) — \(jour)"
    }

    /// La pilule `● Privé — vous deux` (spec §3.2, niveau `shared` : « visible
    /// par les deux personnes du fil »).
    ///
    /// `nil` côté collaborateur : la pilule de rôle y est **obligatoire** (D4),
    /// et deux pilules violettes côte à côte diraient deux fois la même chose.
    static func privacyPillLabel(for kind: MeetingKind) -> String? {
        kind == .oneToOne ? "● Privé — vous deux" : nil
    }

    /// `Rapport 1:1` en entretien, `Rapport` partout ailleurs : le rapport d'un
    /// 1:1 suit un gabarit différent (`d2_oneToOne`), et son bouton doit le
    /// dire avant qu'on l'ait pressé.
    static func reportBaseLabel(for kind: MeetingKind) -> String {
        switch kind {
        case .oneToOne, .manager: return "Rapport 1:1"
        case .global, .project, .work, .note, .workshop: return "Rapport"
        }
    }

    /// `Laurent NOMINÉ — entretien du 4 septembre` (capture 2a).
    ///
    /// Dérivé de la personne et de la date, jamais stocké : c'est l'identité
    /// d'une séance de fil. Sert de **placeholder** du titre, pas de
    /// remplacement — renommer un entretien doit rester possible, et la barre
    /// est le seul endroit de l'application qui le permet.
    static func oneOnOneSessionHeading(person: String, date: Date) -> String {
        let jour = OneOnOneDateFormat.dayFullMonth(date)
        let nom = person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nom.isEmpty else { return "Entretien du \(jour)" }
        return "\(nom) — entretien du \(jour)"
    }

    /// Le placeholder du champ de titre : l'en-tête d'entretien pour un 1:1
    /// mené, le placeholder générique ailleurs.
    static func titlePlaceholder(for meeting: Meeting) -> String {
        let personne = meeting.participants.first?.name ?? ""
        switch meeting.kind {
        case .oneToOne:
            return oneOnOneSessionHeading(person: personne, date: meeting.date)
        case .manager:
            // Lot 13 : côté subi, la personne d'en face est mon manager, et
            // l'en-tête de la capture 5a le dit ainsi (`Avec <Manager> — <jour>`).
            return collaboratorSessionHeading(person: personne, date: meeting.date)
        case .global, .project, .work, .note, .workshop:
            return "Titre de la réunion…"
        }
    }

    /// Lecture d'un timecode tapé à la main dans la pilule audio (spec §2.1 :
    /// « Clic sur le temps = saisie directe d'un timecode »).
    ///
    /// Refuse plutôt que de deviner : une saisie invalide rend `nil` et laisse
    /// la tête de lecture où elle est. Deviner déplacerait la lecture au
    /// hasard, ce qui est pire que ne rien faire.
    enum TimecodeInput {
        static func parse(_ texte: String) -> Double? {
            let propre = texte.trimmingCharacters(in: .whitespaces)
            guard !propre.isEmpty else { return nil }
            let parts = propre.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count <= 3 else { return nil }

            var valeurs: [Int] = []
            for part in parts {
                guard !part.isEmpty,
                      part.allSatisfy(\.isNumber),
                      let n = Int(part) else { return nil }
                valeurs.append(n)
            }
            switch valeurs.count {
            case 1:
                // Un nombre seul : des secondes.
                return Double(valeurs[0])
            case 2:
                guard valeurs[1] < 60 else { return nil }
                return Double(valeurs[0] * 60 + valeurs[1])
            case 3:
                guard valeurs[1] < 60, valeurs[2] < 60 else { return nil }
                return Double(valeurs[0] * 3600 + valeurs[1] * 60 + valeurs[2])
            default:
                return nil
            }
        }
    }

    // MARK: - Entrées

    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var modelContext

    /// Les réglages, pour le drapeau `workshopEnabled`. Interrogés ici plutôt
    /// que passés en paramètre : la barre est déjà appelée avec dix-huit
    /// arguments, et un dix-neuvième traversant `MeetingView` est exactement ce
    /// que le programme §8 refuse.
    @Query private var reglages: [AppSettings]
    @Query private var allTemplates: [ReportTemplate]
    @ObservedObject var recorder: AudioRecorderService
    @ObservedObject var stt: TranscriptionService
    @ObservedObject var captureService: ScreenCaptureService
    /// Tête de lecture de la réunion : la pilule affiche `playhead.formatted`
    /// et non le temps du lecteur, pour que la barre, la frise et les notes
    /// parlent du même `t` (spec §1.1).
    let playhead: MeetingPlayhead
    /// Vrai si l'enregistrement en cours appartient à la réunion affichée.
    /// ⚠️ Pour l'affichage (pastille rouge, chrono), ne pas utiliser
    /// `recorder.isRecording` : le service est un singleton et la pastille
    /// apparaîtrait dans toutes les fenêtres réunion ouvertes.
    let isRecordingThisMeeting: Bool
    let isGeneratingReport: Bool
    let reportElapsedSeconds: Int
    let reportStatus: String
    let reportWaitWarning: String?

    /// Source d'actions partagée avec les menus natifs (cf. MeetingMenuActions).
    let actions: MeetingMenuActions

    /// Nombre de captures déjà prises pour cette réunion.
    let capturedSlidesCount: Int

    /// L'état du tiroir Ressources, pour la pilule `● Partage actif · n voient`
    /// (lot 6, spec §4.2). Optionnel : les aperçus et les écrans qui montent
    /// la barre sans modèle d'écran n'ont pas de partage à annoncer.
    var resources: ResourcesState?

    /// Le pilotage de la capture (lot 7, spec §5.1) : la pilule y ancre le
    /// sélecteur de source. Optionnel pour la même raison que `resources` —
    /// une barre montée sans modèle d'écran n'a pas de session à piloter, et
    /// la pilule retombe alors sur son bouton neutre.
    var capture: CaptureSessionCoordinator?

    /// Bascule lecture/pause de l'audio enregistré.
    let onTogglePlay: () -> Void
    /// Ouvre la configuration de la source de capture d'écran.
    let onShowCaptureSetup: () -> Void
    /// Ouvre la galerie des captures.
    let onShowSlides: () -> Void
    /// Ouvre la fiche du projet. Au lot 9 elle s'ouvrira en panneau latéral de
    /// 430 px ; d'ici là, l'appelant pousse `ProjectDetailView`.
    let onOpenProject: () -> Void
    /// Crée une réunion — le `+` de l'ancienne deuxième ligne, devenu une
    /// entrée du menu de type (spec §2.1).
    let onCreateMeeting: () -> Void

    /// Retour vers l'écran d'où l'on vient, quand la réunion a été **poussée**
    /// dans une pile (depuis la fiche d'un collaborateur). `nil` quand elle est
    /// ouverte seule : il n'y a alors rien derrière, et un chevron mentirait.
    var onBack: (() -> Void)?

    /// Affiche le popover de choix du type de rapport avant génération.
    @State private var showReportTypePicker = false
    /// Les deux menus de la barre, en popovers stylés et non en `NSMenu`
    /// (défaut n° 3 des retours d'usage du 2026-09-08).
    @State private var showTypePicker = false
    @State private var showTemplatePicker = false
    /// Saisie de timecode en cours dans la pilule audio ; `nil` = affichage.
    @State private var timecodeDraft: String?
    /// L'aperçu `Mon récap` d'un 1:1 subi est ouvert (lot 13).
    @State private var showsMyRecap = false
    /// La feuille « Raccourcis » est ouverte (lot 19c, spec §1.4).
    @State private var showsShortcuts = false

    var body: some View {
        HStack(spacing: 10) {
            if let onBack {
                panelButton(onBack)
            }
            breadcrumb
            badgeAtelier
            titleField
            Spacer(minLength: 8)
            controlsGroup
        }
        .padding(.horizontal, Self.paddingHorizontal)
        .frame(height: Self.height)
        .background(Self.tint(for: meeting.kind))
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.cardBorder).frame(height: 1)
        }
    }

    /// Les contrôles de droite, **à leur largeur intrinsèque**.
    ///
    /// Deuxième moitié de la règle d'arbitrage de la barre (cf. `titleField`) :
    /// le titre cède, les contrôles gardent leur taille. Les recettes des
    /// lots 16 et 1–4 ont relevé les deux faces du **même** défaut — le badge
    /// `ATELIER` tronqué à 1 616 px, et à 1 280 px `Rapport ✓ 6:20` réduit à
    /// « R », `Capture` à « C », `● Partage actif · 5 voient` à un carré bleu.
    /// La priorité négative du titre ne suffisait pas seule : elle décide de
    /// **qui** cède, ce `fixedSize` dit que ce groupe ne cède pas du tout,
    /// popovers et menus compris.
    private var controlsGroup: some View {
        HStack(spacing: 10) {
            // Une note n'a ni audio, ni transcription, ni rapport : ses
            // contrôles disparaissent entièrement (même règle que
            // `MeetingSpaceRouting`, qui lui retire l'espace Rapport).
            if meeting.kind != .note {
                if let confidentialite = Self.privacyPillLabel(for: meeting.kind) {
                    Pill(confidentialite, ton: .oneOnOne, bordee: true)
                        .help("Cet entretien n'est visible que de vous deux — les lignes privées ne sortent pas même de là")
                }
                audioPill
                // Lot 13 : côté subi, la barre porte `Mon récap` — l'aperçu de
                // ce qui partira vers mon manager. C'est la contrepartie du
                // défaut `private` : pouvoir vérifier avant d'envoyer.
                if meeting.kind == .manager { myRecapButton }
                sharePill
                captureButton
                    .popover(isPresented: capturePopoverBinding,
                             attachmentAnchor: .rect(.bounds),
                             arrowEdge: .bottom) {
                        if let capture {
                            CaptureSourcePopover(coordinator: capture, service: captureService)
                        }
                    }
                // Spec §2.1 : les pilules d'état se suivent — partage (lot 6),
                // capture (lot 7), puis `Local · hors ligne` de l'atelier
                // (lot 16). La placer avant la pilule audio, comme le lot 16
                // l'avait écrite seul, la sortait de ce groupe.
                piluleLocale
                typeMenu
                templatePickerButton
                reportButton
            } else {
                typeMenu
            }
            moreMenu
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Atelier (lot 16)

    /// Vrai quand le type Atelier est armé dans les réglages.
    private var atelierArme: Bool {
        reglages.canonicalSettings?.workshopEnabled ?? false
    }

    /// Les types proposés. L'Atelier n'apparaît que si le drapeau est armé —
    /// mais une réunion déjà de ce type garde son entrée, sinon le sélecteur
    /// afficherait un type absent de sa propre liste.
    private var typesOfferts: [MeetingKind] {
        MeetingKind.allCases.filter { $0 != .workshop || atelierArme || meeting.kind == .workshop }
    }

    /// Le badge `ATELIER` en `accent/workshop` plein (capture 6a).
    @ViewBuilder
    private var badgeAtelier: some View {
        if meeting.kind == .workshop {
            Text("ATELIER")
                .font(.plexMono(9.5, .semibold))
                .tracking(9.5 * 0.07)
                .foregroundStyle(One2OneToken.onFilledButton)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.workshop))
                // Largeur intrinsèque garantie : à 1 616 px, la barre porte
                // déjà fil d'Ariane, titre, pilules audio et capture, menus de
                // type et de modèle et le bouton Rapport, et le badge
                // apparaissait **tronqué** (recette du lot 16, 2026-09-07).
                // Même règle que `controlsGroup` — cf. `titleField`.
                .fixedSize()
                .accessibilityLabel("Type Atelier")
        }
    }

    /// `● Local · hors ligne` — **toujours vrai** pour l'atelier : les planches
    /// vivent dans le dossier de la réunion et le moteur est embarqué (spec
    /// §7.4, ADR du 2026-09-07). La pilule est donc une affirmation, pas un
    /// état à surveiller.
    @ViewBuilder
    private var piluleLocale: some View {
        if meeting.kind == .workshop {
            HStack(spacing: 5) {
                Circle()
                    .fill(One2OneToken.ok)
                    .frame(width: 6, height: 6)
                Text("Local · hors ligne")
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(One2OneToken.ink2)
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule(style: .continuous).fill(One2OneToken.surface))
            .overlay(Capsule(style: .continuous)
                .strokeBorder(One2OneToken.strongBorder, lineWidth: 1))
            .help("Les planches, la scène et les vignettes restent dans le dossier de la réunion")
        }
    }

    // MARK: - Mon récap (lot 13)

    /// `Mon récap` — l'aperçu du récap filtré `.manager`.
    ///
    /// Autonome à dessein : la barre a déjà `meeting` et le contexte, donc elle
    /// n'a besoin d'aucun paramètre de plus. Un `onShowMyRecap` traversant
    /// obligerait `MeetingView` à porter une closure supplémentaire, ce que le
    /// programme §8 refuse — et `MeetingView` n'est pas touché par ce lot.
    private var myRecapButton: some View {
        Button {
            showsMyRecap = true
        } label: {
            Text("Mon récap")
                .font(.plexSans(11, .medium))
                .foregroundStyle(One2OneToken.oneOnOneInk)
                .padding(.horizontal, 9)
                .frame(height: 24)
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
        .help("Voir ce qui partira vers votre manager — vos lignes privées n'y sont pas")
        .sheet(isPresented: $showsMyRecap) {
            MyRecapPreview(meeting: meeting)
        }
    }

    // MARK: - Fil d'Ariane

    /// Le retour vit dans le fil d'Ariane : c'est le seul endroit de l'écran
    /// qui dit déjà « où je suis ». `⌘[` fait la même chose, comme partout sur
    /// macOS.
    private func panelButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(One2OneToken.ink3)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("[", modifiers: .command)
        .help("Retour (⌘[)")
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Text("One2One")
                .font(.plexSans(11))
                .foregroundStyle(One2OneToken.ink4)
            chevron
            if let project = meeting.project {
                // Segment projet bordé `accent/action` : la seule partie
                // cliquable du fil, et la spec veut qu'on le voie. Depuis le
                // lot 9 il ouvre la fiche projet en panneau de 430 px
                // (spec §4.3) et non plus la feuille « Détails ».
                Button(action: onOpenProject) {
                    HStack(spacing: 4) {
                        Text(project.name)
                            .font(.plexSans(11, .medium))
                            .lineLimit(1)
                        Text(Self.projectSegmentChevron)
                            .font(.plexSans(11, .medium))
                    }
                        .foregroundStyle(One2OneToken.actionInk)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(One2OneToken.actionBg2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(One2OneToken.action.opacity(0.5), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Self.projectSegmentHelp)
                chevron
            }
            // Lot 11 : un 1:1 mené se range sous « Mon équipe » — le segment
            // que la capture 2a montre à la place du projet. Non cliquable :
            // l'annuaire n'est pas une destination de cet écran.
            if let equipe = Self.teamSegmentLabel(for: meeting.kind) {
                Text(equipe)
                    .font(.plexSans(11))
                    .foregroundStyle(One2OneToken.ink4)
                chevron
            }
            // Lot 13 : un 1:1 subi se range sous « Mes 1:1 » — le segment que
            // la capture 5a montre à la place de `Mon équipe`. Non cliquable,
            // pour la même raison.
            if let miens = Self.myOneOnOnesSegmentLabel(for: meeting.kind) {
                Text(miens)
                    .font(.plexSans(11))
                    .foregroundStyle(One2OneToken.ink4)
                chevron
            }
            // Signalétique 1:1 (lot 10) : le badge de type, puis la pilule de
            // rôle quand l'entretien est subi.
            if let badge = Self.typeBadge(for: meeting.kind) {
                Pill(badge, ton: .oneOnOne)
                    .help("Entretien individuel — notes privées par ligne")
            }
            if let role = Self.collaboratorPillLabel(for: meeting.kind) {
                Pill(role, ton: .oneOnOne, bordee: true)
                    .help("Vous ne menez pas cet entretien : vos notes sont privées par défaut")
            }
            audioStatusBadge
        }
        .fixedSize()
    }

    private var chevron: some View {
        Text("›")
            .font(.plexSans(11))
            .foregroundStyle(One2OneToken.inkMuted)
    }

    /// Titre de la réunion : `flex:1; min-width:0` de la spec, donc
    /// `maxWidth: .infinity` + une ligne. Éditable en place.
    ///
    /// **Première moitié de la règle d'arbitrage de largeur de la barre**, et
    /// la seule qui vaille : quand la place manque, c'est le titre qui se
    /// rogne. Lui seul porte une ellipse ; un badge de six lettres, une pilule
    /// ou un libellé de bouton n'en ont pas, et se réduisent à leur première
    /// lettre. Avec `layoutPriority(1)`, le titre était servi le premier et
    /// absorbait toute la largeur restante.
    ///
    /// Les deux moitiés sont nécessaires et vont dans le même sens : la
    /// priorité négative désigne le perdant de l'arbitrage, le `fixedSize` de
    /// `controlsGroup` (et ceux de `breadcrumb` et du badge `ATELIER`) met les
    /// gagnants hors d'atteinte. Ne garder que l'une des deux ramène l'un des
    /// deux défauts de recette (lot 16 à 1 616 px, vague 1–4 à 1 280 px).
    private var titleField: some View {
        // Écart (c) n° 3 : un titre, pas un champ. Le style `plain` retire le
        // bezel permanent et la fonte est passée en `NSFont` — un
        // `NSViewRepresentable` ignore le `.font()` de l'environnement, et le
        // `.font(.plexSans(13, .semibold))` qui vivait ici n'avait aucun effet.
        // L'édition en place, elle, ne change pas.
        EditableTextField(placeholder: Self.titlePlaceholder(for: meeting),
                          text: $meeting.title,
                          style: .plain,
                          font: .plexSans(13, .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
    }

    /// Badge d'état de disponibilité de l'audio.
    /// - `.original` : audio intact → aucun badge affiché.
    /// - `.compressed` : audio recompressé (AAC) → badge informatif.
    /// - `.deleted` : audio purgé par la politique de rétention.
    @ViewBuilder
    private var audioStatusBadge: some View {
        switch meeting.audioAvailability {
        case .original:
            EmptyView()
        case .compressed:
            Pill("Audio compressé", ton: .neutre)
                .help("Audio compressé (AAC 32 kbps mono) — qualité STT dégradée si re-transcription")
        case .deleted:
            Pill("Audio archivé", ton: .neutre)
                .help("Audio supprimé après 30 jours (politique de rétention). Rapport et transcription conservés.")
        }
    }

    // MARK: - Pilule audio

    /// La pilule audio de la spec §2.1 : fond `ink/1`, rayon 16,
    /// `▶ mm:ss / mm:ss` puis marqueur (`⌘M`) et édition (`✂`).
    ///
    /// Trois états, un seul contenant : enregistrement en cours (chrono + pause
    /// + stop), audio disponible (lecture + position + marqueur + ciseaux),
    /// rien encore (bouton d'enregistrement).
    @ViewBuilder
    private var audioPill: some View {
        if isRecordingThisMeeting {
            pillShell { recordingContent }
        } else if actions.hasWav {
            pillShell { playbackContent }
        } else {
            // Le plein écran ne dépend pas de l'audio : on passe en mode
            // séance pour prendre des notes, l'enregistrement est un choix
            // séparé. Le bouton accompagne donc aussi la pilule d'attente.
            idlePill
            if SessionFullscreenPresenter.shared.peutEntrer(meeting.stableID) {
                pillShell { fullscreenButton }
            }
        }
    }

    private func pillShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 7) { content() }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusAudio)
                    .fill(One2OneToken.ink1)
            )
    }

    @ViewBuilder
    private var recordingContent: some View {
        Circle().fill(One2OneToken.report).frame(width: 7, height: 7)
        Text(MeetingPlayhead.mmss(recorder.elapsedSeconds))
            .font(.plexMono(10))
            .foregroundStyle(One2OneToken.onFilledButton)
        pillIcon(recorder.isPaused ? "play.fill" : "pause.fill",
                 aide: recorder.isPaused ? "Reprendre" : "Mettre en pause",
                 action: actions.togglePause)
        pillIcon("stop.fill", aide: "Arrêter et transcrire", action: actions.stopRecording)
        markerButton
        fullscreenButton
    }

    @ViewBuilder
    private var playbackContent: some View {
        pillIcon(playhead.isPlaying ? "pause.fill" : "play.fill",
                 aide: meeting.hasPlayableAudio ? "Lecture" : "Audio supprimé après politique de rétention",
                 action: onTogglePlay)
            .disabled(!meeting.hasPlayableAudio)
            .opacity(meeting.hasPlayableAudio ? 1 : 0.4)
        timecodeView
        markerButton
        pillIcon("scissors", aide: "Éditer l'audio — couper le début/la fin ou diviser",
                 action: actions.editAudio)
            .disabled(!meeting.hasPlayableAudio || stt.isTranscribing || isGeneratingReport)
            .opacity(meeting.hasPlayableAudio ? 1 : 0.4)
        fullscreenButton
    }

    /// Position courante et durée. Un clic ouvre la saisie directe : c'est le
    /// seul chemin par lequel un timecode tapé entre dans le modèle.
    @ViewBuilder
    private var timecodeView: some View {
        if let brouillon = timecodeDraft {
            TextField("mm:ss", text: Binding(
                get: { brouillon },
                set: { timecodeDraft = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.plexMono(10))
            .foregroundStyle(One2OneToken.onFilledButton)
            .frame(width: 52)
            .onSubmit {
                if let t = TimecodeInput.parse(brouillon) { playhead.seek(to: t) }
                timecodeDraft = nil
            }
            .onExitCommand { timecodeDraft = nil }
        } else {
            Button {
                timecodeDraft = playhead.formatted
            } label: {
                Text("\(playhead.formatted) / \(MeetingPlayhead.mmss(displayDuration))")
                    .font(.plexMono(10))
                    .foregroundStyle(One2OneToken.onFilledButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cliquer pour saisir un timecode")
        }
    }

    /// Durée affichée : celle de la tête de lecture, sinon celle enregistrée
    /// sur la réunion (un audio non encore chargé a une durée de 0).
    private var displayDuration: Double {
        max(playhead.duration, Double(meeting.durationSeconds))
    }

    /// L'entrée du mode séance plein écran (lot 4, spec §2.6 : « bouton dans la
    /// pilule audio ou `⌃⌘F` »).
    ///
    /// Affichée seulement quand un écran est en mesure de présenter — le mode
    /// En séance de l'espace Réunion (`SessionFullscreenPresenter.hote`). Un
    /// bouton grisé dans une pilule de 24 px de haut est un bouton qu'on
    /// n'identifie pas ; ici il apparaît quand il sert.
    @ViewBuilder
    private var fullscreenButton: some View {
        if SessionFullscreenPresenter.shared.peutEntrer(meeting.stableID) {
            pillIcon("arrow.up.left.and.arrow.down.right",
                     aide: "Mode séance plein écran (⌃⌘F)") {
                SessionFullscreenPresenter.shared.demanderBascule()
            }
        }
    }

    private var markerButton: some View {
        pillIcon("mappin.and.ellipse", aide: "Poser un marqueur (⌘M)") {
            playhead.addMarker(at: playhead.t, kind: .note)
        }
    }

    private func pillIcon(_ symbole: String,
                          aide: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(One2OneToken.onFilledButton)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(aide)
    }

    private var idlePill: some View {
        // `recorder.isRecording` (global) ici et non `isRecordingThisMeeting` :
        // une autre réunion enregistre déjà, le service ne peut pas en démarrer
        // un second — le bouton est grisé plutôt qu'échouer au clic.
        let autreEnCours = recorder.isRecording && !isRecordingThisMeeting
        return Button(action: actions.startRecording) {
            HStack(spacing: 5) {
                Circle().fill(One2OneToken.onFilledButton).frame(width: 6, height: 6)
                Text("Enregistrer").font(.plexSans(10.5, .medium))
            }
            .foregroundStyle(One2OneToken.onFilledButton)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusAudio)
                    .fill(One2OneToken.report)
            )
        }
        .buttonStyle(.plain)
        .disabled(stt.isTranscribing || isGeneratingReport || autreEnCours)
        .opacity(autreEnCours ? 0.4 : 1)
        .help(autreEnCours
              ? "Un enregistrement est déjà en cours pour une autre réunion"
              : "Démarrer l'enregistrement")
    }

    // MARK: - Partage à l'écran (lot 6)

    /// `● Partage actif · 5 voient`, **pleine** `accent/action` (spec §4.2,
    /// capture `3a-tiroir-ressources.png`).
    ///
    /// Critère d'acceptation n° 2 du chantier 3 : l'état de partage se lit
    /// d'ici, sans ouvrir le tiroir. Le libellé vient de
    /// `MeetingSharingState`, pur et testé — la barre ne compte pas les
    /// participants elle-même.
    ///
    /// **Sans partage, la pilule disparaît** : pas d'état grisé. Une pilule
    /// éteinte occuperait la place et se lirait comme un contrôle désactivé,
    /// alors qu'il n'y a rien à contrôler.
    @ViewBuilder
    private var sharePill: some View {
        if let libelle = MeetingSharingState.pillLabel(
            isPresenting: resources?.isPresenting ?? false,
            presentCount: MeetingSharingState.presentCount(for: meeting)) {
            Button { resources?.open() } label: {
                Text(libelle)
                    .font(.plexSans(10.5, .semibold))
                    .foregroundStyle(One2OneToken.onFilledButton)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    // Spec §4.2 : « pilule `accent/action` pleine ». Une
                    // pilule prend le rayon 11 de la table §1.2, pas celui
                    // d'un bouton (6) — la recette visuelle de la vague 1–4 a
                    // relevé le carré à la place de la pilule.
                    .background(
                        Capsule(style: .continuous).fill(One2OneToken.action)
                    )
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Un document est à l'écran des participants — ouvrir le tiroir Ressources")
        }
    }

    // MARK: - Capture

    /// État de capture dans la barre du haut (spec §5.2, capture 4a) :
    /// pilule `● Capture · Teams 3 ⌄` en `accent/ok` bordée, `Source perdue` en
    /// `accent/warn` avec un lien de reconfiguration, bouton neutre `Capture`
    /// sinon. Le chevron rouvre le sélecteur de source.
    ///
    /// Tout se lit **sans ouvrir de menu** : l'état, la source et le compteur
    /// (critère d'acceptation n° 1 du chantier 4). La décision est
    /// `CaptureState.pill`, une fonction pure testée à part.
    @ViewBuilder
    private var captureButton: some View {
        switch capturePill {
        case .idle:
            Button(action: onShowCaptureSetup) {
                Text(capturedSlidesCount > 0 ? "Capture \(capturedSlidesCount)" : "Capture")
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(One2OneToken.ink2)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
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
            .help("Choisir la source à capturer (⌘⇧S)")

        case .armed(_, _, let automatique):
            capturePillView(texte: capturePill.label,
                            ton: .ok,
                            point: automatique ? One2OneToken.ok : One2OneToken.ink4,
                            aide: automatique
                                ? "Capture armée — une capture à chaque changement de partage. Clic pour changer de source."
                                : "Capture prête — ⌘⇧S capture ce qui est à l'écran. Clic pour changer de source.")

        case .lost:
            capturePillView(texte: capturePill.label,
                            ton: .warn,
                            point: One2OneToken.warn,
                            aide: captureStatusHelp + " — clic pour reconfigurer la source.")
        }
    }

    /// Ouverture du sélecteur, portée par `CaptureState` : le raccourci `⌘⇧S`
    /// et la bande de captures l'ouvrent aussi, et un `@State` local ici les
    /// laisserait sans porte.
    private var capturePopoverBinding: Binding<Bool> {
        Binding(get: { capture?.screen.capture.showPopover ?? false },
                set: { capture?.screen.capture.showPopover = $0 })
    }

    /// L'état de la pilule, dérivé du service : jamais stocké, sinon il
    /// annoncerait une capture armée sur une session close.
    private var capturePill: CapturePillState {
        CaptureState.pill(sessionOpen: captureService.hasOpenSession,
                          sourceLost: captureService.isSourceLost,
                          source: captureService.configuration?.source,
                          count: capturedSlidesCount,
                          automatic: captureService.configuration?.detectsAutomatically ?? false)
    }

    /// La pilule elle-même : point, libellé, chevron. Le chevron **fait** ce
    /// qu'il annonce (rouvrir le sélecteur) ; le clic droit garde le pilotage
    /// de la session.
    private func capturePillView(texte: String,
                                 ton: ChipTon,
                                 point: Color,
                                 aide: String) -> some View {
        Button(action: onShowCaptureSetup) {
            HStack(spacing: 5) {
                Circle().fill(point).frame(width: 6, height: 6)
                Text(texte)
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(ton.encre)
                Text("⌄")
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(ton.encre.opacity(0.7))
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusPill).fill(ton.fond)
            )
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusPill)
                    .strokeBorder(ton.encre.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(aide)
        .contextMenu {
            Button("Choisir la source…") { onShowCaptureSetup() }
            Button("Voir les captures") { onShowSlides() }
            Divider()
            if captureService.isCapturing {
                Button("Arrêter la capture") { captureService.stop() }
            } else {
                Button("Reprendre la capture") { captureService.resume() }
            }
            Button("Terminer le lot") { Task { await captureService.finish() } }
        }
    }

    private var captureStatusHelp: String {
        if case .paused(let reason) = captureService.state { return reason }
        return "Voir les captures"
    }

    // MARK: - Menu de type

    /// Les sept types de la spec §2.1, plus la création de réunion : le `+` de
    /// l'ancienne deuxième ligne est devenu une entrée de ce menu.
    ///
    /// **Un popover stylé, pas un `Menu`** (défaut n° 3 des retours d'usage du
    /// 2026-09-08) : les lignes d'un `NSMenu` sont dessinées par AppKit, en
    /// fonte système, et aucun `.font(.plexSans(…))` ne les atteint —
    /// cf. `StyledMenuPopover`.
    private var typeMenu: some View {
        Button { showTypePicker = true } label: {
            chromeMenuLabel(meeting.kind.label)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Type de réunion — recharge la disposition de l'espace Réunion, jamais le contenu")
        .popover(isPresented: $showTypePicker, arrowEdge: .bottom) {
            StyledMenuPopover(titre: "Type de réunion",
                              items: typePickerItems,
                              fermer: { showTypePicker = false })
        }
    }

    /// Les lignes du menu de type : les types offerts, puis `Nouvelle réunion…`
    /// détachée par un filet — c'est une commande, pas un type.
    private var typePickerItems: [StyledMenuPopover.Item] {
        var items = typesOfferts.map { k in
            StyledMenuPopover.Item(id: "kind-\(k.rawValue)",
                                   libelle: k.label,
                                   symbole: k.sfSymbol,
                                   selectionnee: meeting.kind == k) {
                meeting.kind = k
                try? modelContext.save()
            }
        }
        items.append(StyledMenuPopover.Item(id: "kind-new",
                                            libelle: "Nouvelle réunion…",
                                            symbole: "plus",
                                            separateurAvant: true,
                                            action: onCreateMeeting))
        return items
    }

    /// Libellé commun des deux menus de la barre : `<texte> ⌄` dans un cadre
    /// `border/strong`, comme les boutons `Projet ⌄` / `Global ⌄` de la capture.
    private func chromeMenuLabel(_ texte: String) -> some View {
        HStack(spacing: 4) {
            Text(texte)
                .font(.plexSans(Self.menuPillLabelSize, .medium))
                .foregroundStyle(One2OneToken.ink2)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(One2OneToken.ink4)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
        )
    }

    // MARK: - Bouton rapport

    @ViewBuilder
    private var reportButton: some View {
        // Le rapport a besoin d'une transcription OU d'un audio à transcrire.
        // Sans transcript mais avec audio, le clic enchaîne transcription + rapport.
        let needsTranscription = meeting.rawTranscript.isEmpty
        let hasSource = !needsTranscription || meeting.hasPlayableAudio
        let disabled = !hasSource || recorder.isRecording || stt.isTranscribing || isGeneratingReport
        Button(action: { showReportTypePicker = true }) {
            HStack(spacing: 5) {
                if isGeneratingReport {
                    ProgressView().controlSize(.small).tint(One2OneToken.onFilledButton)
                    Text("\(reportStatus) · \(formatElapsed(reportElapsedSeconds))")
                        .font(.plexMono(10))
                        .lineLimit(1)
                    if reportWaitWarning != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                    }
                } else if stt.isTranscribing {
                    ProgressView().controlSize(.small).tint(One2OneToken.onFilledButton)
                    Text("Transcription…").font(.plexSans(Self.reportLabelSize, .medium))
                } else {
                    Text(reportLabel).font(.plexSans(Self.reportLabelSize, .medium))
                }
            }
            // Indisponible, le bouton ne s'éclaircit plus : il **change de
            // registre**. Un libellé blanc sur `report` à 45 % d'opacité
            // tombait à moins de 2:1 — « Transcrire + Rapport 1:1 » était
            // illisible sur les captures 2a, 2b, 5a, 5b, 6a et 6b de la
            // recette finale. Le couple `report/bg` + `report/ink` de §1.2
            // atteint 6:1 et dit la même chose : ce bouton n'est pas
            // l'action primaire de l'instant.
            .foregroundStyle(disabled ? One2OneToken.reportInk : One2OneToken.onFilledButton)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                    .fill(disabled ? One2OneToken.reportBg : One2OneToken.report)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(reportWaitWarning ?? reportStatus)
        .popover(isPresented: $showReportTypePicker, arrowEdge: .bottom) {
            reportTypePicker
        }
    }

    /// `Rapport ✓ (m:ss)` : la coche dit « généré », la durée est le temps de
    /// génération (spec §2.1).
    private var reportLabel: String {
        // `Rapport 1:1` en entretien (lot 11) : le gabarit et l'audience du
        // rapport diffèrent, et le bouton le dit avant d'être pressé.
        let base = Self.reportBaseLabel(for: meeting.kind)
        if meeting.rawTranscript.isEmpty { return "Transcrire + \(base)" }
        if meeting.summary.isEmpty { return base }
        if meeting.reportGenerationDurationSeconds > 0 {
            return "\(base) ✓ \(formatElapsed(Int(meeting.reportGenerationDurationSeconds.rounded())))"
        }
        return "\(base) ✓"
    }

    /// Popover de choix du type de rapport, affiché au clic sur « Rapport ».
    /// Propose « Auto » puis les templates compatibles ; la sélection fixe
    /// `meeting.reportTemplate` puis lance la génération.
    private var reportTypePicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Type de rapport")
                .sectionLabel()
                .padding(.horizontal, 12)
                .padding(.top, 10).padding(.bottom, 6)
            reportTypeRow(name: "Auto (selon type)", template: nil)
            if !compatibleTemplates.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(compatibleTemplates) { t in
                    reportTypeRow(name: t.name, template: t)
                }
            }
        }
        .frame(minWidth: 240)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func reportTypeRow(name: String, template: ReportTemplate?) -> some View {
        let isSelected = meeting.reportTemplate?.persistentModelID == template?.persistentModelID
        Button {
            meeting.reportTemplate = template
            try? modelContext.save()
            showReportTypePicker = false
            actions.generateReport()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: template == nil ? "wand.and.stars" : "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(One2OneToken.ink4)
                Text(name).font(.plexSans(12)).lineLimit(1)
                Spacer(minLength: 12)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(One2OneToken.action)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func formatElapsed(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Menu de template

    /// Même remède que `typeMenu` : un popover stylé. C'est ce menu que la
    /// capture du retour d'usage montrait en fonte système, ouvert sur
    /// `Auto (selon type) / Global / 1:1 Collaborateur…`.
    private var templatePickerButton: some View {
        Button { showTemplatePicker = true } label: {
            chromeMenuLabel(meeting.reportTemplate?.name ?? "Auto")
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Template de rapport — modifie la structure du compte-rendu généré")
        .popover(isPresented: $showTemplatePicker, arrowEdge: .bottom) {
            StyledMenuPopover(titre: "Template de rapport",
                              items: templatePickerItems,
                              fermer: { showTemplatePicker = false })
        }
    }

    /// `Auto (selon type)` en tête, un filet, puis les templates compatibles —
    /// l'ordre du menu natif qu'il remplace.
    private var templatePickerItems: [StyledMenuPopover.Item] {
        var items = [
            StyledMenuPopover.Item(id: "template-auto",
                                   libelle: "Auto (selon type)",
                                   symbole: "wand.and.stars",
                                   selectionnee: meeting.reportTemplate == nil) {
                meeting.reportTemplate = nil
                try? modelContext.save()
            }
        ]
        for (index, t) in compatibleTemplates.enumerated() {
            items.append(StyledMenuPopover.Item(
                id: "template-\(t.persistentModelID.hashValue)",
                libelle: t.name,
                symbole: "doc.text",
                selectionnee: meeting.reportTemplate?.persistentModelID == t.persistentModelID,
                separateurAvant: index == 0
            ) {
                meeting.reportTemplate = t
                try? modelContext.save()
            })
        }
        return items
    }

    /// Templates non archivés proposés dans le sélecteur, triés par priorité :
    /// d'abord le `ReportTemplateKind` correspondant au type de la réunion,
    /// puis par ordre alphabétique (insensible à la casse).
    private var compatibleTemplates: [ReportTemplate] {
        let mapping: [MeetingKind: ReportTemplateKind] = [
            .global: .general,
            .oneToOne: .oneToOne,
            .manager: .manager,
            .project: .copil,
            .work: .general
        ]
        let preferred = mapping[meeting.kind] ?? .general
        // Escalade vient juste après le gabarit du type, et **seulement** sur
        // les deux types de tête-à-tête (décision D9) : c'est là qu'une ligne
        // escaladée peut exister.
        let secondaire: ReportTemplateKind? =
            (meeting.kind == .oneToOne || meeting.kind == .manager) ? .escalade : nil
        func rang(_ t: ReportTemplate) -> Int {
            if t.kind == preferred { return 0 }
            if let secondaire, t.kind == secondaire { return 1 }
            return 2
        }
        return allTemplates
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let li = rang(lhs), ri = rang(rhs)
                if li != ri { return li < ri }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: - Menu ⋯

    /// Les cinq entrées de la spec §2.1 : Exporter, Détails, Importer, Audio,
    /// Supprimer. Une note n'a ni audio ni import WAV — même règle que le menu
    /// natif, qui les grise plutôt que de les retirer
    /// (`MeetingMenuActions.disabledForNote`).
    private var moreMenu: some View {
        Menu {
            Menu {
                Button(action: actions.exportMarkdown) { Label("Copier Markdown", systemImage: "doc.text") }
                Button(action: actions.exportPDF) { Label("Exporter PDF", systemImage: "doc.richtext") }
                Menu {
                    Button { actions.exportMail([]) } label: { Label("Rapport seul", systemImage: "envelope") }
                    Button { actions.exportMail(.includeSlidesPDF) } label: { Label("Rapport + slides (PDF)", systemImage: "envelope.badge") }
                    Button { actions.exportMail([.includeTranscript]) } label: { Label("Rapport + transcript", systemImage: "envelope") }
                    Button { actions.exportMail([.includeTranscript, .includeSlidesPDF]) } label: { Label("Rapport + transcript + slides", systemImage: "envelope.badge") }
                } label: { Label("Envoyer via Apple Mail", systemImage: "envelope") }
                Menu {
                    Button { actions.exportOutlook([]) } label: { Label("Rapport seul", systemImage: "envelope") }
                    Button { actions.exportOutlook(.includeSlidesPDF) } label: { Label("Rapport + slides (PDF)", systemImage: "envelope.badge") }
                    Button { actions.exportOutlook([.includeTranscript]) } label: { Label("Rapport + transcript", systemImage: "envelope") }
                    Button { actions.exportOutlook([.includeTranscript, .includeSlidesPDF]) } label: { Label("Rapport + transcript + slides", systemImage: "envelope.badge") }
                } label: { Label("Envoyer via Microsoft Outlook", systemImage: "paperplane") }
                Menu {
                    Button { actions.exportAppleNotes([]) } label: { Label("Rapport seul", systemImage: "note.text") }
                    Button { actions.exportAppleNotes(.includeSlidesPDF) } label: { Label("Rapport + slides", systemImage: "note.text.badge.plus") }
                    Button { actions.exportAppleNotes([.includeTranscript]) } label: { Label("Rapport + transcript", systemImage: "note.text") }
                    Button { actions.exportAppleNotes([.includeTranscript, .includeSlidesPDF]) } label: { Label("Rapport + transcript + slides", systemImage: "note.text.badge.plus") }
                } label: { Label("Exporter vers Apple Notes", systemImage: "note.text") }
            } label: {
                Label("Exporter", systemImage: "square.and.arrow.up")
            }
            .disabled(!actions.hasReport)

            Divider()
            Button(action: actions.toggleCustomPrompt) { Label("Détails de la réunion…", systemImage: "slider.horizontal.3") }
            Menu {
                Button(action: actions.importCalendar) { Label("Importer Calendrier", systemImage: "calendar.badge.plus") }
                if !actions.isNote {
                    Button(action: actions.importExistingWAV) { Label("Importer un WAV existant", systemImage: "waveform.badge.plus") }
                }
            } label: { Label("Importer", systemImage: "square.and.arrow.down") }
            if !actions.isNote {
                Menu {
                    Button(action: actions.editAudio) { Label("Éditer l'audio…", systemImage: "scissors") }
                        .disabled(!actions.hasPlayableAudio)
                    Button(action: actions.revealWAV) { Label("Révéler le WAV dans Finder", systemImage: "folder") }
                        .disabled(!actions.hasPlayableAudio)
                } label: { Label("Audio", systemImage: "waveform") }
            }

            Divider()
            // Spec §1.4 : la table des raccourcis doit être consultable. Elle
            // vit ici parce que `⋯` est le seul menu de l'écran qui ne dépend
            // ni du type de réunion ni de l'état de l'audio.
            Button { showsShortcuts = true } label: {
                Label("Raccourcis clavier…", systemImage: "keyboard")
            }

            Divider()
            Button(role: .destructive, action: actions.deleteMeeting) {
                Label("Supprimer la réunion…", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(One2OneToken.ink3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Self.moreButtonWidth)
        .sheet(isPresented: $showsShortcuts) {
            MeetingShortcutsSheet()
        }
    }
}
