import Foundation

/// Le récap de clôture d'un entretien, en markdown — **pur**.
///
/// C'est la **sixième** sortie de texte de l'application, après le prompt de
/// rapport, le HTML, l'export markdown, l'index RAG et le contexte des chats.
/// Comme les cinq autres, elle ne compare aucune `visibility` elle-même : tout
/// passe par `ConfidentialityFilter.isExportable(_:for:)` (spec §8). Un
/// septième lecteur qui ferait autrement serait une fuite.
///
/// Trois audiences en service (D9) :
/// - `.collaborator` — `Envoyer le récap à <Prénom>` côté manager ;
/// - `.manager` — `Envoyer mon récap` côté collaborateur ;
/// - `.hr` — l'export « Escalade », la seule sortie qui emporte les lignes
///   `escalated` et qui laisse les lignes seulement `shared`.
@MainActor
enum OneOnOneRecapBuilder {

    // MARK: - Markdown

    /// Le récap complet, filtré pour `audience`.
    static func markdown(for meeting: Meeting,
                         thread: OneOnOneThread,
                         audience: Audience,
                         now: Date) -> String {
        var blocs: [String] = ["# \(subject(for: meeting, thread: thread))"]

        if let sujets = topicsBlock(meeting, thread, audience) { blocs.append(sujets) }
        if let engagements = commitmentsBlock(thread, audience) { blocs.append(engagements) }
        if let humeur = moodBlock(meeting, thread, audience) { blocs.append(humeur) }
        if let feedback = feedbackBlock(meeting, audience) { blocs.append(feedback) }
        if let notes = notesBlock(meeting, audience) { blocs.append(notes) }

        let exclues = excludedLinesCount(for: meeting, thread: thread, audience: audience)
        if exclues > 0 {
            // Spec §3.2 : « le bouton de clôture affiche systématiquement le
            // compte des lignes exclues ». Le récap le redit, pour que le
            // destinataire sache qu'il ne lit pas tout.
            blocs.append("---\n\(exclues) ligne\(exclues > 1 ? "s" : "") "
                         + "\(exclues > 1 ? "ont" : "a") été exclue\(exclues > 1 ? "s" : "") de ce récap.")
        }

        return blocs.joined(separator: "\n\n") + "\n"
    }

    /// `## Sujets abordés` — les sujets d'ordre du jour de la séance.
    private static func topicsBlock(_ meeting: Meeting,
                                    _ thread: OneOnOneThread,
                                    _ audience: Audience) -> String? {
        let sujets = AgendaCarryover.items(of: thread, for: meeting)
            .filter { ConfidentialityFilter.isExportable($0, for: audience) }
        guard !sujets.isEmpty else { return nil }
        let lignes = sujets.map { item in
            let coche = item.state == .done ? "x" : " "
            let report = AgendaCarryover.deferredLabel(item).map { " \($0)" } ?? ""
            return "- [\(coche)] \(item.text)\(report)"
        }
        return (["## Sujets abordés"] + lignes).joined(separator: "\n")
    }

    /// `## Engagements` — deux sous-blocs, `Moi` et `<Prénom>`, comme la
    /// colonne de droite de la capture 2a.
    private static func commitmentsBlock(_ thread: OneOnOneThread,
                                         _ audience: Audience) -> String? {
        var sections: [String] = []
        for cote in [OneOnOneSide.manager, .collaborator] {
            let engagements = CommitmentLedger.all(thread, side: cote)
                .filter { ConfidentialityFilter.isExportable($0, for: audience) }
            guard !engagements.isEmpty else { continue }
            let titre = sideTitle(cote, in: thread)
            let lignes = engagements.map { engagement -> String in
                let coche = engagement.state == .kept ? "x" : " "
                var ligne = "- [\(coche)] \(engagement.text)"
                if let due = engagement.dueAt {
                    ligne += " — \(OneOnOneDateFormat.dayMonth(due))"
                }
                if let reports = CommitmentLedger.deferralLabel(engagement) {
                    ligne += " (\(reports))"
                }
                if engagement.state == .missed { ligne += " — manqué" }
                return ligne
            }
            sections.append((["### \(titre)"] + lignes).joined(separator: "\n"))
        }
        guard !sections.isEmpty else { return nil }
        return (["## Engagements"] + sections).joined(separator: "\n\n")
    }

    /// `## Comment ça va` — le cran de la séance et son delta.
    ///
    /// **Jamais vers les RH ni vers l'équipe projet.** Le cran de moral est ce
    /// que la personne a dit d'elle-même à son manager ; le faire monter à la
    /// hiérarchie au détour d'une escalade trahirait la question posée.
    private static func moodBlock(_ meeting: Meeting,
                                  _ thread: OneOnOneThread,
                                  _ audience: Audience) -> String? {
        switch audience {
        case .hr, .projectTeam: return nil
        case .me, .collaborator, .manager: break
        }
        guard let entree = MoodTrend.entry(for: meeting, in: thread) else { return nil }
        var ligne = MoodLevel.clamped(entree.value).label
        if let delta = MoodTrend.deltaLabel(thread) { ligne += " (\(delta))" }
        return "## Comment ça va\n\(ligne)"
    }

