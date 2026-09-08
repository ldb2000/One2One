import SwiftUI
import SwiftData

/// La navigation latérale de 190 px du poste de pilotage (spec §2.7, capture
/// `1c-poste-de-pilotage.png`).
///
/// « Les onglets deviennent un rail latéral (plus d'onglet vide : chaque entrée
/// porte son compteur) ». C'est la même exigence que celle de
/// `MeetingSpacesBar.label(for:…)` au lot 1, poussée d'un cran : ici **toutes**
/// les entrées portent un compteur ou un état, y compris `Synthèse` et
/// `Assistant`, et c'est vérifié par un test d'exhaustivité — une entrée
/// ajoutée demain fait échouer la suite tant qu'elle n'a pas dit ce qu'elle
/// contient.
///
/// Dans ce mode, ce rail **remplace** la barre d'espaces (plan §1, décision
/// D0) : `Rapport` et `Documents` mènent aux espaces Rapport et Ressources,
/// `Notes` et `Transcription` ramènent en mode En séance — c'est le sens de
/// « transcription repliée » (spec §2.2), elle est à un clic —, `Assistant`
/// ouvre le dock, et `Synthèse` et `Actions` déplacent le défilement de la
/// colonne principale.
struct ReviewSidebarNav: View {

    /// Une entrée du rail, avec son complément **obligatoire**.
    struct Entree: Identifiable, Equatable {

        /// Ce que l'entrée annonce. Aucun cas « rien » : c'est tout le sens de
        /// « plus d'onglet vide ».
        enum Complement: Equatable {
            /// Un décompte : `5` notes, `12` actions, `3` documents.
            case compte(Int)
            /// Une durée en minutes : `23′`.
            case minutes(Int)
            /// Un état : `✓`, `—`, `⌘K`, `généré`.
            case etat(String)
            /// Une invite : `＋` (aucun document déposé).
            case invite

            /// Le texte affiché. Jamais vide, par construction.
            var texte: String {
                switch self {
                case .compte(let n):  return "\(n)"
                case .minutes(let m): return "\(m)′"
                case .etat(let e):    return e
                case .invite:         return "＋"
                }
            }
        }

        var section: ReviewState.Section
        var libelle: String
        var complement: Complement
        /// Le complément se lit en `accent/report` : une dette, pas une
        /// information (capture 1c : `Actions 12` en rouge).
        var alerte: Bool
        /// L'entrée est grisée : rien derrière pour l'instant (capture 1c :
        /// `Documents ＋`).
        var atone: Bool

        var id: ReviewState.Section { section }
    }

    /// Les entrées du rail, dans l'ordre de la capture.
    ///
    /// Table **exhaustive** sur `ReviewState.Section`, sans `default` : c'est la
    /// seule manière de faire signaler par le compilateur — et par le test — une
    /// entrée ajoutée sans compteur.
    @MainActor
    static func entrees(for meeting: Meeting) -> [Entree] {
        ReviewState.Section.allCases.map { section in
            switch section {
            case .synthese:
                return Entree(section: section,
                              libelle: section.libelle,
                              complement: .etat(meeting.shortSummary.isEmpty ? "—" : "généré"),
                              alerte: false,
                              atone: false)
            case .notes:
                let n = meeting.timedNotes.count
                return Entree(section: section,
                              libelle: section.libelle,
                              complement: .compte(n),
                              alerte: false,
                              atone: n == 0)
            case .transcription:
                return Entree(section: section,
                              libelle: section.libelle,
                              complement: .minutes(minutes(of: meeting)),
                              alerte: false,
                              atone: meeting.rawTranscript.isEmpty)
            case .actions:
                let total = meeting.tasks.count
                let sansPorteur = meeting.tasks.filter {
                    $0.status == .open && !ActionsRailGrouping.aUnPorteur($0)
                }.count
                return Entree(section: section,
                              libelle: section.libelle,
                              complement: .compte(total),
                              alerte: sansPorteur > 0,
                              atone: total == 0)
            case .rapport:
                let genere = !meeting.summary.isEmpty
                return Entree(section: section,
                              libelle: section.libelle,
                              complement: .etat(genere ? "✓" : "—"),
                              alerte: false,
                              atone: !genere)
            case .documents:
                let n = meeting.attachments.count
                return Entree(section: section,
                              libelle: section.libelle,
                              complement: n == 0 ? .invite : .compte(n),
                              alerte: false,
                              atone: n == 0)
            case .assistant:
                // L'assistant n'a rien à compter : son complément est son
                // raccourci (spec §1.4, `⌘K`). Un complément vide ferait de lui
                // le seul « onglet vide » du rail.
                return Entree(section: section,
                              libelle: section.libelle,
                              complement: .etat("⌘K"),
                              alerte: false,
                              atone: false)
            }
        }
    }

