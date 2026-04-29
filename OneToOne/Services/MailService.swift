import Foundation
import AppKit
import os

private let mailLog = Logger(subsystem: "com.onetoone.app", category: "mail")

// MARK: - MailSnippet

struct MailSnippet: Identifiable, Hashable {
    var id: String { "\(accountName)|\(mailbox)|\(messageId)" }
    let messageId: String
    let accountName: String
    let mailbox: String
    let subject: String
    let sender: String
    let dateReceived: Date
    let preview: String
    /// Corps chargé à la demande (fetchBody).
    var body: String?
}

struct MailboxRef: Identifiable, Hashable {
    var id: String { "\(accountName)|\(mailboxName)" }
    let accountName: String
    let mailboxName: String

    var displayName: String {
        "\(accountName) / \(mailboxName)"
    }
}

struct MailAttachmentFile: Identifiable, Hashable {
    var id: String { path }
    let fileName: String
    let path: String
}

// MARK: - MailService (AppleScript → Apple Mail)

/// Accès aux mails de l'utilisateur via AppleScript sur l'application Mail.
///
/// Nécessite :
///   - Mail configurée avec au moins un compte
///   - Automation permission : `Réglages Système → Confidentialité → Automation`
///     → autoriser OneToOne à contrôler Mail
///
/// Les appels sont exécutés off-main (AppleScript peut bloquer ~secondes).
/// L'AppleScript retourne un texte semi-structuré qu'on parse.
enum MailService {

    enum MailError: LocalizedError {
        case scriptFailed(String)
        case mailNotAvailable

        var errorDescription: String? {
            switch self {
            case .scriptFailed(let d): return "AppleScript a échoué : \(d)"
            case .mailNotAvailable:    return "L'application Mail n'est pas disponible."
            }
        }
    }

    // MARK: - List recent messages

