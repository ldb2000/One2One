# Pièces jointes de réunion : copiées, jamais référencées

**Statut :** validée le 2026-09-07 (décision **D5** du programme de refonte, acceptée par
Laurent le 2026-09-07)
**Portée :** `MeetingAttachment`, `AttachmentImporter`, `MeetingAttachmentService`,
`StorageStatsService`, `OrphanCleanupService`, `BackupService`
**Références :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §8 ·
`docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §4 (D5), §5 (lot 6)

## Contexte

Deux politiques de stockage cohabitaient dans l'application, pour la même action de
l'utilisateur — déposer un fichier :

- **Une pièce de projet est copiée.** `AttachmentImporter.copyIntoAppSupport(source:bucket:)`
  recopie le fichier dans `Application Support/OneToOne/projects/<code>/<horodatage>_<nom>`,
  et `ProjectAttachment.filePath` désigne cette copie.
- **Une pièce de réunion est référencée.** `MeetingAttachmentService.importDocument` ne
  copie rien : `MeetingAttachment.filePath` garde le chemin d'origine et `bookmarkData`
  un signet à portée de sécurité vers ce même fichier.

La seconde politique a trois conséquences qu'on a constatées :

1. **La pièce disparaît sans prévenir.** Déplacer, renommer ou vider le Téléchargements
   suffit : `OrphanCleanupService.orphanAttachments` la classe en orpheline et propose de
   supprimer la ligne. Le texte extrait et les chunks RAG survivent, mais plus rien ne
   permet de rouvrir le document dont on parlait en séance.
2. **La sauvegarde n'est pas fiable.** `BackupService` embarque bien `fileData` lu depuis
   `filePath`, mais ce fichier vit hors du périmètre de l'app : une sauvegarde faite après
   un rangement du disque n'emporte que la ligne.
3. **Le partage à l'écran et l'épinglage n'ont pas d'ancre.** Le lot 6 doit afficher un
   document à l'écran, l'annoter, l'épingler à un timecode et le citer dans le rapport.
   Toutes ces surfaces désignent un fichier ; aucune ne peut le faire si le fichier est
   susceptible d'avoir bougé entre la séance et la relecture.

La spec §8 tranche déjà en une ligne : « **Copie, jamais référence** : un fichier déposé
ou une image insérée est copié dans la réunion. »

## Décision

**Une pièce de réunion est copiée dans le document de réunion, jamais référencée.**

1. `AttachmentImporter.Bucket` gagne le cas
   `meetingDocuments(meetingStableID: UUID)`, de sous-chemin
   `recordings/<uuid>/documents`. La copie réutilise sans changement le mécanisme du
   bucket projet : préfixe horodaté `yyyyMMdd-HHmmss_`, nom assaini, suffixe `-n` en cas
   de collision dans la même seconde.
2. `MeetingAttachmentService.importDocument` **copie avant d'insérer la ligne**.
   `MeetingAttachment.filePath` désigne la copie ; `bookmarkData` reste `nil` — un signet
   vers une copie interne n'a aucune valeur, et son absence est le signal le plus simple
   qu'une pièce relève de la nouvelle politique.
3. L'import renseigne les colonnes du modèle cible (créées au lot 0B) :
   `scope = .meeting`, `mimeType` (déduit de l'extension par `UTType`), `byteCount`
   (taille de la copie), `addedByName` (`AppSettings.ownerName`).
4. Les pièces `link` (URL collée) et `capture` (pont vers `SlideCapture`) n'ont pas de
   fichier à copier : la première ne porte qu'une URL, la seconde pointe déjà un PNG
   interne écrit par le moteur de capture. La politique est **sans objet** pour elles, pas
   contournée.
5. **Migration paresseuse des pièces existantes.** À la première ouverture de l'espace
   Ressources d'une réunion, chaque pièce dont le `filePath` est hors du dossier de
   l'application est traitée une fois :
   - la source existe → elle est copiée dans `recordings/<uuid>/documents/`, `filePath`
     est réécrit, `byteCount` et `mimeType` complétés, `bookmarkData` effacé ;
   - la source a disparu → **rien n'est supprimé**. La pièce est simplement *orpheline*
     (état **calculé**, non persisté : `filePath` absent du disque), et le tiroir affiche
     « Fichier introuvable — relier » pour désigner un nouveau fichier.
6. `StorageStatsService` scanne `recordings/*/documents` et compte ces fichiers ;
   `OrphanCleanupService` **ne propose plus à la suppression une pièce copiée** — un
   fichier interne manquant est un incident à signaler, pas une ligne à nettoyer ;
   `BackupService` embarque le fichier copié via le champ `fileData` **déjà présent** dans
   `MeetingAttachmentDTO`, et transporte en plus les six colonnes cibles en champs
   optionnels (les sauvegardes antérieures restent décodables).

## Alternatives étudiées

**(a) Garder le signet (`bookmarkData`) et le résoudre à la lecture.** C'est l'état
actuel, avec en plus la résolution que `ProjectAttachment.resolvedURL()` implémente déjà.
Rejetée : un signet suit un déplacement, il ne survit ni à une suppression, ni à un
volume démonté, ni à un `~/Téléchargements` vidé — et il ne rend pas la sauvegarde
autonome. Le lot 6 doit pouvoir afficher la page 2 d'un chiffrage six mois plus tard.

**(b) Copier seulement les pièces épinglées ou présentées.** Séduisant sur le papier
(moins d'octets), rejeté sur deux points : la décision de copier arriverait *après* le
moment où la source a le plus de chances d'exister encore, et l'utilisateur devrait
comprendre pourquoi certaines pièces se perdent et d'autres pas. Une seule règle, tout le
temps.

**(c) Un magasin de contenu adressé par empreinte (`sha256`), partagé entre réunions et
projets.** C'est la bonne réponse au coût de stockage — le même PDF déposé dans trois
réunions n'existerait qu'une fois. Rejetée pour la v1 : elle introduit un comptage de
références, donc une suppression qui doit être juste, et `OrphanCleanupService` ainsi que
`BackupService` deviendraient nettement plus délicats. À reconsidérer si le stockage
devient un problème mesuré (l'écran Maintenance donne déjà le chiffre).

## Conséquences

**Positives**

- Une pièce déposée en séance reste lisible indéfiniment, quoi qu'il advienne de
  l'original. C'est le préalable de « À l'écran », de l'annotation, de l'épinglage et de
  la citation dans le rapport.
- La sauvegarde devient autonome : `fileData` est toujours lisible puisque le fichier vit
  sous `Application Support`.
- Une seule politique pour les deux portées de pièces (`meeting` et `project`), donc une
  seule explication à donner et un seul code à maintenir.
- `byteCount` devient exact et affichable (`84 Ko` dans les vignettes du tiroir).

**Négatives et parades**

- **Le disque double pour les documents de séance.** Assumé : l'écran Maintenance mesure
  déjà le stockage par catégorie, et le nouveau dossier y est compté explicitement. La
  déduplication est l'alternative (c), reportée.
- **L'import devient plus lent** (une copie avant l'extraction de texte). En pratique
  l'extraction et l'embedding dominent largement.
- **Les pièces déjà en base migrent tardivement**, à l'ouverture de l'espace Ressources
  et non au lancement : une réunion jamais réouverte garde ses références. C'est
  volontaire — migrer 500 réunions au démarrage bloquerait l'app pour un bénéfice nul sur
  les réunions qu'on ne consulte plus.
- **Une pièce dont la source a disparu ne peut pas être réparée automatiquement.** Elle
  reste visible, marquée orpheline, avec une invite de reliaison. On préfère une ligne
  qui dit « ce document manque » à une ligne supprimée qui ne dit plus rien.

## Vérification

- `Tests/AttachmentCopyPolicyTests.swift` — sous-chemin, nommage, MIME, poids.
- `Tests/AttachmentCopyImportTests.swift` — le fichier est copié ; supprimer l'original
  ne rend pas la pièce illisible.
- `Tests/AttachmentMigrationTests.swift` — source présente → copiée et idempotente ;
  source absente → orpheline, sans exception.
- `Tests/StorageStatsDocumentsTests.swift` — le nouveau dossier est compté.
- `Tests/OrphanCleanupServiceTests.swift` — une pièce copiée n'est pas candidate.
