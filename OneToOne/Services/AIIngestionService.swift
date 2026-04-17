import Foundation
import SwiftData
import PDFKit

// MARK: - Extracted data structures

struct ExtractedData: Decodable {
    let projects: [ExtractedProject]
    let collaborators: [ExtractedCollaborator]
    let summary: String?

    // Accept extra fields Claude might add
    enum CodingKeys: String, CodingKey {
        case projects, collaborators, summary
    }

    init(projects: [ExtractedProject], collaborators: [ExtractedCollaborator], summary: String?) {
        self.projects = projects
        self.collaborators = collaborators
        self.summary = summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = (try? container.decode([ExtractedProject].self, forKey: .projects)) ?? []
        collaborators = (try? container.decode([ExtractedCollaborator].self, forKey: .collaborators)) ?? []
        summary = try? container.decode(String.self, forKey: .summary)
    }
}

struct ExtractedProject: Decodable {
    let code: String
    let name: String
    let domain: String
    let phase: String
    let status: String
    let riskLevel: String?
    let riskDescription: String?
    let keyPoints: [String]?
    let deliveryDate: String?
    let comment: String?
    let collaboratorNames: [String]?
    let sponsor: String?
    let projectType: String?
    let entityName: String?
    let plannedDays: Double?
    let designEndDeadline: String?

    // Flexible init that handles both English and French field names from Claude
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexKey.self)
        code = (try? c.decode(String.self, forKey: FlexKey("code"))) ?? "AUTO"
        name = (try? c.decode(String.self, forKey: FlexKey("name")))
            ?? (try? c.decode(String.self, forKey: FlexKey("nom"))) ?? "Sans nom"
        domain = (try? c.decode(String.self, forKey: FlexKey("domain")))
            ?? (try? c.decode(String.self, forKey: FlexKey("domaine"))) ?? ""
        phase = (try? c.decode(String.self, forKey: FlexKey("phase"))) ?? "Cadrage"
        status = (try? c.decode(String.self, forKey: FlexKey("status")))
            ?? (try? c.decode(String.self, forKey: FlexKey("statut"))) ?? "Unknown"
        riskLevel = (try? c.decode(String.self, forKey: FlexKey("riskLevel")))
            ?? (try? c.decode(String.self, forKey: FlexKey("niveauRisque")))
            ?? (try? c.decode(String.self, forKey: FlexKey("risque")))
        riskDescription = (try? c.decode(String.self, forKey: FlexKey("riskDescription")))
            ?? (try? c.decode(String.self, forKey: FlexKey("descriptionRisque")))
        keyPoints = (try? c.decode([String].self, forKey: FlexKey("keyPoints")))
            ?? (try? c.decode([String].self, forKey: FlexKey("pointsCles")))
        deliveryDate = (try? c.decode(String.self, forKey: FlexKey("deliveryDate")))
            ?? (try? c.decode(String.self, forKey: FlexKey("dateLivraison")))
            ?? (try? c.decode(String.self, forKey: FlexKey("deadline_fin_design")))
        comment = (try? c.decode(String.self, forKey: FlexKey("comment")))
            ?? (try? c.decode(String.self, forKey: FlexKey("commentaire")))
            ?? (try? c.decode(String.self, forKey: FlexKey("commentaires")))
        collaboratorNames = (try? c.decode([String].self, forKey: FlexKey("collaboratorNames")))
            ?? (try? c.decode([String].self, forKey: FlexKey("collaborateurs")))
        sponsor = (try? c.decode(String.self, forKey: FlexKey("sponsor")))
        projectType = (try? c.decode(String.self, forKey: FlexKey("projectType")))
            ?? (try? c.decode(String.self, forKey: FlexKey("type")))
        entityName = (try? c.decode(String.self, forKey: FlexKey("entityName")))
            ?? (try? c.decode(String.self, forKey: FlexKey("entite")))
        if let d = try? c.decode(Double.self, forKey: FlexKey("plannedDays")) {
            plannedDays = d
        } else if let d = try? c.decode(Double.self, forKey: FlexKey("nombre_de_jours")) {
            plannedDays = d
        } else if let i = try? c.decode(Int.self, forKey: FlexKey("nombre_de_jours")) {
            plannedDays = Double(i)
        } else if let i = try? c.decode(Int.self, forKey: FlexKey("plannedDays")) {
            plannedDays = Double(i)
        } else {
            plannedDays = nil
        }
        designEndDeadline = (try? c.decode(String.self, forKey: FlexKey("designEndDeadline")))
            ?? (try? c.decode(String.self, forKey: FlexKey("deadline_fin_design")))
    }
}