    /// Liste les N messages les plus récents de la boîte de réception, tous comptes.
    /// - Parameters:
    ///   - limit: nombre max de messages (défaut 50)
    ///   - search: filtre optionnel (match sur subject OU sender OU contenu)
    static func listRecent(limit: Int = 500, search: String = "", mailbox: MailboxRef? = nil) async throws -> [MailSnippet] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        let scriptSrc = buildListScript(limit: limit, search: trimmed, mailbox: mailbox)
        let raw = try await runAppleScript(scriptSrc)
        return parseList(raw)
    }

    static func listMailboxes() async throws -> [MailboxRef] {
        let sep = "|⎯|"
        let rowEnd = "‡"
        let script = """
        tell application "Mail"
            set output to ""
            repeat with acct in accounts
                set acctName to name of acct
                repeat with mbx in mailboxes of acct
                    try
                        set mbxName to name of mbx
                        set output to output & acctName & "\(sep)" & mbxName & "\(rowEnd)"
                    end try
                end repeat
            end repeat
            return output
        end tell
        """
        let raw = try await runAppleScript(script)
        return raw.components(separatedBy: rowEnd)
            .compactMap { row -> MailboxRef? in
                let fields = row.components(separatedBy: sep)
                guard fields.count >= 2 else { return nil }
                return MailboxRef(accountName: fields[0], mailboxName: fields[1])
            }
            .filter { mailbox in
                let lowered = mailbox.mailboxName.lowercased()
                return lowered == "inbox" || lowered == "boîte de réception" || lowered == "boite de reception"
            }
    }

    /// Charge le corps complet d'un message.
    static func fetchBody(messageId: String, accountName: String, mailbox: String) async throws -> String {
        let script = """
        tell application "Mail"
            set theBody to ""
            repeat with acct in accounts
                if name of acct is "\(escape(accountName))" then
                    repeat with mbx in mailboxes of acct
                        if name of mbx is "\(escape(mailbox))" then
                            try
                                set msgs to (messages of mbx whose message id is "\(escape(messageId))")
                                if (count of msgs) > 0 then
                                    set theBody to content of (item 1 of msgs)
                                    exit repeat
                                end if
                            end try
                        end if
                    end repeat
                end if
                if theBody is not "" then exit repeat
            end repeat
            return theBody
        end tell
        """
        return try await runAppleScript(script)
    }

    static func fetchBody(messageId: String, mailbox: String) async throws -> String {
        let script = """
        tell application "Mail"
            set theBody to ""
            repeat with acct in accounts
                try
                    set inboxMailbox to inbox of acct
                    set msgs to (messages of inboxMailbox whose message id is "\(escape(messageId))")
                    if (count of msgs) > 0 then
                        set theBody to content of (item 1 of msgs)
                        exit repeat
                    end if
                end try
                if theBody is not "" then exit repeat
            end repeat
            return theBody
        end tell
        """
        return try await runAppleScript(script)
    }

    static func saveAttachments(messageId: String, accountName: String, mailbox: String) async throws -> [MailAttachmentFile] {
        let directory = mailAttachmentsDirectory(messageId: messageId)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let script = """
        tell application "Mail"
            set output to ""
            set sep to "|⎯|"
            set rowEnd to "‡"
            set destFolder to POSIX file "\(escape(directory.path))"
            repeat with acct in accounts
                if name of acct is "\(escape(accountName))" then
                    repeat with mbx in mailboxes of acct
                        if name of mbx is "\(escape(mailbox))" then
                            try
                                set msgs to (messages of mbx whose message id is "\(escape(messageId))")
                                if (count of msgs) > 0 then
                                    set m to item 1 of msgs
                                    repeat with att in mail attachments of m
                                        try
                                            set attName to name of att
                                            set destAlias to (destFolder as alias)
                                            save att in destAlias
                                            set output to output & attName & sep & "\(escape(directory.path))/" & attName & rowEnd
                                        end try
                                    end repeat
                                    exit repeat
                                end if
                            end try
                        end if
                    end repeat
                end if
                if output is not "" then exit repeat
            end repeat
            return output
        end tell
        """

        let raw = try await runAppleScript(script)
        return parseAttachmentFiles(raw)
    }

    // MARK: - AppleScript plumbing

    private static func buildListScript(limit: Int, search: String, mailbox: MailboxRef?) -> String {
        // Séparateurs non-ambigus : |⎯|
        let sep = "|⎯|"
        let rowEnd = "‡"
        let escapedSearch = escape(search)
        let accountFilter = mailbox.map { #"name of acct is "\#(escape($0.accountName))""# } ?? "true"
        let mailboxFilter = mailbox.map { #"name of mbx is "\#(escape($0.mailboxName))""# }
            ?? #"((name of mbx) is "INBOX" or (name of mbx) is "Boîte de réception" or (name of mbx) is "Boite de reception")"#

        return """
        tell application "Mail"
            set output to ""
            set theLimit to \(limit)
            set theSearch to "\(escapedSearch)"
            set collected to 0
            repeat with acct in accounts
                if \(accountFilter) then
                    repeat with mbx in mailboxes of acct
                        if \(mailboxFilter) then
                            try
                                set theMsgs to messages of mbx
                                set n to count of theMsgs
                                set i to 1
                                repeat while i <= n and collected < theLimit
                                    try
                                        set m to item i of theMsgs
                                        set subj to subject of m
                                        set snd to (sender of m) as string
                                        set dt to (date received of m) as string
                                        set mid to message id of m
                                        set acctName to name of acct
                                        set mbxName to name of mbx
                                        set prev to ""
                                        if theSearch is not "" then
                                            try
                                                set bodyStr to content of m
                                                if (length of bodyStr) > 400 then
                                                    set prev to text 1 thru 400 of bodyStr
                                                else
                                                    set prev to bodyStr
                                                end if
                                            end try
                                        else
                                            try
                                                set prev to (excerpt of m) as string
                                            on error
                                                set prev to ""
                                            end try
                                        end if

                                        set include to true
                                        if theSearch is not "" then
                                            set include to false
                                            if subj contains theSearch then set include to true
                                            if snd contains theSearch then set include to true
                                            if prev contains theSearch then set include to true
                                        end if

                                        if include then
                                            set output to output & mid & "\(sep)" & acctName & "\(sep)" & mbxName & "\(sep)" & subj & "\(sep)" & snd & "\(sep)" & dt & "\(sep)" & prev & "\(rowEnd)"
                                            set collected to collected + 1
                                        end if
                                    end try
                                    set i to i + 1
                                end repeat
                            end try
                            if collected >= theLimit then exit repeat
                        end if
                    end repeat
                    if collected >= theLimit then exit repeat
                end if
            end repeat
            return output
        end tell
        """
    }

    private static func mailAttachmentsDirectory(messageId: String) -> URL {
        let safeID = messageId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
        return URL.applicationSupportDirectory
            .appending(path: "OneToOne", directoryHint: .isDirectory)
            .appending(path: "mail-attachments", directoryHint: .isDirectory)
            .appending(path: safeID, directoryHint: .isDirectory)
    }

    private static func parseAttachmentFiles(_ raw: String) -> [MailAttachmentFile] {
        let sep = "|⎯|"
        let rowEnd = "‡"
        return raw.components(separatedBy: rowEnd).compactMap { row in
            let fields = row.components(separatedBy: sep)
            guard fields.count >= 2 else { return nil }
            return MailAttachmentFile(fileName: fields[0], path: fields[1])
        }
    }

    private static func parseList(_ raw: String) -> [MailSnippet] {
        let sep = "|⎯|"
        let rowEnd = "‡"
        let rows = raw.components(separatedBy: rowEnd).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return rows.compactMap { row -> MailSnippet? in
            let fields = row.components(separatedBy: sep)
            guard fields.count >= 7 else { return nil }
            let dateStr = fields[5].trimmingCharacters(in: .whitespaces)
            let date = parseAppleDate(dateStr) ?? Date()
            return MailSnippet(
                messageId: fields[0],
                accountName: fields[1],
                mailbox: fields[2],
                subject: fields[3],
                sender: fields[4],
                dateReceived: date,
                preview: fields[6],
                body: nil
            )
        }
    }

    private static func parseAppleDate(_ s: String) -> Date? {
        // Format renvoyé par AppleScript (dépend de la locale système).
        // On essaie plusieurs formats courants.
        let formats = [
            "EEEE d MMMM yyyy 'à' HH:mm:ss",  // fr
            "EEEE, MMMM d, yyyy 'at' h:mm:ss a",
            "d MMMM yyyy 'à' HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss Z"
        ]
        let fr = Locale(identifier: "fr_FR")
        let en = Locale(identifier: "en_US")
        for f in formats {
            for loc in [fr, en] {
                let df = DateFormatter()
                df.locale = loc
                df.dateFormat = f
                if let d = df.date(from: s) { return d }
            }
        }
        return nil
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAppleScript(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let script = NSAppleScript(source: source) else {
                    cont.resume(throwing: MailError.scriptFailed("NSAppleScript init échoué"))
                    return
                }
                var errorDict: NSDictionary?
                let result = script.executeAndReturnError(&errorDict)
                if let err = errorDict {
                    let msg = err[NSAppleScript.errorMessage] as? String ?? "\(err)"
                    mailLog.error("runAppleScript: \(msg, privacy: .public)")
                    cont.resume(throwing: MailError.scriptFailed(msg))
                    return
                }
                let text = result.stringValue ?? ""
                cont.resume(returning: text)
            }
        }
    }
}
