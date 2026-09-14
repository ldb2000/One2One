# ADR 2026-09-14 — Sources audio : fallback par segment et notifications système

**Statut :** accepté le 2026-09-14.
**Portée :** `AudioInputDeviceService`, `AudioInputRouting`, `AudioPermissionKind`,
`MicrophoneSettingsLink`, `AudioRecorderService.switchInput`/`rotate`/`mergeSegments`,
`MeetingRecordingCoordinator`.
**Références :** spec `docs/superpowers/specs/2026-09-14-sources-audio-erreurs-design.md`,
plan `docs/superpowers/plans/2026-09-14-sources-audio-erreurs.md`.

## Contexte

Le tableau des cas d'erreur de capture (spec
`docs/superpowers/specs/2026-09-14-sources-audio-erreurs-design.md`, §1) demande qu'un iPhone
déconnecté en cours de réunion provoque une bascule immédiate sur le micro du Mac. Jusqu'ici,
tout changement de périphérique **arrêtait** l'enregistrement et tuait la transcription live
(`AudioRecorderService.handleConfigurationChange`). L'application ne savait pas non plus
choisir un micro : l'engine lisait l'entrée par défaut du système.

## Décisions

**D1 — Fallback par segment.** À la déconnexion, le WAV courant est clos, un second est ouvert
sur l'entrée de repli, et les segments sont concaténés à l'arrêt (`mergeSegments`, sur la
primitive `concatenateWAVs` déjà présente). Le `TapSink` est conservé : seuls son fichier et son
convertisseur changent (`rotate`), la continuation du flux live et l'horloge d'échantillons
publiés ne bougent pas. Alternative écartée : rebrancher l'engine dans le même fichier, qui
impose de réinstaller tap et convertisseur sur un `AVAudioFile` ouvert et risque de corrompre le
WAV en cours.

**D2 — Micro préféré global** (`AppSettings.preferredAudioInputUID`), le choix fait dans la
feuille de pré-réunion vaut pour cette réunion seulement.

**D3 — Contrôle Teams au démarrage seulement.** Une piste système laissée ouverte après la
fermeture de Teams capte du silence, sans dommage.

**D4 — Notifications système pour les événements de séance** (bascule, flux Teams absent) via
`MeetingNotificationService`, **feuilles in-app** pour le choix de micro et l'aide autorisations.
Aucun composant toast n'est créé. Alternative écartée : un toast in-app, toujours visible en
plein écran mais un composant de plus.

**D5 — Trois couches** : `AudioInputRouting` décide (pur, testé), `AudioInputDeviceService`
observe (CoreAudio, recette manuelle), `AudioRecorderService` exécute ; `MeetingRecordingCoordinator`
les relie et porte la surveillance.

**D6 — Pas de rebascule automatique** au retour du périphérique.

**D7 — Le micro intégré est reconnu par `kAudioDeviceTransportTypeBuiltIn`**, jamais par son nom.

## Conséquences

- `AVAudioEngineConfigurationChange` ne stoppe plus l'enregistrement quand un coordinateur
  surveille : il lui est remis, et c'est lui qui rebranche (même entrée, nouveau segment) ou
  bascule. Sans coordinateur, comportement historique.
- Un enregistrement peut désormais produire plusieurs fichiers intermédiaires ; `stop()` rend
  toujours **une** URL. Si la fusion échoue, le dernier segment est rendu et les autres restent
  sur disque, dans `recordings/`.
- Les bascules sont tracées dans `AudioRecorderService.inputSwitches`, pas dans
  `provenanceTimeline` dont la struct est figée par ses tests.
- Hors périmètre : choix par réunion, rebascule au retour, surveillance de Teams en séance,
  toast in-app, périphériques de sortie, sélection du micro depuis la palette ⌘K.
- `MeetingRecordingCoordinator` est une classe instanciée par fenêtre de réunion, hors des deux
  patrons de services de `CLAUDE.md` (enum pur ou singleton `.shared`) — choix de la spec §4.4,
  assumé : le préflight et la surveillance portent un état propre à une fenêtre de réunion
  donnée, qu'un singleton partagerait entre fenêtres à tort.
- Le câblage recorder / transcription live / playhead reste dans `MeetingView`, qui a
  **grossi** de +43/−10 lignes malgré la règle « rien ne s'ajoute » ; la décision est dans le
  coordinateur, la colle dans la vue. Dette : sortir `startRecording`, `startAppendRecording`,
  `stopRecordingAndTranscribe` de `MeetingView`.
- À la rotation de segment, `TapSink.rotate` **draine** l'ancien convertisseur jusqu'à
  `.endOfStream` (pause comprise) avant de le remplacer : sans cela chaque bascule perdait
  ~74 ms d'audio (l'amorce retenue par le resampler 48 → 16 kHz). `finish()` ne draine pas
  (préexistant).
- `switchInput` se répare seul : en cas d'échec à mi-chemin il appelle `stopForInputLoss()`
  puis relance l'erreur.
- Le coordinateur annule sa tâche de surveillance dans `deinit`.