struct ExtractedCollaborator: Decodable {
    let name: String
    let role: String?

    init(name: String, role: String?) {
        self.name = name
        self.role = role
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexKey.self)
        name = (try? c.decode(String.self, forKey: FlexKey("name")))
            ?? (try? c.decode(String.self, forKey: FlexKey("nom"))) ?? "Inconnu"
        role = (try? c.decode(String.self, forKey: FlexKey("role")))
            ?? (try? c.decode(String.self, forKey: FlexKey("poste")))
    }
}

/// Dynamic CodingKey that accepts any string
struct FlexKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { self.stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

struct CandidateInterviewDraft: Codable {
    let summary: String
    let positivePoints: [String]
    let negativePoints: [String]
    let trainingAssessment: [String]
    let experienceNotes: String
    let skillsNotes: String
    let motivationNotes: String
    let linkedinHints: String
}

// MARK: - AI Ingestion Service

class AIIngestionService {

    // MARK: - File processing

    func processFile(at url: URL, settings: AppSettings) async throws -> ExtractedData {
        // Try direct JSON import first (no AI needed)
        if url.pathExtension.lowercased() == "json" {
            if let directResult = try? importDirectJSON(from: url) {
                print("[AIIngestion] Direct JSON import: \(directResult.projects.count) projects")
                return directResult
            }
        }

        let text = try extractText(from: url)
        print("[AIIngestion] Extracted \(text.count) characters from \(url.lastPathComponent)")

        guard !text.isEmpty else {
            throw IngestionError.emptyFile
        }

        let extracted = try await callAI(text: text, fileName: url.lastPathComponent, settings: settings)
        print("[AIIngestion] Extracted \(extracted.projects.count) projects, \(extracted.collaborators.count) collaborators")
        return extracted
    }

    /// Direct JSON import without AI — handles structured project data files.
    /// Extracts sponsors from projects as collaborators if no collaborators array is present.
    func importDirectJSON(from url: URL) throws -> ExtractedData {
        let data = try Data(contentsOf: url)
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        var extracted = try parseJSON(jsonString, as: ExtractedData.self)

        // If no collaborators were decoded, extract unique sponsors as collaborators
        if extracted.collaborators.isEmpty {
            let sponsors = Set(extracted.projects.compactMap { $0.sponsor }.filter { !$0.isEmpty })
            let collabs = sponsors.map { ExtractedCollaborator(name: $0, role: "Sponsor") }
            extracted = ExtractedData(projects: extracted.projects, collaborators: collabs, summary: extracted.summary)
        }

        return extracted
    }

    /// Process file with a user-customized prompt
    func processFileWithPrompt(at url: URL, customPrompt: String, settings: AppSettings) async throws -> ExtractedData {
        // Try direct JSON import first (no AI needed)
        if url.pathExtension.lowercased() == "json" {
            do {
                let directResult = try importDirectJSON(from: url)
                print("[AIIngestion] Direct JSON import SUCCESS: \(directResult.projects.count) projects, \(directResult.collaborators.count) collaborators")
                return directResult
            } catch {
                print("[AIIngestion] Direct JSON import failed, falling back to AI: \(error)")
            }
        }

        let text = try extractText(from: url)
        print("[AIIngestion] Extracted \(text.count) chars from \(url.lastPathComponent)")
        print("[AIIngestion] Text preview: \(String(text.prefix(200)))")

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IngestionError.emptyFile
        }

        let fullPrompt = customPrompt + "\n\nContenu du fichier \"\(url.lastPathComponent)\":\n" + String(text.prefix(30000))
        let response = try await AIClient.send(prompt: fullPrompt, settings: settings)
        return try parseJSON(response)
    }

