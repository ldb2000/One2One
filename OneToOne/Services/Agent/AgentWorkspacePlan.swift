import Foundation

/// Compose le dossier de travail que l'agent explorera.
///
/// Fonction pure : entrée en DTO, sortie en `[AgentWorkspaceFile]`. L'écriture
/// sur disque est le travail d'une autre couche, ce qui rend le contenu du
/// dossier vérifiable par des tests plutôt que par une inspection du Finder.
enum AgentWorkspacePlan {

    /// Plafonds de contexte. Au-delà, on paie du jeton sans gagner en justesse :
    /// une action porte rarement sur plus de dix réunions.
    static let maxMeetings = 10
    static let maxMails = 20
    static let maxCharactersPerDocument = 8_000

    /// Dossiers créés vides — l'agent y déposera son travail.
    static let directories = ["contexte", "echange", "livrables"]

    static func plan(for input: AgentWorkspaceInput, timeZone: TimeZone = .current) -> [AgentWorkspaceFile] {
        let day = dayFormatter(timeZone)
        var files = [
            AgentWorkspaceFile(path: "BRIEF.md", contents: brief(input, day: day)),
            AgentWorkspaceFile(path: "AGENT.md", contents: systemPrompt())
        ]

        if let project = input.project {
            files.append(.init(path: "contexte/projet.md", contents: sheet(project)))
        }
        if let collaborator = input.collaborator {
            files.append(.init(path: "contexte/collaborateur.md", contents: sheet(collaborator)))
        }
        if !input.alerts.isEmpty {
            files.append(.init(path: "contexte/alertes.md", contents: sheet(input.alerts)))
        }

        files += input.meetings
            .sorted { $0.date > $1.date }
            .prefix(maxMeetings)
            .enumerated()
            .map { rank, meeting in
                AgentWorkspaceFile(
                    path: "contexte/reunions/\(numbered(rank, meeting.title))",
                    contents: sheet(meeting, day: day)
                )
            }

        files += input.mails
            .sorted { $0.date > $1.date }
            .prefix(maxMails)
            .enumerated()
            .map { rank, mail in
                AgentWorkspaceFile(
                    path: "contexte/mails/\(numbered(rank, mail.subject))",
                    contents: sheet(mail, day: day)
                )
            }

        return files
    }

    // MARK: - Le brief