    /// `## Feedback` — les deux sens, séparés par leur auteur.
    private static func feedbackBlock(_ meeting: Meeting, _ audience: Audience) -> String? {
        let retours = MeetingNoteStore.exportable(meeting.timedNotes, for: audience)
            .filter { $0.kind == .feedback }
        guard !retours.isEmpty else { return nil }
        let lignes = retours.map { note -> String in
            let sens = note.authorSide == .me ? "Ce que je lui dis" : "Ce qu'il me dit"
            return "- \(sens) : \(note.text)"
        }
        return (["## Feedback"] + lignes).joined(separator: "\n")
    }

    /// `## Notes de la séance` — tout le reste des lignes horodatées.
    private static func notesBlock(_ meeting: Meeting, _ audience: Audience) -> String? {
        let notes = MeetingNoteStore.exportable(meeting.timedNotes, for: audience)
            .filter { $0.kind != .feedback }
        guard !notes.isEmpty else { return nil }
        return "## Notes de la séance\n\(MeetingNoteStore.markdown(notes))"
    }

    /// Le titre d'un côté : `Moi` pour le mien, le prénom pour l'autre.
    static func sideTitle(_ side: OneOnOneSide, in thread: OneOnOneThread) -> String {
        side == thread.myRole ? "Moi" : OneOnOneThreadStore.firstName(of: thread)
    }

    // MARK: - Exclusions

    /// Le nombre de lignes que `audience` ne verra pas — notes, engagements et
    /// sujets confondus : c'est ce que le bouton de clôture doit annoncer.
    static func excludedLinesCount(for meeting: Meeting,
                                   thread: OneOnOneThread,
                                   audience: Audience) -> Int {
        var lignes: [any Confidential] = meeting.timedNotes
        lignes += thread.commitments as [any Confidential]
        lignes += AgendaCarryover.items(of: thread, for: meeting) as [any Confidential]
        return OneOnOneConfidentiality.excludedLinesCount(lignes, for: audience)
    }

    // MARK: - Titres

    /// `Récap 1:1 — Laurent NOMINÉ — 4 sept. 2026`.
    static func subject(for meeting: Meeting, thread: OneOnOneThread) -> String {
        let nom = thread.collaborator?.name ?? "1:1"
        return "Récap 1:1 — \(nom) — \(OneOnOneDateFormat.dayMonthYear(meeting.date))"
    }

    /// `1:1 — Laurent` : le titre de l'événement du prochain entretien.
    static func nextMeetingTitle(for thread: OneOnOneThread) -> String {
        "1:1 — \(OneOnOneThreadStore.firstName(of: thread))"
    }

    // MARK: - Destinataires

    /// Le destinataire du récap : la personne du fil, si son adresse est
    /// plausible. Vide sinon — mieux vaut un brouillon sans destinataire qu'un
    /// envoi vers « Laurent NOMINÉ ».
    static func recipients(for thread: OneOnOneThread) -> [String] {
        let adresse = thread.collaborator?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard adresse.contains("@"),
              !adresse.contains(" "),
              let arobase = adresse.firstIndex(of: "@"),
              adresse[arobase...].contains(".") else { return [] }
        return [adresse]
    }

    // MARK: - Dossier annuel

    /// `recordings/annual/<année>/<collaborateur>/`.
    ///
    /// Sous `recordings/` et non à côté : `StorageStatsService`,
    /// `OrphanCleanupService` et les sauvegardes ne connaissent que cette
    /// racine, et un dossier qu'aucun d'eux ne voit finit par grossir seul.
    static func annualFolderURL(for thread: OneOnOneThread,
                                date: Date,
                                root: URL? = nil) -> URL {
        let annee = Calendar(identifier: .gregorian).component(.year, from: date)
        let racine = root ?? applicationSupportRoot()
        return racine
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent("annual", isDirectory: true)
            .appendingPathComponent(String(annee), isDirectory: true)
            .appendingPathComponent(sanitized(thread.collaborator?.name ?? "Inconnu"),
                                    isDirectory: true)
    }

    /// `2026-09-04.md` — trié lexicographiquement, donc chronologiquement.
    static func annualFileName(for date: Date) -> String {
        "\(OneOnOneDateFormat.isoDay(date)).md"
    }

    /// Un nom de personne utilisable comme composant de chemin : `/` et `:`
    /// sont interdits par le système de fichiers ou par le Finder.
    static func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func applicationSupportRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("OneToOne", isDirectory: true)
    }
}
