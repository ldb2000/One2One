import Testing
import Foundation
@testable import OneToOne

@Suite("MailService — script de scan automatique")
struct MailAutoScanScriptTests {

    private let mailbox = MailboxRef(accountName: "Pro \"April\"", mailboxName: "INBOX")

    @Test("Le script filtre sur read status et le cutoff en jours")
    func filtresLusEtCutoff() {
        let script = MailService.buildAutoScanScript(limit: 200, lookbackDays: 90, mailbox: mailbox)
        #expect(script.contains("read status of m) is true"))
        #expect(script.contains("set theCutoff to (current date) - (90 * days)"))
        #expect(script.contains("set theLimit to 200"))
        #expect(script.contains("exit repeat"))
    }

    @Test("Compte et boîte ciblés exactement, avec échappement des guillemets")
    func cibleCompteEtBoite() {
        let script = MailService.buildAutoScanScript(limit: 10, lookbackDays: 30, mailbox: mailbox)
        #expect(script.contains(#"name of acct is "Pro \"April\"""#))
        #expect(script.contains(#"name of mbx is "INBOX""#))
    }

    @Test("Le script émet les 7 champs attendus par parseList")
    func formatDeSortie() {
        let script = MailService.buildAutoScanScript(limit: 10, lookbackDays: 30, mailbox: mailbox)
        // même protocole que buildListScript : messageId, compte, boîte, sujet,
        // expéditeur, date, aperçu — séparés par |⎯| et terminés par ‡
        #expect(script.contains("|⎯|"))
        #expect(script.contains("‡"))
        #expect(script.contains("excerpt of m"))
    }
}
