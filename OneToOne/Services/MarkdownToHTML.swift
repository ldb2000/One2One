import Foundation
import AppKit

enum MarkdownToHTML {
    static func render(_ markdown: String) -> String {
        var html = markdown
        
        // Échapper les caractères HTML de base
        html = html.replacingOccurrences(of: "&", with: "&amp;")
        html = html.replacingOccurrences(of: "<", with: "&lt;")
        html = html.replacingOccurrences(of: ">", with: "&gt;")
        
        // Traitement ligne par ligne pour les blocs
        let lines = html.components(separatedBy: .newlines)
        var resultLines: [String] = []
        var inList = false
        
        for line in lines {
            let processedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Titres
            if processedLine.hasPrefix("### ") {
                if inList { resultLines.append("</ul>"); inList = false }
                let content = processedLine.dropFirst(4)
                resultLines.append("<h3 style=\"font-size: 16px; margin-top: 16px; margin-bottom: 8px; border-bottom: 1px solid #eee; padding-bottom: 4px;\">\(content)</h3>")
                continue
            }
            if processedLine.hasPrefix("## ") {
                if inList { resultLines.append("</ul>"); inList = false }
                let content = processedLine.dropFirst(3)
                resultLines.append("<h2 style=\"font-size: 18px; margin-top: 20px; margin-bottom: 10px; border-bottom: 2px solid #ddd; padding-bottom: 2px;\">\(content)</h2>")
                continue
            }
            if processedLine.hasPrefix("# ") {
                if inList { resultLines.append("</ul>"); inList = false }
                let content = processedLine.dropFirst(2)
                resultLines.append("<h1 style=\"font-size: 24px; margin-bottom: 16px; color: #d71920;\">\(content)</h1>")
                continue
            }
            
            // Listes à puces
            if processedLine.hasPrefix("- ") || processedLine.hasPrefix("* ") {
                if !inList { resultLines.append("<ul style=\"padding-left: 20px; margin-bottom: 12px;\">"); inList = true }
                let content = processInline(String(processedLine.dropFirst(2)))
                resultLines.append("<li style=\"margin-bottom: 4px;\">\(content)</li>")
                continue
            }
            
            // Ligne vide
            if processedLine.isEmpty {
                if inList { resultLines.append("</ul>"); inList = false }
                resultLines.append("<br/>")
                continue
            }
            
            // Paragraphe normal
            if inList { resultLines.append("</ul>"); inList = false }
            resultLines.append("<p style=\"margin-bottom: 10px; line-height: 1.5;\">\(processInline(processedLine))</p>")
        }
        
        if inList { resultLines.append("</ul>") }
        
        let finalBody = resultLines.joined(separator: "\n")
        
        return """
        <html>
        <head><meta charset="utf-8"></head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif; font-size: 14px; color: #333; max-width: 800px; margin: 20px auto; padding: 0 20px;">
        \(finalBody)
        </body>
        </html>
        """
    }
    
    private static func processInline(_ text: String) -> String {
        var out = text
        
        // Gras **text**
        let boldRegex = try? NSRegularExpression(pattern: "\\*\\*(.*?)\\*\\*", options: [])
        out = boldRegex?.stringByReplacingMatches(in: out, options: [], range: NSRange(location: 0, length: out.utf16.count), withTemplate: "<strong>$1</strong>") ?? out
        
        // Italique *text*
        let italicRegex = try? NSRegularExpression(pattern: "\\*(.*?)\\*", options: [])
        out = italicRegex?.stringByReplacingMatches(in: out, options: [], range: NSRange(location: 0, length: out.utf16.count), withTemplate: "<em>$1</em>") ?? out
        
        return out
    }
}
