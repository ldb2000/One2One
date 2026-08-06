# Dates interactives et rappels

Date : 2026-08-05
Branche : `feat/editeur-slash-blocs`

> ## ⚠️ Annotation du 2026-08-06 — le découpage a été exécuté **à l'envers**
>
> Vérifié par lecture du code (`SlashController.insertDate`,
> `SlashDatePickerPresenter`, `DateReminder`, commit `e2ed854`) :
>
> | Étape de la spec | État réel |
> |---|---|
> | 1 — format de lien + parsing + aller-retour | **non faite** |
> | 2 — rendu distinct (fond, couleur) | **non faite** |
> | 3 — icône dessinée | non faite |
> | 4 — popover : calendrier, heure | **faite** (`NSPopover` + SwiftUI : champ texte éditable, `DatePicker` graphique, bascule « Inclure l'heure », éditeur d'heure) |
> | 5 — rappel affiché dans le popover, non déclenché | **faite** (`DateReminder`, 5 choix, menu « Rappel ») |
> | 6 — rappels planifiés | non faite |
>
> Les étapes 4 et 5 ont été livrées **avant** les étapes 1 et 2, ce que la spec
> présentait pourtant comme un ordre de dépendance. Conséquence mesurable :
> `SlashController.insertDate` insère toujours du **texte brut**
> (`"5 août 2026"`, `"6 août 2026 13:08"`) et **jette `selection.reminder`** — son
> propre doc-comment le dit. Le popover fait donc choisir à l'utilisateur un rappel
> qui n'est ni écrit, ni stocké, ni déclenché : il disparaît à la validation.
>
> C'est exactement l'avertissement que ce document formulait — « un rappel qui ne se
> déclenche pas est pire qu'un rappel absent » — sauf que le cas réel est pire encore,
> puisque le rappel n'est même pas conservé.
>
> **Deux issues, à trancher** : (a) exécuter l'étape 1 (le lien
> `onetoone://date/…?reminder=P1D`) pour que la donnée survive ; (b) retirer le menu
> « Rappel » du popover tant que (a) n'est pas fait, pour ne pas mentir à
> l'utilisateur. Le reste de ce document reste valide tel quel.

## Point de départ

`/date` existe et insère du **texte brut** (`5 août 2026`) via une `NSAlert`
portant un `NSDatePicker`. Ça marche, mais l'utilisateur veut le comportement
d'AppFlowy :

- une **pastille inline** cliquable, `@5 août 2026 📅`, et non du texte figé ;
- un **calendrier en popover** attaché à la pastille, pas une alerte modale ;
- une **heure optionnelle** (`@6 août 2026 13:08 ⏱`) ;
- un **rappel** : aucun, le jour même à 9h, la veille, deux jours avant, une
  semaine avant.

## Trois chantiers de coûts très différents

| # | Contenu | Coût | Dépendances |
|---|---|---|---|
| 1 | Représentation structurée + rendu distinct | modeste | aucune |
| 2 | Popover d'édition (calendrier, heure, rappel) | moyen | chantier 1 |
| 3 | Rappels réellement déclenchés | **élevé** | modèle de données |

Le chantier 3 est celui qui change de nature : une note est une `String`. Un
rappel qui doit sonner ne peut pas vivre uniquement dans du texte.

## Chantier 1 — représentation et rendu

### Format retenu

Un **lien markdown**, comme pour les mentions (`2026-08-05-mentions-collaborateurs.md`) :

```
[@5 août 2026](onetoone://date/2026-08-05)
[@6 août 2026 13:08](onetoone://date/2026-08-06T13:08)
[@5 août 2026](onetoone://date/2026-08-05?reminder=P1D)
```

Les mêmes trois raisons que pour les mentions : l'aller-retour des liens est
déjà acquis et testé ; le markdown reste standard et exportable ; les données
structurées (date ISO, heure, rappel) tiennent dans l'URL sans inventer de
syntaxe.

Le libellé visible est en français long, le contenu de l'URL en ISO 8601 —
lisible par une machine, stable au changement de locale.

**Écarté** : du texte brut, qui perd la donnée dès qu'on veut la relire ; et un
caractère marqueur porteur d'attributs, qui a causé quatre bugs distincts sur
cette branche.

### Rendu

La pastille d'AppFlowy a un fond, un liseré et une icône. En TextKit 1, dans ce
module :

- **fond et couleur** : attributs sur le run du lien, sans rien ajouter au
  storage — direct ;