    func analyzeCandidateFile(at url: URL, settings: AppSettings) async throws -> CandidateInterviewDraft {
        let text = try extractText(from: url)
        guard !text.isEmpty else {
            throw IngestionError.emptyFile
        }

        let prompt = """
        Analyse ce CV / dossier candidat et prépare un brouillon d'entretien de recrutement.

        Réponds UNIQUEMENT en JSON avec la structure suivante:
        {
          "summary": "synthèse en 4-5 phrases",
          "positivePoints": ["point positif 1", "point positif 2"],
          "negativePoints": ["point de vigilance 1", "point de vigilance 2"],
          "trainingAssessment": ["évaluation formation 1", "évaluation formation 2"],
          "experienceNotes": "analyse de l'expérience",
          "skillsNotes": "analyse des compétences",
          "motivationNotes": "analyse motivation / posture",
          "linkedinHints": "points à vérifier ou enrichir via LinkedIn"
        }

        Règles:
        - N'invente rien
        - Sois concret et exploitable par un recruteur
        - Fais apparaître les incohérences, signaux faibles et points forts

        Contenu:
        \(String(text.prefix(15000)))
        """

        let response = try await AIClient.send(prompt: prompt, settings: settings)
        return try parseJSON(response, as: CandidateInterviewDraft.self)
    }

    // MARK: - Text extraction

    /// Public access for transcript import
    func extractTextPublic(from url: URL) throws -> String {
        try extractText(from: url)
    }

    private func extractText(from url: URL) throws -> String {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pdf":
            return try extractTextFromPDF(url: url)
        case "pptx":
            return try extractTextFromZippedXML(url: url, xmlDir: "ppt/slides")
        case "xlsx":
            return try extractTextFromXLSX(url: url)
        case "xls":
            // Legacy .xls: try reading via strings command
            return try extractTextViaStrings(url: url)
        case "txt", "md", "csv", "text":
            return try String(contentsOf: url, encoding: .utf8)
        default:
            // Try reading as plain text
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    private func extractTextFromPDF(url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw IngestionError.cannotReadFile
        }
        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        return text
    }

