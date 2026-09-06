import SwiftUI

/// Vue qui rend du markdown light (headings, listes, code blocks fenced,
/// quotes, séparateurs) en SwiftUI. L'inline (`**`, `*`, `` ` ``, liens)
/// est délégué à `AttributedString(markdown:)`.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Testing hooks (`Tests/MarkdownTextTableTests.swift`)

    /// Étiquette de bloc pour vérifier l'ordre/la nature des blocs parsés sans dépendre du
    /// rendu SwiftUI (ex. "paragraph", "table"). Réservé aux tests.
    func blockKindsForTesting() -> [String] {
        blocks().map { block in
            switch block {
            case .heading: return "heading"
            case .paragraph: return "paragraph"
            case .bullet: return "bullet"
            case .ordered: return "ordered"
            case .code: return "code"
            case .quote: return "quote"
            case .rule: return "rule"
            case .spacer: return "spacer"
            case .table: return "table"
            }
        }
    }

    /// Tableaux parsés (headers, rows, alignements en chaîne "left"/"center"/"right"), exposés
    /// sans passer par le rendu SwiftUI. Réservé aux tests.
    func parsedTablesForTesting() -> [(headers: [String], rows: [[String]], alignments: [String])] {
        blocks().compactMap { block in
            guard case .table(let headers, let rows, let alignments) = block else { return nil }
            let alignmentLabels = alignments.map { alignment -> String in
                switch alignment {
                case .left: return "left"
                case .center: return "center"
                case .right: return "right"
                }
            }
            return (headers, rows, alignmentLabels)
        }
    }

    // MARK: - Block model

    /// Bloc markdown reconnu par le parseur ligne à ligne.
    private enum Block {
        /// Titre `#`…`######` (niveau 1 à 6).
        case heading(level: Int, text: String)
        case paragraph(String)
        /// Élément de liste à puces (`-`, `*`, `+`).
        case bullet(String)
        /// Élément de liste ordonnée ; `index` est le compteur recalculé en interne, pas le numéro source.
        case ordered(index: Int, text: String)
        /// Bloc de code délimité par ``` ``` `` ; `language` issu de la ligne d'ouverture si présent.
        case code(language: String?, body: String)
        case quote(String)
        /// Règle horizontale (`---`, `***`, `___`).
        case rule
        /// Ligne vide → espacement vertical.
        case spacer
        /// Tableau GFM : ligne d'en-tête + ligne de séparateurs + lignes de données.
        case table(headers: [String], rows: [[String]], alignments: [Alignment])
    }

    /// Alignement d'une colonne de tableau, déduit de la ligne de séparateurs (`:---`/`:---:`/`---:`).
    private enum Alignment {
        case left, center, right

        var frameAlignment: SwiftUI.Alignment {
            switch self {
            case .left: return .leading
            case .center: return .center
            case .right: return .trailing
            }
        }

        var textAlignment: TextAlignment {
            switch self {
            case .left: return .leading
            case .center: return .center
            case .right: return .trailing
            }
        }
    }

    /// Découpe le markdown en blocs en parcourant les lignes (normalise les fins de ligne CRLF).
    private func blocks() -> [Block] {
        var out: [Block] = []
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var i = 0
        var orderedCounter = 0
        var inOrdered = false
        while i < lines.count {
            let raw = lines[i]
            let line = raw

            // Fenced code block ```
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let lang = String(line.trimmingCharacters(in: .whitespaces).dropFirst(3))
                var body: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    body.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }  // skip closing fence
                out.append(.code(language: lang.isEmpty ? nil : lang, body: body.joined(separator: "\n")))
                inOrdered = false
                continue
            }

            // Empty line → spacer
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                out.append(.spacer)
                inOrdered = false
                i += 1
                continue
            }

            // Horizontal rule
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                out.append(.rule)
                inOrdered = false
                i += 1
                continue
            }

            // Table GFM : ligne d'en-tête (contient `|`) suivie d'une ligne de séparateurs.
            if trimmed.contains("|"), i + 1 < lines.count, isTableSeparatorLine(lines[i + 1]) {
                let headers = tableRowCells(line)
                let alignments = tableAlignments(from: lines[i + 1])
                var rows: [[String]] = []
                var j = i + 2
                while j < lines.count {
                    let rowTrimmed = lines[j].trimmingCharacters(in: .whitespaces)
                    guard !rowTrimmed.isEmpty, lines[j].contains("|") else { break }
                    rows.append(tableRowCells(lines[j]))
                    j += 1
                }
                out.append(.table(headers: headers, rows: rows, alignments: alignments))
                i = j
                inOrdered = false
                continue
            }

            // Heading: # to ######
            if let hashes = trimmed.prefix(while: { $0 == "#" }).count as Int?, hashes > 0, hashes <= 6,
               trimmed.count > hashes, trimmed[trimmed.index(trimmed.startIndex, offsetBy: hashes)] == " " {
                let text = String(trimmed.dropFirst(hashes + 1))
                out.append(.heading(level: hashes, text: text))
                inOrdered = false
                i += 1
                continue
            }

            // Quote >
            if trimmed.hasPrefix("> ") {
                out.append(.quote(String(trimmed.dropFirst(2))))
                inOrdered = false
                i += 1
                continue
            }

            // Bullet - * +
            if let m = trimmed.first, "-*+".contains(m), trimmed.count > 2,
               trimmed[trimmed.index(after: trimmed.startIndex)] == " " {
                out.append(.bullet(String(trimmed.dropFirst(2))))
                inOrdered = false
                i += 1
                continue
            }

            // Ordered "1. " or "1) "
            if let dot = trimmed.firstIndex(where: { $0 == "." || $0 == ")" }),
               trimmed.distance(from: trimmed.startIndex, to: dot) > 0,
               trimmed[trimmed.startIndex..<dot].allSatisfy(\.isNumber),
               trimmed.index(after: dot) < trimmed.endIndex,
               trimmed[trimmed.index(after: dot)] == " " {
                if !inOrdered { orderedCounter = 0; inOrdered = true }
                orderedCounter += 1
                let text = String(trimmed[trimmed.index(dot, offsetBy: 2)...])
                out.append(.ordered(index: orderedCounter, text: text))
                i += 1
                continue
            } else {
                inOrdered = false
            }

            // Default paragraph
            out.append(.paragraph(line))
            i += 1
        }
        return out
    }

    // MARK: - Block rendering

    /// Rend un bloc en vue SwiftUI ; l'inline (`**`, `*`, `` ` ``, liens) est délégué à `inlineText(_:)`.
    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(for: level))
                .padding(.top, level <= 2 ? 4 : 2)
        case .paragraph(let text):
            inlineText(text)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundColor(.secondary)
                inlineText(text)
            }
        case .ordered(let idx, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("\(idx).").foregroundColor(.secondary).monospacedDigit()
                inlineText(text)
            }
        case .code(_, let body):
            Text(body)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(6)
                .textSelection(.enabled)
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                inlineText(text).foregroundColor(.secondary)
            }
        case .rule:
            Divider().padding(.vertical, 2)
        case .spacer:
            Spacer().frame(height: 2)
        case .table(let headers, let rows, let alignments):
            tableView(headers: headers, rows: rows, alignments: alignments)
        }
    }

    // MARK: - Table parsing helpers

    /// Découpe une ligne de tableau en cellules trimmées, en retirant un `|` de tête et/ou
    /// de fin s'il est présent (les deux formes GFM, avec ou sans pipes de bordure, sont acceptées).
    private func tableRowCells(_ line: String) -> [String] {
        var body = line.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        return body.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Vrai si `line` est une ligne de séparateurs de tableau valide (`|---|:--:|--:|`, avec ou
    /// sans pipes de bordure) : chaque cellule ne contient que des tirets, avec `:` optionnels
    /// aux extrémités pour l'alignement.
    private func isTableSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }
        let cells = tableRowCells(trimmed)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            guard !cell.isEmpty else { return false }
            var body = cell
            if body.hasPrefix(":") { body.removeFirst() }
            if body.hasSuffix(":") { body.removeLast() }
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

    /// Déduit l'alignement de chaque colonne depuis la ligne de séparateurs ;
    /// aucun `:` → alignement gauche par défaut.
    private func tableAlignments(from separatorLine: String) -> [Alignment] {
        tableRowCells(separatorLine).map { cell -> Alignment in
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            if left && right { return .center }
            if right { return .right }
            return .left
        }
    }

    // MARK: - Table rendering

    @ViewBuilder
    private func tableView(headers: [String], rows: [[String]], alignments: [Alignment]) -> some View {
        let columnCount = max(headers.count, alignments.count)
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<columnCount, id: \.self) { col in
                        tableCell(col < headers.count ? headers[col] : "", alignment: alignment(at: col, in: alignments), isHeader: true)
                    }
                }
                .background(Color.accentColor.opacity(0.08))

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1)
                    HStack(spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { col in
                            tableCell(col < row.count ? row[col] : "", alignment: alignment(at: col, in: alignments), isHeader: false)
                        }
                    }
                    .background(rowIndex % 2 == 1 ? Color.gray.opacity(0.04) : Color.clear)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private func alignment(at index: Int, in alignments: [Alignment]) -> Alignment {
        index < alignments.count ? alignments[index] : .left
    }

    @ViewBuilder
    private func tableCell(_ text: String, alignment: Alignment, isHeader: Bool) -> some View {
        Group {
            if isHeader {
                inlineText(text).fontWeight(.semibold)
            } else {
                inlineText(text)
            }
        }
        .multilineTextAlignment(alignment.textAlignment)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 80, maxWidth: .infinity, alignment: alignment.frameAlignment)
        .padding(8)
    }

    /// Police associée à un niveau de titre (1 = title2 gras … défaut = subheadline semibold).
    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.semibold)
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }

    @ViewBuilder
    private func inlineText(_ text: String) -> some View {
        if let attr = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attr).textSelection(.enabled)
        } else {
            Text(text).textSelection(.enabled)
        }
    }
}