- **icône** : ne doit **pas** entrer dans le storage, sinon elle fuit dans le
  markdown enregistré. À dessiner par `MarkdownLayoutManager`, comme les
  marqueurs de liste et le filet de citation. **À mesurer d'abord** : ces
  décorations sont dans la marge ; une icône inline en fin de run est un cas
  différent, et rien ne garantit qu'elle se place proprement.

**Repli acceptable si l'icône inline résiste** : fond coloré et couleur
distincte, sans icône. La pastille reste identifiable et cliquable.

### Distinguer date et mention

Les deux sont des liens. `StyleRenderer` doit les styliser différemment, en
lisant le schéma de l'URL (`onetoone://date/` contre
`onetoone://collaborator/`). Prévoir cette distinction dès le début, sinon les
deux fonctionnalités se marcheront dessus.

## Chantier 2 — popover d'édition

Clic sur la pastille → `NSPopover` ancré sur le rectangle du run, contenant :

- un calendrier (`NSDatePicker` en `.clockAndCalendar`, ou une vue SwiftUI) ;
- une bascule **« Inclure l'heure »** ;
- un menu **« Rappel »** : aucun / le jour même à 9h / la veille / 2 jours
  avant / 1 semaine avant.

Valider réécrit le lien en place. Le popover remplace l'`NSAlert` actuelle,
qui reste le repli pour l'insertion initiale si l'ancrage pose problème.

**Point technique à mesurer** : obtenir le rectangle écran d'un run inline pour
y ancrer le popover. `firstRect(forCharacterRange:actualRange:)` le fait pour
le curseur — vérifié sur cette pile — mais pour une plage de plusieurs
caractères, à confirmer.

**Attention** : le popover ne doit pas voler le focus au texte, même piège que
le panneau du menu `/`. `SlashPanel` a la parade (`canBecomeKey = false`,
`.nonactivatingPanel`) ; s'en inspirer.

## Chantier 3 — rappels réellement déclenchés

C'est ici que ça cesse d'être une affaire d'éditeur.

Un rappel écrit dans une note doit **sonner**. Or une note est une `String`
dans SwiftData : rien ne la surveille, rien ne planifie. Trois questions à
trancher avant d'écrire une ligne :

1. **Où vit le rappel ?** Uniquement dans le texte, avec un balayage des notes
   au démarrage et à chaque sauvegarde ? Ou dans un modèle SwiftData dédié,
   synchronisé avec le texte ? Le second est plus fiable et plus coûteux ; le
   premier risque de désynchroniser texte et notifications.
2. **Que se passe-t-il si la mention est supprimée du texte ?** Le rappel doit
   disparaître. Un modèle séparé demande une réconciliation ; un balayage la
   fait naturellement.
3. **Quelle infrastructure existe déjà ?** Le projet a
   `Services/MeetingNotificationService.swift` — **à lire avant de concevoir**.
   S'il sait déjà planifier des notifications locales, le chantier se réduit
   beaucoup.

**Recommandation** : ne pas s'engager sur le chantier 3 avant d'avoir répondu à
ces trois questions par la lecture du code existant. Les chantiers 1 et 2
livrent déjà une date interactive et éditable ; le rappel peut n'être qu'une
donnée affichée, non déclenchée, dans un premier temps — à condition de le
**dire** dans l'interface plutôt que de laisser croire qu'il sonnera.

Un rappel qui ne se déclenche pas est pire qu'un rappel absent.