    private static func brief(_ input: AgentWorkspaceInput, day: DateFormatter) -> String {
        let action = input.action
        var lines = [
            "# Ce que j'attends de toi",
            "",
            action.request,
            "",
            "## L'action",
            "",
            "- **Intitulé** : \(action.title)",
            "- **Destinataire** : \(action.audience)"
        ]

        if let due = action.dueDate { lines.append("- **Échéance** : \(day.string(from: due))") }
        if action.isUrgent { lines.append("- **Urgente**") }
        if action.isImportant { lines.append("- **Importante**") }

        lines += [
            "- **Format attendu** : " + (input.expectedFormat.map { "`\($0)`" } ?? "au choix — retiens le plus adapté")
        ]

        if !action.comments.isEmpty {
            lines += ["", "## Commentaires portés sur l'action", ""]
            lines += action.comments.map { "- \($0)" }
        }

        lines += [
            "",
            "## Le contexte à ta disposition",
            "",
            "Le dossier `contexte/` rassemble ce que l'application sait du sujet :",
            "la fiche du projet, celle du collaborateur, les alertes ouvertes, les",
            "comptes rendus des réunions liées et les mails classés. Lis ce qui te",
            "sert, ignore le reste."
        ]

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Le prompt système

    private static func systemPrompt() -> String {
        """
        # Ton rôle

        Tu produis le livrable d'une action professionnelle pour un manager
        d'architectes. Lis `BRIEF.md`, puis le dossier `contexte/`. Écris en
        français, dans un registre professionnel sobre.

        # Ce que tu peux faire

        Tu travailles **uniquement** dans ce dossier. Tu n'as accès ni à
        l'application, ni à sa base de données : tout ce que tu sais du sujet
        vient des fichiers présents ici.

        # Où déposer ton travail

        Tout livrable va dans `livrables/`, jamais ailleurs. Un chemin qui sort
        du dossier de travail est refusé par l'application.

        Pour les formats bureautiques, passe par `uv`, sans rien installer :

        ```
        uv run --with python-docx  script.py    # Word
        uv run --with python-pptx  script.py    # PowerPoint
        uv run --with openpyxl     script.py    # Excel
        ```

        # Quand une information te manque

        Ne devine pas ce qui engage : un montant, une date d'engagement, un nom
        de destinataire, un arbitrage. Écris ta question dans
        `echange/question.md`, termine ton tour, et attends. Tu retrouveras la
        réponse dans `echange/reponse.md` au tour suivant.

        En revanche, ne demande rien que tu peux raisonnablement déduire du
        contexte : formule une hypothèse, déclare-la, et avance.

        # Comment terminer chaque tour

        Écris **toujours** `etat.json` avant de rendre la main :

        ```json
        {
          "etat": "question",
          "question": "Quel montant dois-je annoncer ?",
          "livrables": [
            { "fichier": "livrables/note.docx", "type": "docx", "titre": "Note de cadrage" }
          ],
          "hypotheses": ["J'ai retenu le CR du 3 août"],
          "resume": "Une phrase sur ce que tu as fait."
        }
        ```

        - `"etat"` vaut `"question"` (il te manque une information),
          `"livrable"` (le travail est prêt à relire) ou `"bloque"` (le contexte
          ne permet pas d'aboutir, explique pourquoi dans `resume`).
        - `"type"` vaut `mail`, `prompt`, `md`, `docx`, `pptx`, `xlsx` ou `pdf`.
        - Un `"etat"` valant `"question"` exige une `"question"` non vide.

        Un mail est un **brouillon** : l'auteur le relit et l'envoie lui-même.
        """
    }

    // MARK: - Les fiches de contexte

    private static func sheet(_ project: AgentWorkspaceInput.Project) -> String {
        var lines = ["# Projet — \(project.name)", ""]
        if let phase = project.phase     { lines.append("- **Phase** : \(phase)") }
        if let sponsor = project.sponsor { lines.append("- **Sponsor** : \(sponsor)") }
        if let entity = project.entity   { lines.append("- **Entité** : \(entity)") }
        if let summary = project.summary { lines += ["", summary] }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func sheet(_ collaborator: AgentWorkspaceInput.Collaborator) -> String {
        var lines = ["# Collaborateur — \(collaborator.name)", ""]
        if let role = collaborator.role   { lines.append("- **Rôle** : \(role)") }
        if let notes = collaborator.notes { lines += ["", notes] }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func sheet(_ alerts: [AgentWorkspaceInput.Alert]) -> String {
        let body = alerts.map { "## \($0.title)\n\n- **Gravité** : \($0.severity)\n\n\($0.detail)" }
        return (["# Alertes ouvertes", ""] + body).joined(separator: "\n") + "\n"
    }

    private static func sheet(_ meeting: AgentWorkspaceInput.Meeting, day: DateFormatter) -> String {
        """
        # \(meeting.title)

        - **Date** : \(day.string(from: meeting.date))

        \(truncated(meeting.report))
        """
    }

    private static func sheet(_ mail: AgentWorkspaceInput.Mail, day: DateFormatter) -> String {
        """
        # \(mail.subject)

        - **Date** : \(day.string(from: mail.date))
        - **De** : \(mail.sender)

        \(truncated(mail.body))
        """
    }

    // MARK: - Détail

    /// Coupe un document trop long **en le disant**. Un agent qui ignore qu'il
    /// lit un extrait conclut sur une base tronquée sans le signaler.
    private static func truncated(_ text: String) -> String {
        guard text.count > maxCharactersPerDocument else { return text }
        return String(text.prefix(maxCharactersPerDocument))
            + "\n\n> _[Contenu tronqué à \(maxCharactersPerDocument) caractères.]_"
    }

    private static func numbered(_ rank: Int, _ title: String) -> String {
        String(format: "%03d-%@.md", rank + 1, slug(title))
    }

    /// Un titre de réunion peut porter accents, ponctuation et barres obliques ;
    /// un nom de fichier ne le peut pas.
    private static func slug(_ title: String) -> String {
        let folded = title
            .folding(options: [.diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        let allowed = CharacterSet.alphanumerics
        let pieces = folded.unicodeScalars
            .split { !allowed.contains($0) }
            .map(String.init)

        let slug = pieces.joined(separator: "-").prefix(40)
        return slug.isEmpty ? "sans-titre" : String(slug)
    }

    private static func dayFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
