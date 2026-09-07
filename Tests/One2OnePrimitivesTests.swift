import Testing
import SwiftUI
@testable import OneToOne

/// Les primitives de la refonte portent chacune une règle de la spec §1.2 :
/// « timecode toujours mm:ss, largeur fixe », « ＋ assigner en accent/action,
/// renseignée en accent/ok », « pile d'avatars 19 px, chevauchement −6, max 6
/// puis +n ».
///
/// Une vue SwiftUI ne se teste pas sans session graphique. Ce fichier teste donc
/// la **règle**, extraite en fonction pure à côté de la vue qui l'applique — ce
/// qui est de toute façon la bonne façon de l'écrire.
@Suite("Primitives de la refonte — leurs règles pures")
struct One2OnePrimitivesTests {

    // MARK: - Timecode

    @Test("Un timecode est toujours mm:ss, sur deux chiffres chacun")
    func timecodeIsAlwaysMinutesSeconds() {
        #expect(TimecodeLabel.format(0) == "00:00")
        #expect(TimecodeLabel.format(9) == "00:09")
        #expect(TimecodeLabel.format(252) == "04:12")
        #expect(TimecodeLabel.format(1404) == "23:24")
    }

    @Test("Au-delà d'une heure, les minutes débordent — jamais de hh:mm:ss")
    func timecodeOverflowsIntoMinutes() {
        // La spec §1.2 dit « toujours mm:ss » : une réunion de 1 h 02 s'écrit
        // 62:xx. Basculer en hh:mm:ss changerait la largeur de la colonne, que
        // la conception veut justement fixe.
        #expect(TimecodeLabel.format(3723) == "62:03")
    }

    @Test("Un timecode négatif ou non fini se lit 00:00 plutôt que de produire un absurde")
    func timecodeClampsDegenerateValues() {
        #expect(TimecodeLabel.format(-1) == "00:00")
        #expect(TimecodeLabel.format(.nan) == "00:00")
        #expect(TimecodeLabel.format(.infinity) == "00:00")
    }

    @Test("Les secondes fractionnaires sont tronquées, pas arrondies")
    func timecodeTruncates() {
        // 04:12,9 est encore 04:12 : arrondir ferait apparaître un timecode que
        // la tête de lecture n'a pas encore atteint.
        #expect(TimecodeLabel.format(252.9) == "04:12")
    }

    // MARK: - Pilule d'invite

    @Test("Une pilule d'invite non renseignée s'affiche en accent/action")
    func invitePillInvitesInAction() {
        #expect(InvitePill.Etat.invite.encre == One2OneToken.actionInk)
        #expect(InvitePill.Etat.invite.fond == One2OneToken.actionBg)
    }

    @Test("Une pilule d'invite renseignée passe en accent/ok")
    func invitePillFilledIsOk() {
        #expect(InvitePill.Etat.renseignee.encre == One2OneToken.okDeep)
        #expect(InvitePill.Etat.renseignee.fond == One2OneToken.okBg)
    }

    @Test("Une pilule d'invite neutre ne réclame rien : encre ink/3 sur surface/alt")
    func invitePillNeutralIsQuiet() {
        #expect(InvitePill.Etat.neutre.encre == One2OneToken.ink3)
        #expect(InvitePill.Etat.neutre.fond == One2OneToken.surfaceAlt)
    }

    /// Les pilules font 10–10,5 px (spec §1.2) : elles tombent sous le seuil de
    /// 12 px et doivent atteindre 4,5:1.
    ///
    /// Sauf `.renseignee`, qui emploie `ok/deep` sur `ok/bg` — le meilleur
    /// couple que la table offre pour `accent/ok`, mesuré à 4,43:1. Cf.
    /// `One2OneTokensTests.okDeepOnOkBackgroundIsJustBelowThreshold` : c'est un
    /// écart de la table, pas de la primitive, et la capture 1a montre bien du
    /// vert sur vert clair pour une action assignée.
    @Test("Chaque état de pilule d'invite reste lisible sur son propre fond",
          arguments: [
            (InvitePill.Etat.invite, 4.5),
            (InvitePill.Etat.renseignee, 4.4),
            (InvitePill.Etat.neutre, 4.5),
          ])
    func invitePillStatesAreReadable(cas: (InvitePill.Etat, Double)) throws {
        let (etat, minimum) = cas
        let ratio = try #require(ContrastRatio.ratio(etat.encre, etat.fond))
        #expect(ratio >= minimum, "\(etat) : \(String(format: "%.2f", ratio)):1")
    }

    /// Même règle, même exception pour le ton `ok`.
    @Test("Chaque ton de chip reste lisible sur son propre fond",
          arguments: ChipTon.allCases)
    func chipTonesAreReadable(ton: ChipTon) throws {
        let minimum = ton == .ok ? 4.4 : 4.5
        let ratio = try #require(ContrastRatio.ratio(ton.encre, ton.fond))
        #expect(ratio >= minimum, "\(ton) : \(String(format: "%.2f", ratio)):1")
    }

    // MARK: - Pile d'avatars

    @Test("Jusqu'à six participants, la pile les montre tous et n'affiche pas de surplus")
    func avatarStackShowsUpToSix() {
        let noms = ["Patrice Y", "Nicolas L", "Claire-Amélie P", "Laurent S", "Camille A", "Loïc D"]
        let mise = AvatarStack.layout(noms: noms, maxVisibles: 6)
        #expect(mise.visibles.count == 6)
        #expect(mise.surplus == 0)
    }

    @Test("Au-delà de six, la pile en montre six et compte le reste")
    func avatarStackOverflows() {
        let noms = (1...9).map { "Participant \($0)" }
        let mise = AvatarStack.layout(noms: noms, maxVisibles: 6)
        #expect(mise.visibles.count == 6)
        #expect(mise.surplus == 3)
        #expect(mise.visibles.first == "Participant 1")
        #expect(mise.visibles.last == "Participant 6")
    }

    @Test("Une pile vide n'affiche ni avatar ni « +0 »")
    func avatarStackEmpty() {
        let mise = AvatarStack.layout(noms: [], maxVisibles: 6)
        #expect(mise.visibles.isEmpty)
        #expect(mise.surplus == 0)
    }

    @Test("La géométrie de la pile est celle de la conception : 19 px, chevauchement −6")
    func avatarStackGeometry() {
        #expect(AvatarStack.diametre == 19)
        #expect(AvatarStack.chevauchement == -6)
    }

    // MARK: - Barre de progression

    @Test("Une progression est bornée à 0…1")
    func progressBarClamps() {
        #expect(ProgressBar.clamp(0.5) == 0.5)
        #expect(ProgressBar.clamp(-3) == 0)
        #expect(ProgressBar.clamp(1.4) == 1)
    }

    @Test("Une progression indéfinie vaut zéro plutôt qu'une barre de largeur absurde")
    func progressBarHandlesNaN() {
        // 3 actions closes sur 0 action produit `nan` : la barre doit rester
        // vide, pas disparaître ni occuper toute la carte.
        #expect(ProgressBar.clamp(.nan) == 0)
        #expect(ProgressBar.clamp(.infinity) == 1)
    }
}
