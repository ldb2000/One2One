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

    // MARK: - Block model

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case ordered(index: Int, text: String)
        case code(language: String?, body: String)
        case quote(String)
        case rule
        case spacer
    }

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
        }
    }

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
