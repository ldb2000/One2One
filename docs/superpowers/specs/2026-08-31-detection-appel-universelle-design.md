# Détection d'appel universelle — Design spec

**Date** : 2026-08-31
**Branche** : `feat/detection-appel-universelle` (à créer à l'implémentation)
**Specs de référence** :
[`2026-08-28-teams-autorecord-popup-design.md`](2026-08-28-teams-autorecord-popup-design.md) (v2.1, implémentée)
et [`2026-05-12-calendar-teams-integration-design.md`](2026-05-12-calendar-teams-integration-design.md) (v1)
**Auteur** : laurent.deberti
**Statut** : à valider

## 0. Résumé

Aujourd'hui, OneToOne ne propose d'enregistrer que si **trois** conditions
tiennent ensemble : Microsoft Teams est l'app détectée, un événement EventKit
existe à ±2 min, et cet événement porte un lien Teams. Le calendrier est un
**verrou** : sans événement apparié, aucun popup
(`TeamsAutoRecordCoordinator.swift:160`).

Cette spec inverse le rapport. Ce qu'on détecte, c'est **la participation à un
appel** — Zoom, Teams, Meet dans un navigateur, Webex —, et le calendrier
devient un **enrichissement** : il pré-remplit la réunion quand il a de quoi,
et se tait sinon. Une réunion ad hoc est créée dans tous les cas.

Le signal change de nature. Le titre de fenêtre, faible, laisse la place à un
signal universel et indépendant de l'application : **le micro est capté par
quelqu'un d'autre**, croisé avec **une application de visioconférence est
présente**.

## 1. Goals & non-goals

### Goals

1. Détecter la participation à un appel indépendamment de la plateforme :
   apps natives (Teams, Zoom, Webex, Slack) et appels dans un navigateur
   (Google Meet, Teams Web).
2. Proposer l'enregistrement **sans exiger** d'événement calendrier.
3. Créer une réunion ad hoc titrée automatiquement quand aucun événement ne
   correspond.
4. Conserver l'enrichissement calendrier quand il existe — et l'élargir,
   puisqu'un mauvais appariement ne coûte plus qu'un pré-remplissage à
   corriger.
5. Ne pas régresser le parcours existant : machine à états, demandes vers
   `MeetingView`, comptes rendus, double piste audio restent en place.

### Non-goals

- Pas de détection de **qui** capte le micro. L'API publique CoreAudio dit que
  le périphérique d'entrée est en service, jamais par quel processus. Le
  croisement avec « une app de visio est présente » porte tout le sens.
- Pas de lecture du contenu des appels, pas d'API Zoom/Google/Microsoft. La
  détection reste purement locale (décision v1 T-A, maintenue).
- Pas de renommage global du domaine « Teams » en « appels ». Les noms
  existants restent là où ils décrivent encore la réalité
  (`TeamsCallMonitor`, `TeamsURLExtractor`) ; seuls le coordinateur et les
  libellés utilisateur se généralisent. Voir §7.
- Pas d'apprentissage des refus (« ne plus proposer pour cette app »).
  Envisageable en v2 de ce chantier si l'usage le réclame.
- Pas de détection par caméra. Beaucoup d'appels sont audio seuls ; le micro
  suffit et couvre plus de cas.

## 2. Décisions

| Ref | Décision | Valeur |
|---|---|---|
| U-1 | Signal principal | Micro capté par un tiers (CoreAudio) **et** app de visio présente |
| U-2 | Seuil de confirmation | 10 s de micro pris sans interruption |
| U-3 | Condition « app de visio » | Vue **au moins une fois depuis** que le micro est pris — pas « en ce moment » |
| U-4 | Navigateurs | Comptent seulement si un titre de fenêtre évoque une conférence |
| U-5 | Sans événement calendrier | Réunion ad hoc, titre automatique, type déduit par `ProjectMatchService` |
| U-6 | Fenêtre d'appariement | Tout événement dont l'intervalle contient l'instant, plus 2 min de marge avant |
| U-7 | Déduplication | Par **session d'appel** pour les ad hoc, par occurrence d'événement sinon |
| U-8 | Périmètre du remaniement | Nouveau détecteur + coordinateur généralisé ; `TeamsCallMonitor` conservé |
| U-9 | Fin d'appel | 30 s de micro libre (inchangé par rapport à la valeur actuelle) |

### Décisions annulées de la spec v2.1

| Ref v2.1 | Décision | Sort |
|---|---|---|
| §10 | « Appel Teams sans event EventKit correspondant → pas de popup » | **Annulée** : c'est le cas nominal du chantier |
| D-2 | Tolérance d'appariement `±2 min` autour du `startDate` | **Élargie** : voir U-6 |
| §3 | Heuristique « appel actif » fondée sur le titre de fenêtre | **Complétée**, pas remplacée : le titre reste un signal parmi d'autres |

## 3. Le signal

### Ce qu'on observe

- **Le micro est-il capté ?** `kAudioDevicePropertyDeviceIsRunningSomewhere`
  sur le périphérique d'entrée par défaut
  (`kAudioHardwarePropertyDefaultInputDevice`). Propriété publique CoreAudio,
  lisible sans aucune permission — la permission micro n'est requise que pour
  *capturer*, pas pour savoir que le périphérique est en service.
- **Une app de visio est-elle présente ?** `NSWorkspace.frontmostApplication`
  et, quand la permission d'enregistrement d'écran est déjà accordée,
  l'énumération `SCShareableContent` déjà utilisée par `TeamsCallMonitor`.

### Ce qu'on ne peut pas observer

- Quel processus détient le micro. C'est la limite qui impose le croisement.
- Si l'appel est en sourdine (le micro reste réservé par l'app, donc le signal
  tient — c'est un avantage ici).
- Le nombre de participants, l'état de la caméra.

### Heuristique « appel en cours »

Un appel est réputé en cours quand **toutes** ces conditions tiennent :

1. le micro est capté sans interruption depuis au moins **10 s** (U-2) ;
2. une app de visioconférence a été vue **au moins une fois depuis l'instant
   où le micro a été pris** (U-3) ;
3. OneToOne n'est pas lui-même en train d'enregistrer
   (`AudioRecorderService.isRecording` faux).

La condition 3 n'est pas un détail : dès que notre capture démarre, c'est
*nous* qui tenons le micro, et sans cette garde le détecteur se déclencherait
sur son propre enregistrement.

La condition 2 dit « depuis », pas « maintenant ». Rejoindre un appel puis
basculer aussitôt sur ses notes est le comportement normal d'un manager en
réunion ; exiger l'app au premier plan au moment de la confirmation raterait
précisément l'usage visé.

### Fin d'appel

`callEnded` est émis après **30 s** de micro libre (U-9), même seuil que la
détection de fin actuelle. Un blanc de quelques secondes entre deux prises de
parole ne termine donc rien.

### Apps de visioconférence reconnues

Apps natives, par identifiant de bundle :

| App | Identifiant |
|---|---|
| Microsoft Teams | `com.microsoft.teams`, `com.microsoft.teams2` |
| Zoom | `us.zoom.xos` |
| Webex | `Cisco-Systems.Spark` |
| Slack (huddles) | `com.tinyspeck.slackmacgap` |

Navigateurs (`com.apple.Safari`, `com.google.Chrome`, `com.microsoft.edgemac`,
`company.thebrowser.Browser`, `org.mozilla.firefox`) : ils ne comptent **que
si** un titre de fenêtre évoque une conférence (U-4). Même normalisation par
tokens que `TeamsCallObservation.titleLooksLikeCall` — repli des accents et de
la ponctuation via `AgendaProjectResolver.normalizedKey` —, avec la liste
élargie : `call, meeting, appel, reunion, conference, meet, visio, zoom,
teams, webex, huddle`.

Cette liste vit **en dur** dans le code, comme celle de la spec v2.1 (§14
Q12) : elle évolue avec les faux positifs constatés, pas avec l'imagination.

### Faux positifs assumés

Un mémo vocal ou un appel WhatsApp de plus de 10 s, pendant qu'une app de
visio tourne, déclenchera une proposition. « Ignorer » la referme, mais elle
sera apparue. C'est le prix explicite de la couverture universelle, et un
écart assumé avec la philosophie §3 de la spec v2.1 (« pas de popup vaut mieux
qu'un faux positif ») — qui valait quand le calendrier filtrait, et ne vaut
plus quand le but est justement d'attraper les appels hors calendrier.

### Faux négatifs connus

- Un appel où l'utilisateur n'active jamais son micro (écoute seule) :
  certaines apps ne réservent pas le périphérique tant que le micro est coupé.
  Non couvert, et non couvrable par ce signal.
- Un appel passé depuis une app inconnue de la liste, sans navigateur ni app
  de visio ouverte.
- Un casque Bluetooth qui bascule le périphérique d'entrée par défaut en cours
  d'appel : le compteur de 10 s repart. Le popup arrive plus tard, il n'est
  pas perdu.

## 4. Architecture

### Nouveaux modules

```
OneToOne/
  Services/
    Calls/
      MicrophoneActivityMonitor.swift   [NEW] — enveloppe CoreAudio, listener
      ConferenceAppRegistry.swift       [NEW] — pur : quelles apps, quels titres
      CallDetector.swift                [NEW] — pur : machine à états du signal
    Teams/
      TeamsAutoRecordCoordinator.swift  [MODIFIER] — le verrou tombe, l'ad hoc naît
      TeamsCallMatchService.swift       [MODIFIER] — fenêtre élargie (U-6)
      TeamsCallMonitor.swift            [inchangé] — reste une source parmi d'autres
    MeetingNotificationService.swift    [MODIFIER] — corps des notifications généralisés
```

Deux des trois nouveaux modules sont des **fonctions pures**, testables sur
des entrées synthétiques sans matériel ni permission — c'est le patron qui a
porté les deux chantiers précédents et qui a permis d'attraper leurs défauts
avant l'écran.

### `MicrophoneActivityMonitor`

Singleton `@MainActor`. Installe un `AudioObjectPropertyListener` sur
`kAudioDevicePropertyDeviceIsRunningSomewhere` du périphérique d'entrée par
défaut, plus un listener sur
`kAudioHardwarePropertyDefaultInputDevice` pour suivre les changements de
périphérique (casque branché en cours d'appel). Publie
`isMicrophoneInUse: Bool`.

Neutralise son signal — publie `false` — tant que
`AudioRecorderService.shared.isRecording` est vrai.

La lecture initiale se fait à l'installation ; ensuite tout est événementiel,
sans scrutation.

### `ConferenceAppRegistry`

`enum` namespace, fonctions pures, aucun import framework au-delà de
Foundation :

```swift
static func isConferenceApp(bundleID: String) -> Bool
static func isBrowser(bundleID: String) -> Bool
static func titleLooksLikeConference(_ title: String) -> Bool
/// Vrai si l'une des fenêtres est une app de visio, ou un navigateur dont
/// le titre évoque une conférence.
static func conferenceAppSeen(in windows: [(bundleID: String, title: String)]) -> String?
```

Retourne le **nom lisible** de l'app détectée (« Zoom », « Microsoft Teams »,
« Google Meet »), qui servira au titre de la réunion ad hoc et au corps de la
notification.

### `CallDetector`

`enum` namespace + `struct CallDetectionState`, sur le modèle exact de
`TeamsCallObservation` (spec v2.1 §3, éprouvé) :

```swift
struct CallSignalInput: Equatable {
    let isMicrophoneInUse: Bool
    let conferenceApp: String?      // nom lisible, nil si aucune vue
    let isSelfRecording: Bool
    let now: Date
}

enum CallSignalDecision: Equatable {
    case none
    case callStarted(app: String)
    case callEnded
}

enum CallDetector {
    static let confirmationDelay: TimeInterval = 10
    static let absenceDelay: TimeInterval = 30
    static func step(state: inout CallDetectionState, input: CallSignalInput) -> CallSignalDecision
}
```

L'état retient `micTakenAt`, `conferenceAppSeenSinceMicTaken` (le nom, mémorisé
dès la première observation) et `micFreeSince`. Toute la logique — le seuil de
10 s, la mémoire de l'app vue « depuis », la garde anti-auto-détection, les
30 s de fin — vit là, en fonctions pures.

### Le coordinateur

`TeamsAutoRecordCoordinator` gagne une entrée et perd son verrou.

**Entrée** : le détecteur devient une quatrième source, à côté des trois
existantes (surveillance `NSWorkspace`, clic « Rejoindre Teams », horloge
calendrier). Toutes convergent vers `handleDetection()`, comme aujourd'hui.

**Le verrou tombe** (`:160`). `handleDetection()` devient :

```
match(events, at: now) →
  .matched(event)   → importEvent(event)          // inchangé
  .ambiguous(_)     → réunion ad hoc              // le lien se rattache à la main
  .none             → réunion ad hoc              // le cas nominal de ce chantier
```

**La réunion ad hoc** : `Meeting(title:date:)` avec un titre composé du nom de
l'app et de l'heure — « Appel Zoom · 14:30 » —, `kind` déduit par
`ProjectMatchService` comme partout ailleurs, aucun `calendarEventID`. Elle est
créée, ouverte et enregistrée par le chemin existant
(`QuickLaunchRouter` + `MeetingRequest.startRecording`), sans code nouveau.

**Déduplication** (U-7) : `handledEventIDs` continue de servir aux réunions
issues du calendrier. Les ad hoc sont dédoublonnées par **session d'appel** —
une session étant l'intervalle continu pendant lequel le micro est pris. Une
proposition par session, refusée ou acceptée.

### L'appariement élargi

`TeamsCallMatchService.match` passe de « `startDate` à ±2 min » à « l'intervalle
`[startDate − 2 min, endDate]` contient l'instant » (U-6). Rejoindre avec dix
minutes de retard retrouve la réunion ; la marge avant couvre le fait de
rejoindre en avance.

Le filtre sur le lien Teams (`teamsJoinURL != nil`) **disparaît** : un
événement d'agenda qui recouvre l'instant est un candidat légitime pour
pré-remplir, qu'il porte ou non un lien de visioconférence. C'est cohérent avec
l'inversion : le calendrier n'autorise plus, il enrichit.

Les événements annulés et sur la journée entière restent exclus.

## 5. Modèle de données

Aucun changement de schéma SwiftData, aucune migration.

Une réunion ad hoc est une `Meeting` ordinaire : `title`, `date`, `kind`,
`participants` vides au départ, `calendarEventID` vide. Rien ne la distingue
structurellement d'une réunion créée à la main depuis le menu bar — ce qui est
voulu : elle doit se comporter comme telle partout ensuite (rapport, export,
statistiques).

`AppSettings` : aucune clé nouvelle. `teamsAutoRecordEnabled` continue de
gouverner tout le parcours ; son libellé dans une future UI de Réglages devra
dire « appels » et non « Teams ».

## 6. Notifications

Les identifiants de catégorie **ne changent pas** (`TEAMS_CALL_DETECTED` et
les autres) : les modifier invaliderait les autorisations déjà accordées par
le système, pour un gain purement cosmétique.

Seuls les **corps** se généralisent :

| Cas | Titre | Corps |
|---|---|---|
| Événement apparié | `Appel détecté : {event.title}` | `Démarrer l'enregistrement dans OneToOne ?` |
| Ad hoc | `Appel {app} détecté` | `Démarrer l'enregistrement dans OneToOne ?` |

Le reste du parcours — fin d'appel, transcription prête, STT indisponible,
liaison — est inchangé.

## 7. Ce qui garde son nom

`TeamsCallMonitor`, `TeamsURLExtractor`, `TeamsLauncher` décrivent encore
exactement ce qu'ils font : détecter Teams, extraire une URL Teams, lancer
Teams. Ils restent.

`TeamsAutoRecordCoordinator` ment désormais sur son nom, mais le renommer
touche une classe fraîchement livrée et pas encore vérifiée à l'écran. La
décision U-8 le garde tel quel et se contente de généraliser son vocabulaire
interne (commentaires, libellés) là où il est faux. Un renommage propre —
fichiers, types, catégories, clé de réglage — mérite son propre commit, une
fois le parcours validé en usage réel.

Cet écart est consigné ici pour qu'il ne se découvre pas par surprise.

## 8. Permissions

| Permission | Nécessaire pour | Sans elle |
|---|---|---|
| Aucune | Lire `kAudioDevicePropertyDeviceIsRunningSomewhere` | — |
| Calendrier | Enrichir depuis EventKit | Réunion ad hoc, le parcours fonctionne |
| Micro | Enregistrer | Bandeau d'erreur, pas d'enregistrement (inchangé) |
| Enregistrement d'écran | Voir les fenêtres en arrière-plan, capter l'audio système | Détection limitée au premier plan, capture micro seule (inchangé) |

Le point notable : **la détection ne demande aucune permission nouvelle**. Le
signal micro est lisible par défaut ; c'est le croisement qui coûte, et il
réutilise ce qui existe déjà.

`Info.plist` : aucun ajout. (La clé calendrier manquante, corrigée le
2026-08-31 par `b925b42`, était un bug antérieur sans rapport avec ce
chantier.)

## 9. Stratégie de test

### Unit — fonctions pures

- **`CallDetector`** : micro pris sans app de visio → rien ; app vue puis micro
  pris → confirmation à 10 s pile ; 9,9 s → rien ; app vue **puis quittée**
  avant la confirmation → confirme quand même (U-3) ; `isSelfRecording` vrai →
  jamais de décision ; micro libéré 30 s → `callEnded` ; libéré 29 s puis
  repris → rien ; deux sessions successives → deux `callStarted`.
- **`ConferenceAppRegistry`** : chaque app native reconnue ; navigateur avec
  titre de conférence → reconnu, avec titre quelconque → ignoré ; titre
  accentué (« Réunion ») ; app inconnue → ignorée ; liste vide → nil.
- **`TeamsCallMatchService`** (modifié) : événement en cours, rejoint 10 min
  après le début → apparié ; rejoint 1 min avant → apparié ; terminé il y a
  1 min → pas apparié ; sans lien Teams → **apparié** (changement) ; annulé →
  ignoré ; journée entière → ignoré ; deux candidats → ambigu.

### Integration — `ModelContext` en mémoire

- Détection sans événement → une réunion ad hoc créée, titre attendu, pas de
  `calendarEventID`, ouverture demandée avec `.startRecording`.
- Détection avec événement recouvrant → réunion pré-remplie, `calendarEventID`
  posé.
- Deux détections dans la même session d'appel → une seule proposition.
- Détection pendant un enregistrement en cours → proposition de liaison
  (comportement D-10 existant, préservé).

### Non testable en unitaire

`MicrophoneActivityMonitor` : dépend d'un périphérique réel. Sa surface pure
(la résolution du périphérique par défaut) est testable ; le listener relève de
la vérification à l'écran.

### Vérification à l'écran

1. Zoom natif, hors calendrier → popup après ~10 s, réunion « Appel Zoom · … ».
2. Google Meet dans Chrome, hors calendrier → popup.
3. Réunion Teams **au calendrier**, rejointe 10 min en retard → popup avec le
   bon titre pré-rempli (vérifie U-6).
4. Mémo vocal de 15 s avec Teams ouvert → popup **attendu** : c'est le faux
   positif assumé, on vérifie qu'« Ignorer » le referme proprement.
5. Enregistrement en cours → aucune re-détection sur notre propre micro.
6. Casque branché en cours d'appel → au pire un popup retardé, jamais perdu.

## 10. Plan d'attaque

1. `ConferenceAppRegistry` + tests — pur, sans dépendance.
2. `CallDetector` + tests — pur, la machine à états.
3. `MicrophoneActivityMonitor` — l'enveloppe CoreAudio, fine.
4. `TeamsCallMatchService` élargi + tests — le changement le plus risqué pour
   l'existant, isolé et testé seul.
5. Le coordinateur : le verrou tombe, l'ad hoc naît, la déduplication par
   session ; tests d'intégration.
6. Corps des notifications, amendements de la spec v2.1, `STATUS.md`.
7. Vérification à l'écran (§9).

## 11. Critères d'acceptation

- `swift test` passe intégralement.
- Le parcours calendrier existant est inchangé : une réunion Teams au
  calendrier rejointe à l'heure se comporte exactement comme avant.
- Les six scénarios de §9 sont déroulés à l'écran.
- La spec v2.1 est amendée sur §3, §10 et D-2, avec renvoi vers ce document.
- `STATUS.md` est à jour.

## 12. Hors scope, à noter pour plus tard

- Apprentissage des refus (« ne plus proposer pour cette app aujourd'hui »).
- Renommage complet du domaine « Teams » → « appels ».
- UI de Réglages pour `teamsAutoRecordEnabled` (déjà reporté par la v2.1).
- Détection par caméra, pour les appels où le micro reste coupé.
- Attribution « moi / distant » des segments : rappel que la chronologie de
  provenance est **produite mais non consommée** (voir la spec v2.1 §6.1
  amendée). Ce chantier ne la touche pas.