> ## ⚠️ Constat du 2026-08-06 — chantier 3 mesuré, non construit
>
> Lecture de `OneToOne/Services/MeetingNotificationService.swift` (299 lignes),
> demandée par la question 3 ci-dessus. Chantiers 1 et 2 livrés dans l'intervalle
> (lien `onetoone://date/…?reminder=…`, rendu distinct) — voir les commits de
> cette branche. Ce qui suit mesure, sans construire, comme demandé.
>
> ### Ce que sait faire `MeetingNotificationService`
>
> - Planifie des notifications locales via `UNUserNotificationCenter`
>   (`UNCalendarNotificationTrigger` sur des `DateComponents`, pas un simple
>   délai) — quatre par réunion : pré-rappel (N min avant le début, réglable),
>   début, « fin dans 5 min » (fixe), fin.
> - Annulation : `cancel(for: meeting)` retire quatre identifiants **connus à
>   l'avance** (`"meeting.<uuid>.preStart"`, `.start`, `.endWarning`, `.end`) —
>   aucun scan, aucun diff contre ce qui est réellement planifié côté OS
>   (`UNUserNotificationCenter.getPendingNotificationRequests()` n'est appelée
>   nulle part dans ce fichier). Reprogrammation : `schedule(for:settings:)`
>   appelle `cancel(for:)` avant de reposer les quatre requêtes — idempotent
>   par construction (mêmes identifiants réécrits), jamais par comparaison.
> - Déclenchement aujourd'hui, quatre call sites, tous liés au calendrier ou
>   aux réglages — aucun sur une sauvegarde de texte libre :
>   `CalendarMeetingImportService` (import), `MeetingView.resyncFromCalendarInMeetingView`
>   (resync), `AppDelegate.applicationDidFinishLaunching` (résilience au
>   redémarrage, via `syncPending`) et `SettingsView.resyncNotifs` (au
>   changement du délai de pré-rappel). `syncPending` re-fetch les réunions à
>   venir (`FetchDescriptor<Meeting>` sur `scheduledStart > now`) et rappelle
>   `schedule` pour chacune — la résilience vient de cette requête SwiftData,
>   pas d'un cache en mémoire.
> - S'appuie entièrement sur un modèle SwiftData concret, `Meeting`
>   (`scheduledStart`/`scheduledEnd`/`title`/`teamsJoinURL`/`participants`,
>   `ensuredStableID` pour construire l'identifiant de requête). Aucune valeur
>   libre passée à l'appel ne fait office de source de vérité — même
>   `snoozePreStart`/`notifyRecordingStarted`, qui prennent des paramètres,
>   restent appelés depuis un `Meeting` déjà chargé.
>
> ### Réponses aux trois questions
>
> 1. **Où vivrait le rappel ?** Le texte porteur d'un `/date` n'est pas
>    uniforme : `Note.body` (`Models/Note.swift`, une note par Projet ou
>    Collaborateur) et `Meeting.notes` (`String`, un champ par réunion) sont
>    deux formes différentes déjà mesurées, sans doute pas les seules. Le
>    patron déjà en place pour les réunions (`Meeting.scheduledStart` = source
>    de vérité, `syncPending` = balayage de réconciliation au démarrage) pointe
>    vers un **modèle SwiftData dédié**, rempli par un balayage du texte **à la
>    sauvegarde** (pas au moment de sonner) plutôt qu'un balayage pur sans
>    modèle : sans modèle, détecter qu'un rappel a disparu du texte demanderait
>    de diffuser contre `getPendingNotificationRequests()`, une API que ce
>    fichier n'utilise nulle part aujourd'hui. La donnée du lien
>    (`onetoone://date/…?reminder=P1D`) reste la source déclarative dans le
>    texte ; le modèle en serait la projection planifiable, sur le même
>    principe que `Meeting.scheduledStart` aujourd'hui.
> 2. **Que se passe-t-il si la mention est effacée du texte ?** Rien
>    aujourd'hui ne le détecterait : `MeetingNotificationService` n'a aucune
>    logique de diff, seulement des identifiants connus à l'avance, annulés
>    explicitement par un appelant qui *sait* qu'un `Meeting` a changé. Pour un
>    rappel dans du texte libre, il faudrait à chaque sauvegarde : extraire
>    l'ensemble courant des liens `onetoone://date/…` porteurs d'un rappel
>    (brique déjà acquise : `DateLinkCatalog.selection(from:)`, chantier 1),
>    le comparer à l'ensemble précédemment connu (le modèle dédié ci-dessus),
>    annuler + supprimer les lignes disparues, ajouter les nouvelles. **Manque
>    concret mesuré** : l'URL actuelle ne porte qu'une date/heure/type de
>    rappel, aucun identifiant d'instance — deux rappels identiques dans la
>    même note seraient indiscernables pour ce diff. `DateLinkCatalog.dateURL`
>    devrait gagner un paramètre d'identité pour que la réconciliation soit
>    fiable.
> 3. **Quelle part du travail reste réellement ?** Réutilisable tel quel : le
>    canevas de notification — délégué `UNUserNotificationCenter`, demande
>    d'autorisation, catégories/actions, routage du tap vers
>    `NotificationCenter.default.post`, et la primitive privée
>    `schedule(id:title:body:fireAt:category:userInfo:interruptionLevel:)`
>    (générique, pas spécifique aux réunions). **Manque, mesuré, à
>    construire** :
>    (a) trancher où vit réellement le texte porteur de `/date` en production
>    (`Note.body` ? `Meeting.notes` ? les deux ?) — non fait ici ;
>    (b) un identifiant d'instance dans l'URL de date (point 2) ;
>    (c) un modèle SwiftData dédié au rappel, avec propriétaire flexible
>    (`Note`/`Meeting`, sur le modèle des deux relations optionnelles
>    mutuellement exclusives déjà présentes sur `Note`) ;
>    (d) une extraction — parcourir les runs `.mdLink` dont l'hôte est `date`
>    dans le texte d'une note/réunion, câblée sur son chemin de sauvegarde ;
>    (e) la logique de diff/réconciliation (ajout, suppression, changement),
>    absente de `MeetingNotificationService`, qui ne fait qu'annuler quatre
>    identifiants fixes puis reposer — jamais comparer contre un ensemble
>    variable ;
>    (f) `registerCategories()` **remplace** tout le jeu de catégories à chaque
>    appel (`center.setNotificationCategories([...])`) — un nouveau type de
>    rappel doit être ajouté à cette même liste, pas déclaré à part, sous peine
>    de faire disparaître silencieusement les actions déjà enregistrées pour
>    les réunions ;
>    (g) le tap sur une notification ne sait aujourd'hui qu'ouvrir un `Meeting`
>    par id (`openMeetingNotification`) — atteindre un point précis dans une
>    note n'a pas d'équivalent.
>    **Estimation** : chantier réellement « coût élevé », comme la table du
>    haut de ce document le disait déjà — confirmé, pas seulement supposé. Le
>    canevas de notification (partie la plus visible) est acquis, mais le cœur
>    du travail (modèle, identité d'instance, diff, branchement sur la
>    sauvegarde, décision sur l'emplacement du texte) reste entièrement à
>    construire. Pas un prolongement d'une heure des chantiers 1/2.
>
> **Conséquence pour le menu « Rappel » du popover** : la donnée survit
> désormais à l'enregistrement (chantier 1), mais rien ne la déclenchera avant
> ce chantier 3 tel que mesuré ci-dessus — non construit dans ce passage, par
> consigne explicite (« si le chemin s'avère court, on le fera ensuite ; s'il
> est long, on retirera le menu plutôt que de mentir à l'utilisateur »). Au vu
> de ce qui précède, le chemin est **long** : retirer le menu « Rappel » du
> popover (ou le marquer clairement non fonctionnel) reste la décision
> cohérente tant que ce chantier n'est pas engagé.

## Pièges connus de ce code

Tous mesurés sur cette branche :

1. **`insertText` fusionne les `typingAttributes`** — une pastille insérée après
   du code inline hériterait `.mdInlineCode`. `SlashController.stripRiskyTypingAttributes`
   est la parade.
2. **Rien de visuel ne doit entrer dans le storage.** Quatre bugs distincts en
   sont venus. L'icône se dessine, elle ne s'insère pas.
3. **Les tests pixel dépendent de l'apparence système.** `NSColor.labelColor`
   devient blanc en mode sombre ; un test qui peint sur fond blanc mesure zéro.
   Envelopper dans `NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance`.
4. **Le mécanisme natif n'est pas garanti.** `NSTextList` ne peint rien en
   TextKit 1 — mesuré. Vérifier avant de concevoir sur une API AppKit.

## Découpage proposé

| # | Étape | Livrable |
|---|---|---|
| 1 | Format de lien + parsing + aller-retour | une date insérée survit à l'enregistrement, avec sa donnée structurée |
| 2 | Rendu distinct (fond, couleur), sans icône | la date se voit comme un élément, pas comme du texte |
| 3 | Icône dessinée, si la mesure le permet | confort |
| 4 | Popover : calendrier, heure | la date s'édite en place |
| 5 | Rappel affiché dans le popover, non déclenché | la donnée est saisie et conservée |
| 6 | Rappels réellement planifiés | après réponse aux trois questions ci-dessus |

Les étapes 1 et 2 remplacent déjà l'insertion en texte brut actuelle par
quelque chose de relisable et d'éditable plus tard.

## Hors périmètre

- Récurrence des rappels.
- Fuseaux horaires — tout est en heure locale.
- Retrouver toutes les notes contenant une date à venir (le lien le permettra,
  c'est une fonctionnalité à part).
- Synchronisation avec le calendrier système.