    /// Copy a security-scoped URL to a temp file so external tools (unzip, strings) can access it.
    private func copyToTemp(url: URL) throws -> URL {
        let tempFile = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString + "." + url.pathExtension)
        try FileManager.default.copyItem(at: url, to: tempFile)
        return tempFile
    }

    /// Unzip an Office Open XML file and extract text from XML files in a given subdirectory.
    private func extractTextFromZippedXML(url: URL, xmlDir: String) throws -> String {
        // Copy to temp first — security-scoped URLs can't be read by /usr/bin/unzip
        let tempFile = try copyToTemp(url: url)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", tempFile.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            print("[AIIngestion] unzip failed with status \(process.terminationStatus) for \(url.lastPathComponent)")
            throw IngestionError.cannotReadFile
        }

        let targetDir = tempDir.appending(path: xmlDir)
        var allText = ""

        if let xmlFiles = try? FileManager.default.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: nil) {
            let sorted = xmlFiles.filter { $0.pathExtension == "xml" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for xmlFile in sorted {
                let xmlData = try Data(contentsOf: xmlFile)
                let xmlString = String(data: xmlData, encoding: .utf8) ?? ""
                let texts = extractXMLTextContent(from: xmlString)
                if !texts.isEmpty {
                    allText += texts.joined(separator: " ") + "\n"
                }
            }
        }

        return allText
    }

    /// Extract text from XLSX (Excel) files — reads shared strings + sheet data
    private func extractTextFromXLSX(url: URL) throws -> String {
        let tempFile = try copyToTemp(url: url)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", tempFile.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            print("[AIIngestion] unzip XLSX failed with status \(process.terminationStatus)")
            throw IngestionError.cannotReadFile
        }

        var allText = ""

        // Read shared strings (most cell text is stored here)
        let sharedStringsURL = tempDir.appending(path: "xl/sharedStrings.xml")
        if let data = try? Data(contentsOf: sharedStringsURL),
           let xml = String(data: data, encoding: .utf8) {
            let texts = extractXMLTextContent(from: xml)
            allText += texts.joined(separator: "\t") + "\n"
        }

        // Also read sheet XML files for inline strings and structure
        let sheetsDir = tempDir.appending(path: "xl/worksheets")
        if let sheetFiles = try? FileManager.default.contentsOfDirectory(at: sheetsDir, includingPropertiesForKeys: nil) {
            let sorted = sheetFiles.filter { $0.pathExtension == "xml" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for sheetFile in sorted {
                if let data = try? Data(contentsOf: sheetFile),
                   let xml = String(data: data, encoding: .utf8) {
                    let texts = extractXMLTextContent(from: xml)
                    if !texts.isEmpty {
                        allText += texts.joined(separator: "\t") + "\n"
                    }
                }
            }
        }

        return allText
    }

    /// Fallback: extract printable strings from binary files (legacy .xls, .doc, etc.)
    private func extractTextViaStrings(url: URL) throws -> String {
        let tempFile = try copyToTemp(url: url)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/strings")
        process.arguments = [tempFile.path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Filter out very short lines (binary noise)
        let filtered = output.components(separatedBy: "\n")
            .filter { $0.count > 3 }
            .joined(separator: "\n")

        guard !filtered.isEmpty else {
            throw IngestionError.cannotReadFile
        }
        return filtered
    }

    private func extractXMLTextContent(from xml: String) -> [String] {
        var results: [String] = []

        // Match multiple tag patterns: <a:t> (PPTX), <t> (XLSX), <t ...> (XLSX with attrs)
        let patterns: [(String, String)] = [
            ("<a:t>", "</a:t>"),       // PowerPoint
            ("<a:t ", "</a:t>"),       // PowerPoint with attributes
            ("<t>", "</t>"),           // Excel shared strings
            ("<t ", "</t>"),           // Excel with attributes (e.g. <t xml:space="preserve">)
        ]

        for (openTag, closeTag) in patterns {
            var searchRange = xml.startIndex..<xml.endIndex
            while let openRange = xml.range(of: openTag, range: searchRange) {
                // For tags with attributes, find the closing >
                let contentStart: String.Index
                if openTag.hasSuffix(">") {
                    contentStart = openRange.upperBound
                } else {
                    guard let closeBracket = xml.range(of: ">", range: openRange.upperBound..<xml.endIndex) else {
                        searchRange = openRange.upperBound..<xml.endIndex
                        continue
                    }
                    contentStart = closeBracket.upperBound
                }

                guard let closeRange = xml.range(of: closeTag, range: contentStart..<xml.endIndex) else {
                    break
                }

                let text = String(xml[contentStart..<closeRange.lowerBound])
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    results.append(trimmed)
                }
                searchRange = closeRange.upperBound..<xml.endIndex
            }
        }

        return results
    }

    // MARK: - AI API call

    private func callAI(text: String, fileName: String, settings: AppSettings) async throws -> ExtractedData {
        let prompt = buildPrompt(text: text, fileName: fileName)
        let response = try await AIClient.send(prompt: prompt, settings: settings)
        return try parseJSON(response)
    }

    private func buildPrompt(text: String, fileName: String) -> String {
        return """
        Analyse le contenu suivant extrait du fichier "\(fileName)" (dashboard projets / présentation / compte-rendu).

        Extrais les informations structurées au format JSON suivant. Sois exhaustif.

        {
          "projects": [
            {
              "code": "code projet (ex: P24_021) ou généré si absent",
              "name": "nom du projet",
              "domain": "domaine/entité",
              "phase": "Cadrage|Design|Build|Run",
              "status": "Green|Yellow|Red|Unknown",
              "riskLevel": "Critique|Élevé|Modéré|Faible|null",
              "riskDescription": "description du risque principal ou null",
              "keyPoints": ["point important 1", "point important 2"],
              "deliveryDate": "JJ/MM/AAAA ou null",
              "comment": "commentaires, faits marquants",
              "collaboratorNames": ["nom1", "nom2"]
            }
          ],
          "collaborators": [
            {
              "name": "Prénom Nom",
              "role": "rôle si mentionné ou null"
            }
          ],
          "summary": "résumé global en 2-3 phrases avec les points d'attention principaux"
        }

        Règles:
        - Extrais TOUS les projets mentionnés
        - Pour chaque personne mentionnée (chef de projet, responsable, architecte, etc.), ajoute-la dans collaborators
        - Le statut doit être Green, Yellow, Red ou Unknown
        - La phase doit être Cadrage, Design, Build ou Run
        - riskLevel: évalue le niveau de risque (Critique si blocage/alerte rouge, Élevé si retard/problème, Modéré si attention, Faible sinon)
        - riskDescription: décris le risque principal en une phrase
        - keyPoints: les 2-3 points les plus importants pour ce projet
        - Réponds UNIQUEMENT avec le JSON, sans texte avant ou après

        Contenu:
        \(String(text.prefix(15000)))
        """
    }

    // MARK: - JSON parsing

    private func parseJSON(_ raw: String) throws -> ExtractedData {
        try parseJSON(raw, as: ExtractedData.self)
    }

    private func parseJSON<T: Decodable>(_ raw: String, as type: T.Type) throws -> T {
        var jsonString = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences if present (```json ... ```)
        if jsonString.contains("```") {
            jsonString = jsonString
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let start = jsonString.range(of: "{"), let end = jsonString.range(of: "}", options: .backwards) {
            jsonString = String(jsonString[start.lowerBound..<end.upperBound])
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw IngestionError.parseError("Cannot convert to data")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[AIIngestion] JSON parse failed. Raw response (first 500 chars): \(String(raw.prefix(500)))")
            print("[AIIngestion] Extracted JSON (first 500 chars): \(String(jsonString.prefix(500)))")
            print("[AIIngestion] Decode error: \(error)")
            throw IngestionError.parseError("Reponse IA invalide: \(error.localizedDescription)\n\nDebut de la reponse: \(String(raw.prefix(200)))")
        }
    }

    // MARK: - Apply extracted data to SwiftData

    func applyExtractedData(_ extracted: ExtractedData, fileName: String, in context: ModelContext) -> (projects: [Project], collaborators: [Collaborator], interview: Interview) {
        // 1. Find or create "Autre" entity
        let autreEntity = findOrCreateEntity(name: "Autre", in: context)

        // 2. Create/update collaborators
        var collaboratorMap: [String: Collaborator] = [:]
        for ec in extracted.collaborators {
            let collab = findOrCreateCollaborator(name: ec.name, role: ec.role, in: context)
            collaboratorMap[ec.name.lowercased()] = collab
        }

        // 3. Create/update projects
        var createdProjects: [Project] = []
        for ep in extracted.projects {
            let project = findOrCreateProject(extracted: ep, defaultEntity: autreEntity, in: context)
            createdProjects.append(project)
        }

        // 4. Create import Interview
        let fileExt = (fileName as NSString).pathExtension.lowercased()
        let interviewType: InterviewType
        switch fileExt {
        case "pptx": interviewType = .importPPTX
        case "pdf": interviewType = .importPDF
        default: interviewType = .importPDF
        }

        let interview = Interview(
            date: Date(),
            notes: buildImportNotes(extracted: extracted, fileName: fileName),
            type: interviewType
        )
        interview.sourceFileName = fileName
        context.insert(interview)

        if let firstCollab = collaboratorMap.values.first {
            interview.collaborator = firstCollab
        }

        // 5. Create tasks for risks and key points
        for project in createdProjects {
            if let riskDesc = project.comment, !riskDesc.isEmpty {
                let task = ActionTask(title: "Suivi: \(project.name)")
                task.interview = interview
                task.project = project
                context.insert(task)
            }
        }

        do {
            try context.save()
            print("[AIIngestion] Data saved successfully")
        } catch {
            print("[AIIngestion] Save failed: \(error)")
        }

        return (createdProjects, Array(collaboratorMap.values), interview)
    }

    // MARK: - Helpers

    private func findOrCreateEntity(name: String, in context: ModelContext) -> Entity {
        // Normalize: title case ("SERVICE DELIVERY" → "Service Delivery")
        let normalized = name.localizedCapitalized

        // Case-insensitive lookup: fetch all and compare
        let descriptor = FetchDescriptor<Entity>()
        if let allEntities = try? context.fetch(descriptor) {
            if let existing = allEntities.first(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame || $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return existing
            }
        }

        let entity = Entity(name: normalized, summary: "")
        context.insert(entity)
        return entity
    }

    private func findOrCreateCollaborator(name: String, role: String?, in context: ModelContext) -> Collaborator {
        // Case-insensitive lookup
        let descriptor = FetchDescriptor<Collaborator>()
        if let allCollabs = try? context.fetch(descriptor) {
            if let existing = allCollabs.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return existing
            }
        }

        let collab = Collaborator(name: name, role: role ?? "Non spécifié")
        context.insert(collab)
        return collab
    }

    private func findOrCreateProject(extracted: ExtractedProject, defaultEntity: Entity, in context: ModelContext) -> Project {
        let code = extracted.code
        let resolvedEntity: Entity = {
            if let entityName = extracted.entityName, !entityName.isEmpty {
                return findOrCreateEntity(name: entityName, in: context)
            }
            return defaultEntity
        }()

        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.code == code })
        if let existing = try? context.fetch(descriptor).first {
            // Only update fields that are present in the extracted data — never overwrite with nil
            if !extracted.name.isEmpty && extracted.name != "Sans nom" { existing.name = extracted.name }
            if !extracted.domain.isEmpty { existing.domain = extracted.domain }
            if !extracted.phase.isEmpty { existing.phase = extracted.phase }
            if !extracted.status.isEmpty && extracted.status != "Unknown" { existing.status = extracted.status }
            if let comment = extracted.comment { existing.comment = comment }
            if let sponsor = extracted.sponsor, !sponsor.isEmpty { existing.sponsor = sponsor }
            if let projectType = extracted.projectType, !projectType.isEmpty { existing.projectType = projectType }
            if let days = extracted.plannedDays { existing.plannedDays = days }
            if let deadline = extracted.designEndDeadline { existing.designEndDeadline = parseDate(deadline) }
            existing.entity = resolvedEntity
            print("[AIIngestion] Updated existing project: \(code) — \(existing.name)")
            return existing
        }

        let project = Project(
            code: extracted.code,
            name: extracted.name,
            domain: extracted.domain,
            sponsor: extracted.sponsor ?? "",
            projectType: extracted.projectType ?? "Métier",
            phase: extracted.phase,
            status: extracted.status
        )
        if let comment = extracted.comment { project.comment = comment }
        if let days = extracted.plannedDays { project.plannedDays = days }
        if let deadline = extracted.designEndDeadline { project.designEndDeadline = parseDate(deadline) }
        project.entity = resolvedEntity
        context.insert(project)
        print("[AIIngestion] Created new project: \(code) — \(extracted.name)")
        return project
    }

    /// Parses date strings in common formats (dd/MM/yyyy, yyyy-MM-dd, etc.)
    private func parseDate(_ string: String) -> Date? {
        let formatters: [DateFormatter] = {
            let f1 = DateFormatter(); f1.dateFormat = "dd/MM/yyyy"
            let f2 = DateFormatter(); f2.dateFormat = "yyyy-MM-dd"
            let f3 = DateFormatter(); f3.dateFormat = "dd-MM-yyyy"
            return [f1, f2, f3]
        }()
        for fmt in formatters {
            if let date = fmt.date(from: string) { return date }
        }
        return nil
    }

    private func buildImportNotes(extracted: ExtractedData, fileName: String) -> String {
        var notes = "## Import: \(fileName)\n"
        notes += "Date: \(Date().formatted(date: .long, time: .shortened))\n\n"

        if let summary = extracted.summary {
            notes += "### Résumé\n\(summary)\n\n"
        }

        notes += "### Projets extraits (\(extracted.projects.count))\n"
        for p in extracted.projects {
            notes += "- **\(p.code)** — \(p.name) [\(p.phase)] (\(p.status))"
            if let risk = p.riskLevel {
                notes += " ⚠️ Risque: \(risk)"
            }
            notes += "\n"
            if let riskDesc = p.riskDescription {
                notes += "  Risque: _\(riskDesc)_\n"
            }
            if let keyPoints = p.keyPoints, !keyPoints.isEmpty {
                for kp in keyPoints {
                    notes += "  - \(kp)\n"
                }
            }
            if let comment = p.comment {
                notes += "  _\(comment)_\n"
            }
        }

        if !extracted.collaborators.isEmpty {
            notes += "\n### Collaborateurs identifiés (\(extracted.collaborators.count))\n"
            for c in extracted.collaborators {
                notes += "- \(c.name)"
                if let role = c.role { notes += " — \(role)" }
                notes += "\n"
            }
        }

        return notes
    }
}

// MARK: - Errors

enum IngestionError: LocalizedError {
    case emptyFile
    case cannotReadFile
    case noAPIKey
    case invalidEndpoint
    case networkError(String)
    case apiError(Int, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "Le fichier est vide ou illisible."
        case .cannotReadFile: return "Impossible de lire le fichier."
        case .noAPIKey: return "Aucune clé API configurée. Allez dans Paramètres."
        case .invalidEndpoint: return "L'endpoint API est invalide."
        case .networkError(let msg): return "Erreur réseau: \(msg)"
        case .apiError(let code, let body): return "Erreur API (\(code)): \(String(body.prefix(200)))"
        case .parseError(let msg): return "Erreur de parsing: \(msg)"
        }
    }
}
