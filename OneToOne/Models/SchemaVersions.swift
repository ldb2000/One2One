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
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            ProjectMail.self,
            ProjectMailAttachment.self,
            ProjectInfoEntry.self,
            ProjectCollaboratorEntry.self,
            ProjectAttachment.self,
            Collaborator.self,
            Interview.self,
            ActionTask.self,
            ProjectAlert.self,
            AppSettings.self,
            Entity.self,
            InterviewAttachment.self,
            Meeting.self,
            MeetingAttachment.self,
            TranscriptChunk.self,
            SlideCapture.self,
            SavedPrompt.self,
            Note.self
        ]
    }
}

// MARK: - Migration plan

enum OneToOneMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // Pas de stage explicite tant qu'il n'y a qu'une version de schéma
        // — SwiftData applique une lightweight migration automatiquement
        // pour les ajouts de champs avec defaults.
        []
    }
}

// MARK: - Schema courant

typealias CurrentSchema = SchemaV1
