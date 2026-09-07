import Foundation
import SwiftData

// MARK: - Versioned schema
//
// Référence unique des modèles SwiftData versionnés.
// À chaque changement structurel (ajout d'un champ non-optionnel, renommage,
// relation modifiée, suppression de type), créer `SchemaV2`, `SchemaV3`…
// et ajouter les `MigrationStage` correspondants dans `OneToOneMigrationPlan`.

/// Liste des modèles actifs. SwiftData gère automatiquement la lightweight
/// migration depuis un store disque existant lorsque les modèles Swift sont
/// étendus (champs additionnels avec defaults / optionnels).
///
/// ⚠️ Pour un changement structurel cassant (renommage de champ, suppression
/// de type, transformation de données) : créer un `SchemaV2` avec un snapshot
/// **nested** des modèles (sinon CoreData ne voit pas de diff — les types
/// Swift top-level sont partagés) puis ajouter un `MigrationStage` custom.
///
/// ⚠️ Quatre types ont été retirés le 2026-08-10 (`Note`, `NoteAttachment`,
/// `ProjectInfoEntry`, `ProjectCollaboratorEntry`) **sans** créer de `SchemaV2`
/// malgré l'avertissement ci-dessus. Voir
/// `docs/superpowers/specs/2026-08-10-fusion-note-reunion-design.md`. Ce
/// snapshot nested n'a de valeur que pour préserver des données existantes
/// lors de la migration ; le store réel a été vérifié vide sur les quatre
/// tables juste avant chaque suppression (`ZNOTE = 0`, `ZNOTEATTACHMENT = 0`,
/// `ZPROJECTINFOENTRY = 0`, `ZPROJECTCOLLABORATORENTRY = 0`, aucune note
/// rattachée à un collaborateur). Sans données à migrer, un `SchemaV2` n'aurait
/// rien à préserver — il n'a donc pas été créé. Si ce raisonnement ne tient
/// plus (une autre suppression de type sur des données non vides), revenir à
/// la procédure `SchemaV2` standard.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            ProjectMail.self,
            ProjectMailAttachment.self,
            MailIndexSuggestion.self,
            MailScanRecord.self,
            ProjectAttachment.self,
            Collaborator.self,
            ActionTask.self,
            ActionComment.self,
            ProjectAlert.self,
            AppSettings.self,
            Entity.self,
            Meeting.self,
            MeetingTag.self,
            MeetingAttachment.self,
            TranscriptChunk.self,
            SlideCapture.self,
            SavedPrompt.self,
            ManagerReportItem.self,
            ManagerMeetingReport.self,
            TranscriptSegment.self,
            ReportTemplate.self,
            ReportRevision.self,
            AgendaProjectRule.self
        ]
    }
}

/// SchemaV2 (2026-09-06) : ajout pur de `ChatSession`/`ChatMessageEntity` (persistance de
/// l'historique du chatbot, `ChatbotView`). Pas de champ modifié/supprimé sur les types
/// existants — lightweight migration automatique, pas de `MigrationStage` custom nécessaire.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV1.models + [ChatSession.self, ChatMessageEntity.self]
    }
}

/// SchemaV3 (2026-09-07, lot 0B de la refonte de l'écran de réunion) : ajout des neuf
/// tables du modèle cible (spec §1.3) — notes horodatées, planches d'atelier, jalons et
/// interlocuteurs de projet, et le domaine 1:1 (fil, engagements, ordre du jour, humeur,
/// objectifs). Les modèles existants gagnent en plus des **colonnes à valeur par défaut**
/// (`ActionTask` : priorité, statut, effort, source, reports ; `MeetingAttachment` : portée,
/// MIME, poids, épinglage ; `SlideCapture` : `t`, source, déclencheur ; `Project` : périmètre
/// et thèmes ; `Meeting` : `recordingStartedAt`, `notesMigrated`). Aucun champ supprimé,
/// renommé ni rendu obligatoire → lightweight migration automatique, pas de `MigrationStage`
/// custom (même raisonnement que V1→V2). Vérifié par `Tests/SchemaV3MigrationTests.swift`.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV2.models + [
            MeetingNote.self,
            Board.self,
            ProjectMilestone.self,
            ProjectContact.self,
            OneOnOneThread.self,
            Commitment.self,
            OneOnOneAgendaItem.self,
            MoodEntry.self,
            OneOnOneObjective.self
        ]
    }
}

// MARK: - Migration plan

enum OneToOneMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }

    static var stages: [MigrationStage] {
        // Pas de stage explicite : V1→V2 n'ajoute que deux tables, V2→V3 des
        // tables et des colonnes à valeur par défaut. SwiftData applique dans
        // les deux cas une lightweight migration automatique. Un
        // `MigrationStage.lightweight` explicite serait redondant ; la
        // convention du dépôt est de laisser cette liste vide et de le
        // documenter ici.
        []
    }
}

// MARK: - Schema courant

/// Version de schéma active utilisée par le `ModelContainer` de l'app.
/// Pointer cet alias vers la dernière `SchemaVN` lors d'une migration.
typealias CurrentSchema = SchemaV3
