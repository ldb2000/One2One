import Testing
@testable import OneToOne

/// Critère d'acceptation n° 1 du chantier 1 : « Aucun espace ne peut afficher
/// une zone vide sans invite d'action. »
///
/// L'ancien écran opposait à un dossier vide un `ContentUnavailableView`
/// (« Aucun document ») qui ne disait pas quoi faire. La règle est désormée
/// portée par une **table exhaustive** : chaque couple espace × mode a son
/// invite, et ce test échoue si l'un manque — y compris ceux qu'un lot futur
/// ajouterait.
@Suite("Aucun espace vide sans invite (critère chantier 1 n° 1)")
struct MeetingEmptyInviteTests {

    @Test("Les neuf combinaisons espace × mode ont toutes une invite non vide")
    func everyStateHasAnInvite() {
        for space in MeetingScreenModel.Space.allCases {
            for mode in MeetingScreenModel.Mode.allCases {
                let invite = MeetingEmptyInvite.Catalogue.invite(for: space, mode: mode)
                #expect(!invite.titre.isEmpty, "titre manquant pour \(space)/\(mode)")
                #expect(!invite.invite.isEmpty, "invite manquante pour \(space)/\(mode)")
            }
        }
    }

    @Test("L'invite dit quoi faire, pas seulement qu'il n'y a rien")
    func inviteIsActionable() {
        // Les notes renvoient aux commandes `/` que la spec §2.4 veut
        // « toujours visibles, pas de découverte cachée ».
        let notes = MeetingEmptyInvite.Catalogue.invite(for: .meeting, mode: .live)
        #expect(notes.invite.contains("/"))

        // Les ressources renvoient au dépôt ou à l'import.
        let ressources = MeetingEmptyInvite.Catalogue.invite(for: .resources, mode: .live)
            .invite.lowercased()
        #expect(ressources.contains("dépos") || ressources.contains("import"))

        // Le rapport renvoie à sa génération.
        let rapport = MeetingEmptyInvite.Catalogue.invite(for: .report, mode: .review)
            .invite.lowercased()
        #expect(rapport.contains("génér") || rapport.contains("transcri"))
    }

    @Test("Aucune invite ne se contente de nier : pas de « Aucun… » tout court")
    func inviteNeverJustDenies() {
        for space in MeetingScreenModel.Space.allCases {
            for mode in MeetingScreenModel.Mode.allCases {
                let invite = MeetingEmptyInvite.Catalogue.invite(for: space, mode: mode)
                // Une invite d'action fait au moins une phrase : le titre seul
                // (« Aucune décision ») était exactement le défaut à corriger.
                #expect(invite.invite.count >= 20,
                        "invite trop courte pour \(space)/\(mode) : « \(invite.invite) »")
            }
        }
    }

    @Test("Les invites de compteur à zéro des cartes KPI existent aussi")
    func kpiInvites() {
        // Spec §2.3 : « Un compteur à 0 reste affiché avec une invite
        // (« Aucune décision — /décision dans les notes »), jamais une carte
        // vide. »
        #expect(!MeetingEmptyInvite.Catalogue.kpiInvite(for: .decisions).isEmpty)
        #expect(!MeetingEmptyInvite.Catalogue.kpiInvite(for: .risks).isEmpty)
        #expect(!MeetingEmptyInvite.Catalogue.kpiInvite(for: .actions).isEmpty)
        #expect(!MeetingEmptyInvite.Catalogue.kpiInvite(for: .presence).isEmpty)
        #expect(MeetingEmptyInvite.Catalogue.kpiInvite(for: .decisions).contains("/décision"))
    }
}
