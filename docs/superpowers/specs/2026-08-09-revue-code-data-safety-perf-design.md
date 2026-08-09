# Reprise de la revue de code de mai — sûreté des données, fil principal, robustesse

**Date** : 2026-08-09
**Statut** : validée
**Origine** : la branche `fix/code-review-data-safety-perf`, un commit unique du
30 mai 2026 (`0c627ee`), jamais fusionnée.

---

## Pourquoi cette spec existe

La branche portait douze correctifs issus d'une passe de revue. Elle est restée sur le
côté ; `master` a avancé de **280 commits** depuis, et huit de ses onze fichiers ont été
modifiés entre-temps. L'hypothèse raisonnable était que ces correctifs de mai étaient
devenus caducs, ou avaient été réappliqués autrement.

**Cette hypothèse est fausse.** Vérification faite sur le `master` du 9 août 2026 :
**aucun des douze n'est présent**. Les défauts sont tous encore là.

La branche elle-même n'est pas fusionnable en l'état — elle conflite sur
`AIClient.swift` et `MeetingView.swift`, et embarque un ajustement de grille sans rapport.
Elle est donc traitée ici comme un **cahier de défauts connus**, à réappliquer sur le code
d'aujourd'hui, un par un, chacun revérifié.

**Un des douze est déjà corrigé** : le déverrouillage forcé d'`AVAudioPCMBuffer`
(commit `1b6a121`, 9 août). Il faisait planter l'application sur l'édition audio ; c'est
pourquoi il a été traité séparément et tout de suite. Restent les onze ci-dessous.

---

## Méthode de vérification, et son inégalité

Chaque défaut a été confronté au code actuel. **Le degré de certitude n'est pas le même
partout**, et l'implémenteur doit le savoir :

- **Vérifiés en lisant le code** : n° 1, 2, 7. Le défaut est décrit ci-dessous tel qu'il
  se présente aujourd'hui, pas tel que le message de mai le décrivait.
- **Vérifiés par absence de marqueur** : n° 3, 4, 5, 6, 8, 9, 10, 11. Le correctif est
  absent — aucun `guard`, aucune constante, aucun repli d'encodage ne figure là où il
  devrait. Que le défaut soit exploitable dans les conditions réelles reste à confirmer
  au cas par cas.

**Première étape de toute implémentation : rejouer la vérification.** Deux mois se sont
écoulés entre la revue et cette spec, et trois jours peuvent suffire à en périmer un.

---

## Deux diagnostics de mai qui ont vieilli

À corriger, sinon l'implémenteur cherchera un défaut qui n'existe plus sous cette forme.

**Le n° 2 n'est plus un « print muet ».** Le message d'origine dit que l'échec de
sauvegarde après une coupe audio était avalé par un `print`. Ce n'est plus vrai :
`TranscriptEditService.deleteSegment` finit aujourd'hui par `try context.save()`, qui
propage. Le défaut réel est plus fin, et plus intéressant — voir sa fiche.

**Le n° 1 ne concerne pas que `TranscriptChunk`.** `repairStoreIfNeeded` ne déduplique
aujourd'hui **que les codes de projet**. Aucun identifiant UUID n'y est réparé. Le piège
est donc plus large que le seul `chunkId` visé en mai.

---

## Les onze correctifs

### Axe 1 — Sûreté des données

#### 1. La réparation du store ne couvre aucun identifiant UUID

**État vérifié.** `OneToOneApp.repairStoreIfNeeded()` déduplique les `code` de projet en
leur ajoutant un suffixe. Il ne touche à aucun UUID.

**Le piège.** Un `var id: UUID = UUID()` non optionnel sur un modèle SwiftData reçoit sa
valeur par défaut à la **migration**, pas à l'insertion : toutes les lignes migrées
partagent alors le même identifiant. `TranscriptChunk.chunkId` était le cas visé en mai.
`Meeting.stableID` est réputé exposé au même piège.

**À faire.** Étendre la réparation aux identifiants UUID : détecter les doublons et
réattribuer. Traiter `TranscriptChunk.chunkId` et **inventorier les autres modèles**
portant un UUID non optionnel avec valeur par défaut — l'inventaire fait partie du
travail, la liste de mai n'est pas fiable.

**Sévérité** : haute. Des identifiants dupliqués corrompent silencieusement les
rapprochements.

#### 2. Une coupe audio réussie suivie d'une sauvegarde échouée désynchronise sans le dire

**État vérifié.** `TranscriptEditService.deleteSegment` procède dans cet ordre : coupe le
fichier audio, décale les segments suivants, supprime le segment, puis `try context.save()`.

Le commentaire du code affirme « failure-safe : si throw, transcript intact ». C'est vrai
de l'étape 1 — mais **faux de la dernière**. Si `save()` échoue, l'audio a déjà été coupé
sur disque de façon irréversible pendant que la transcription conserve le segment :
l'audio et le texte ne correspondent plus, et l'appelant reçoit une erreur SwiftData
générique qui ne dit rien de cet état.

**À faire.** Distinguer cet échec par un type d'erreur propre (`saveFailedAfterAudioCut`
ou équivalent) et faire remonter à l'interface un message qui **nomme la
désynchronisation**, au lieu d'un échec générique. Corriger au passage le commentaire, qui
promet une garantie que le code ne tient pas.

**Sévérité** : haute. L'utilisateur ne peut pas savoir que son enregistrement a été modifié.

#### 3. Le fichier temporaire survit à un échec d'écriture