    /// La durée de la réunion en minutes, arrondie — le `23′` de la capture.
    ///
    /// La durée de la séance (`meetingDurationSeconds`) l'emporte sur celle de
    /// l'enregistrement : on relit une réunion de 23 minutes, même si l'audio
    /// n'en couvre que vingt.
    static func minutes(of meeting: Meeting) -> Int {
        let secondes = meeting.meetingDurationSeconds > 0
            ? meeting.meetingDurationSeconds
            : meeting.durationSeconds
        return Int((Double(secondes) / 60).rounded())
    }

    /// Les trois dernières réunions du **même projet**, de la plus récente à la
    /// plus ancienne (capture 1c : `1 sept. — COSUI hebdo`, `31 août —
    /// Gouvernance`, `26 août — Situation AP`).
    ///
    /// Antérieures seulement : une réunion à venir n'est pas un antécédent, et
    /// la faire figurer dans un bloc d'historique tromperait.
    @MainActor
    static func dernieresDuProjet(_ meeting: Meeting,
                                  dans historique: [Meeting],
                                  limite: Int = 3) -> [Meeting] {
        guard let projet = meeting.project else { return [] }
        return historique
            .filter { autre in
                autre.persistentModelID != meeting.persistentModelID
                    && autre.project?.persistentModelID == projet.persistentModelID
                    && autre.date < meeting.date
            }
            .sorted { $0.date > $1.date }
            .prefix(limite)
            .map { $0 }
    }

    /// `1 sept. — COSUI hebdo` : la date d'abord, parce que c'est par elle qu'on
    /// cherche. L'ordinal du premier du mois vient
    /// d'`ActionsRailGrouping.dateOrdinale` — deux formateurs de date
    /// finiraient par écrire « 1 sept. » d'un côté et « 1er sept. » de l'autre.
    @MainActor
    static func libelleReunion(_ meeting: Meeting, calendar: Calendar = .current) -> String {
        let titre = titreCourt(meeting.title)
        return "\(ActionsRailGrouping.dateOrdinale(meeting.date, calendar: calendar)) — \(titre)"
    }

    /// Le titre sans son préfixe de référence projet (`[P25_110] `) : dans
    /// 190 px, la référence prend la place du sujet, et elle est déjà dans
    /// l'en-tête.
    static func titreCourt(_ titre: String) -> String {
        guard titre.hasPrefix("["), let fin = titre.firstIndex(of: "]") else { return titre }
        return String(titre[titre.index(after: fin)...])
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Entrées de la vue

    let meeting: Meeting
    let screen: MeetingScreenModel
    /// Réunions connues, pour le bloc projet.
    let historique: [Meeting]
    /// Ouvre une autre réunion du projet.
    let onOpenMeeting: (PersistentIdentifier) -> Void
    /// Ouvre le dock de l'assistant (entrée `Assistant`).
    let onOpenAssistant: () -> Void

    /// Les risques ouverts de la réunion puis du projet — la même lecture que
    /// l'onglet Risques du rail, pour que le bloc `ALERTES` et lui n'annoncent
    /// jamais deux nombres différents.
    private var alertes: [ProjectAlert] {
        let deLaReunion = meeting.meetingAlerts.filter { !$0.isResolved }
        let dejaListes = Set(deLaReunion.map(\.persistentModelID))
        let duProjet = (meeting.project?.alerts ?? [])
            .filter { !$0.isResolved && !dejaListes.contains($0.persistentModelID) }
        return ActionsRailRisks.triees(deLaReunion) + ActionsRailRisks.triees(duProjet)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                marque
                SectionLabel("séance")
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Self.entrees(for: meeting)) { entree in
                        ligne(entree)
                    }
                }
                .padding(.horizontal, 8)

                blocProjet
                Spacer(minLength: 12)
                blocAlertes
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: One2OneToken.sideNavWidth)
        .background(One2OneToken.bgApp)
    }

    // MARK: - Marque

    private var marque: some View {
        HStack(spacing: 8) {
            Text("1:1")
                .font(.plexMono(10, .semibold))
                .foregroundStyle(One2OneToken.onFilledButton)
                .padding(.horizontal, 5)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.ink1)
                )
            Text("One2One")
                .font(.plexSans(13, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    // MARK: - Entrées

    @ViewBuilder
    private func ligne(_ entree: Entree) -> some View {
        let actif = screen.review.section == entree.section
        Button {
            selectionner(entree.section)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entree.section.symbole)
                    .font(.system(size: 10))
                    .foregroundStyle(couleurDuSymbole(entree, actif: actif))
                    .frame(width: 13)
                Text(entree.libelle)
                    .font(.plexSans(12, actif ? .semibold : .regular))
                    .foregroundStyle(entree.atone && !actif
                                     ? One2OneToken.inkMuted
                                     : One2OneToken.ink2)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(entree.complement.texte)
                    .font(.plexMono(10, .medium))
                    .foregroundStyle(couleurDuComplement(entree))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Rectangle())
            // L'entrée active est une **carte blanche à ombre de 1 px**
            // (spec §2.7) : pas un soulignement — celui-ci reste réservé à la
            // barre d'espaces, et deux marques de sélection sur le même écran
            // ne se hiérarchisent plus.
            .background {
                if actif {
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.surface)
                        .shadow(color: One2OneToken.hair, radius: 0, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(actif ? [.isSelected] : [])
        .help(aide(entree))
    }

    private func couleurDuSymbole(_ entree: Entree, actif: Bool) -> Color {
        if entree.section == .rapport, !meeting.summary.isEmpty { return One2OneToken.report }
        if entree.atone && !actif { return One2OneToken.inkMuted }
        return actif ? One2OneToken.ink2 : One2OneToken.ink4
    }

    private func couleurDuComplement(_ entree: Entree) -> Color {
        if entree.alerte { return One2OneToken.report }
        if entree.section == .rapport, !meeting.summary.isEmpty { return One2OneToken.okDeep }
        return One2OneToken.ink4
    }

    private func aide(_ entree: Entree) -> String {
        switch entree.section {
        case .rapport:       return "Ouvrir l'espace Rapport"
        case .documents:     return "Ouvrir l'espace Ressources"
        case .assistant:     return "Interroger l'assistant (⌘K)"
        case .notes:         return "Déplier les notes de la séance"
        case .transcription: return "Déplier la transcription"
        default:             return "Aller à \(entree.libelle)"
        }
    }

    private func selectionner(_ section: ReviewState.Section) {
        if let espace = section.changeDEspace {
            screen.space = espace
            return
        }
        if let mode = section.changeDeMode {
            screen.mode = mode
            return
        }
        if section == .assistant {
            onOpenAssistant()
            return
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            screen.review.section = section
        }
    }

    // MARK: - Bloc projet

    @ViewBuilder
    private var blocProjet: some View {
        let precedentes = Self.dernieresDuProjet(meeting, dans: historique)
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("projet")
            if let projet = meeting.project {
                Text(projet.name)
                    .font(.plexSans(12))
                    .foregroundStyle(One2OneToken.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Hors projet")
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
            }
            if precedentes.isEmpty {
                // Aucune zone vide sans invite (critère n° 1 du chantier 1) :
                // une première réunion de projet n'a pas d'antécédent, et le
                // dire vaut mieux qu'un bloc tronqué.
                Text(meeting.project == nil
                     ? "Rattachez la réunion à un projet pour retrouver son fil."
                     : "Première réunion du projet.")
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(precedentes) { precedente in
                    Button {
                        onOpenMeeting(precedente.persistentModelID)
                    } label: {
                        HStack(alignment: .top, spacing: 5) {
                            Text("·")
                                .font(.plexSans(11.5))
                                .foregroundStyle(One2OneToken.ink4)
                            Text(Self.libelleReunion(precedente))
                                .font(.plexSans(11.5))
                                .foregroundStyle(One2OneToken.ink3)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Ouvrir cette réunion")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
    }

    // MARK: - Bloc alertes

    /// Au plus quatre titres, comme la capture, puis `+n` : dans 190 px, une
    /// cinquième ligne pousse le bloc hors de l'écran, et un bloc d'alertes
    /// qu'on ne voit pas n'alerte personne.
    @ViewBuilder
    private var blocAlertes: some View {
        let toutes = alertes
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionLabel("alertes")
                    .foregroundStyle(One2OneToken.report)
                // `ALERTES · 5` comme la capture `1c-poste-de-pilotage.png`
                // (et comme `DÉCISIONS PRISES · 3` et `RISQUES · 5`) : le
                // point médian sépare le libellé de son compteur.
                MonoMeta("· \(toutes.count)", emphase: !toutes.isEmpty)
                Spacer(minLength: 0)
            }
            if toutes.isEmpty {
                Text("Aucun risque ouvert — /risque dans les notes.")
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(toutes.prefix(4), id: \.persistentModelID) { alerte in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(ActionsRailRisks.teinte(alerte.severity))
                            .frame(width: 6, height: 6)
                            .padding(.top, 4)
                        Text(alerte.title)
                            .font(.plexSans(11.5))
                            .foregroundStyle(One2OneToken.ink2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                if toutes.count > 4 {
                    // Singulier quand il n'en reste qu'une, et `ink/4` : la
                    // spec §1.2 réserve `ink/muted` aux textes de 11,5 px et
                    // plus.
                    Text(toutes.count - 4 == 1 ? "+1 autre" : "+\(toutes.count - 4) autres")
                        .font(.plexSans(11))
                        .foregroundStyle(One2OneToken.ink4)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 8)
    }
}