**État vérifié par absence.** `AudioFileEditor.trim` et `.cut` suppriment le `.tmp.wav`
**avant** d'écrire, jamais après un échec. `split` le fait pour ses deux sorties (bloc
`catch`), `trim` et `cut` n'ont pas d'équivalent.

**À faire.** Nettoyer le temporaire sur le chemin d'échec, sur le modèle du `catch` déjà
présent dans `split`.

**Sévérité** : basse. Encombrement du disque, pas de perte de données.

### Axe 2 — Travail inutile sur le fil principal

#### 4. `MeetingView` interroge le système de fichiers à chaque rendu

**État vérifié par absence** : aucun cache `hasWavFile`.
**À faire** : mettre le résultat en cache dans un `@State`, invalidé aux changements
pertinents, au lieu d'un `fileExists` synchrone deux fois par rendu.
**Sévérité** : moyenne. Accès disque synchrone sur le fil de rendu.

#### 5. Le chatbot construit son contexte de base sur le chemin synchrone

**État vérifié en lisant le code.** `ChatbotView` appelle `buildDatabaseContext()` de
façon synchrone dans le chemin d'envoi d'un message.
**À faire** : sortir la construction du chemin synchrone.
**Sévérité** : moyenne. Gel perceptible à l'envoi si la base est grosse.

#### 6. La recherche de la barre latérale lit le corps de toutes les notes à chaque frappe

**État vérifié en lisant le code.** `Sidebar.projectMatches` appelle `noteMatches` sur
**toutes** les notes de **tous** les projets, et `noteMatches` fait
`n.body.localizedCaseInsensitiveContains(q)` — donc un balayage du corps complet de chaque
note, à **chaque caractère tapé**.
**À faire** : débouncer la saisie (250 ms dans la version de mai).
**Sévérité** : moyenne, croissante avec le nombre de notes. C'est le défaut de performance
le plus certain des quatre, parce qu'il est visible dans le code sans mesure.

#### 7. Les avatars sont redécodés à chaque rendu

**État vérifié par absence** : pas de `CachedNSImage.swift`, pas de cache d'images.
**À faire** : un cache `NSCache` d'images décodées.
**Sévérité** : basse à moyenne, proportionnelle au nombre d'avatars affichés.

### Axe 3 — Robustesse des entrées et des appels externes

#### 8. Le prompt du CLI Claude passe en argument de ligne de commande

**État vérifié par absence** : aucun `standardInput` dans `AIClient`.
**À faire** : passer le prompt par l'entrée standard. Un prompt long dépasse `ARG_MAX` et
l'appel échoue.
**Sévérité** : moyenne. Échec net, mais sur les gros contextes seulement.

#### 9. Le corps d'erreur d'un flux n'est pas plafonné

**État vérifié par absence** : aucune constante de plafond dans `AIClient`.
**À faire** : plafonner à 64 Ko aux deux endroits concernés. Une erreur serveur volumineuse
est aujourd'hui chargée entièrement en mémoire.
**Sévérité** : basse.

#### 10. Un fichier non-UTF8 est rejeté au lieu d'être lu

**État vérifié par absence** : aucun repli CP1252 ni Latin-1 dans `AIIngestionService`.
**À faire** : tenter CP1252 puis Latin-1 quand le décodage UTF-8 échoue — cas courant des
exports Windows.
**Sévérité** : moyenne. Fonction inutilisable sur un fichier pourtant valide.

#### 11. La troncature des documents est silencieuse

**État vérifié par absence** : aucun marqueur de troncature dans `AIReportService`.
**À faire** : insérer un marqueur visible dans le texte tronqué et journaliser. Aujourd'hui
le modèle reçoit un document coupé sans que rien ne l'indique, ni à lui ni à l'utilisateur.
**Sévérité** : moyenne. Produit des réponses fausses sans trace.

---

## Ordre proposé

1. **N° 1 et 2** — sûreté des données. Ce sont les seuls dont la conséquence est une
   corruption ou une désynchronisation silencieuse. Le n° 2 est cerné et local ; le n° 1
   demande d'abord un inventaire.
2. **N° 6, 5, 4** — le fil principal, du plus certain au moins mesuré. Le n° 6 est visible
   dans le code sans instrumentation.
3. **N° 10 et 11** — robustesse des entrées : les deux produisent des résultats faux
   plutôt que des échecs francs, ce qui est pire.
4. **N° 8, 3, 7, 9** — le reste, par sévérité décroissante.

Chacun est indépendant des autres et peut faire son propre commit.

---

## Non-objectifs

- **Ne pas fusionner `fix/code-review-data-safety-perf`.** Elle conflite sur deux fichiers
  et embarque un ajustement de grille `DashboardView` sans rapport avec la revue.
- Ne pas réappliquer un correctif sans avoir revérifié que son défaut existe encore.
- Ne pas traiter le n° 4 déjà corrigé (`AVAudioPCMBuffer`, commit `1b6a121`).

---

## Sort de la branche

Elle n'a **jamais été poussée** : elle n'existe qu'en local. Tant que cette spec n'est pas
exécutée, elle reste la seule copie du code des correctifs — le message de commit décrit
les intentions, pas les diffs.

Quand la spec aura été appliquée, la branche pourra être archivée en étiquette puis
supprimée, comme cela a été fait pour `worktree-backlog-sharepoint-import`
(`archive/backlog-sharepoint-import`).

---

## Ce que cette spec ne dit pas

Aucun de ces onze défauts n'a été **observé à l'exécution**. Ils sont établis par lecture
du code. Les quatre défauts de performance en particulier sont des raisonnements sur des
chemins chauds, pas des mesures : si l'un d'eux est traité, la première chose à faire est
de le mesurer avant, puis après.
