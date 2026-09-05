# Plan — IA configurable avec LM Studio et OpenRouter

Date : 2026-09-05. Statut : **lots 1 à 4 implémentés, tests automatisés réussis ; recette réelle restante**.
Branche : `refactor/ai-endpoints-lmstudio-openrouter`, créée depuis `master` à `a388fb8`.

Suivi : l'accord utilisateur « Go » lance les lots 1 à 4 ; décision dans
`docs/adr/2026-09-05-endpoints-ia-configurables.md`. Les sections suivantes conservent
le plan initial. Les lots embeddings, retrait des anciens fournisseurs et extensions
audio/agent restent différés. Voir `STATUS.md` pour les validations effectives.

Évolution après recette utilisateur : Ollama est promu endpoint principal et le
moteur Direct est retiré (partie du lot 6 désormais réalisée). Les catalogues et champs
de saisie sont corrigés. Décision complémentaire :
`docs/adr/2026-09-05-catalogues-ia-retrait-direct.md`.

## 1. Objectif et recommandation

Permettre dans les réglages de choisir **le type d’endpoint, puis le modèle** :
LM Studio pour un serveur local, OpenRouter pour les modèles accessibles par API.
Les services métier ne doivent plus connaître le moteur d’inférence.

La majorité des usages textuels sont déjà centralisés derrière `AIClient` et sont
migrables sans réécriture des prompts ni de la logique métier. Il faut cependant
distinguer génération de texte, embeddings de recherche, transcription et agent
outillé : un même modèle ne couvre pas nécessairement ces quatre besoins.

Recommandation : livrer d’abord les deux endpoints pour les fonctions textuelles,
y compris le classement des mails ; conserver initialement la transcription,
la diarisation et les embeddings locaux. Proposer ensuite les embeddings sur API,
avec leur propre choix de modèle. La transcription distante et le remplacement
de Claude CLI sont des extensions distinctes. Leurs limites sont détaillées ci-dessous.

Les choix structurants des lots 1 à 4 ont été validés dans l’ADR citée ci-dessus.
Lors de la préparation initiale, aucun code applicatif n’avait été modifié et aucun
endpoint réel n’avait été testé.

## 2. Cartographie du code existant

Les chemins ci-dessous sont relatifs à la racine du dépôt. Les constats proviennent
du code à `a388fb8` ; certaines descriptions dans `docs/architecture.md` sont dépassées.

| Usage | Code actuel | Conséquence pour la migration |
| --- | --- | --- |
| Routage texte et streaming | `OneToOne/Services/AIClient.swift`, `AIClientProtocol.swift` | Réutiliser la façade ; extraire le transport HTTP compatible OpenAI. |
| LLM intégré | `OneToOne/Services/DirectLLMClient.swift` | Chargement MLX, cache HF et enregistrement Gemma4Swift ; remplacés par le serveur pour les requêtes migrées. |
| Rapports, préparation, extraction d’actions | `OneToOne/Services/AIReportService.swift` | Appelle déjà `AIClient`, dont des réponses JSON et du streaming. |
| Import et reformulation | `OneToOne/Services/AIIngestionService.swift`, `AIReformulationService.swift` | Appellent déjà `AIClient` ; extraction des fichiers reste locale. |
| Suivi manager et suggestions de tags | `ManagerCRGenerator.swift`, `ManagerCategoryClassifier.swift`, `ManagerSnippetElaborator.swift`, `MeetingTagSuggester.swift` dans `OneToOne/Services/` | Utilisent `AIClientProtocol`, avec injection pour les tests. |
| Chat avec contexte RAG | `OneToOne/Views/RAGChatView.swift`, `OneToOne/Services/RAGService.swift` | Génération déjà via `AIClient` ; récupération du contexte dépend séparément des embeddings. |
| Classement des mails | `OneToOne/Services/MailLLMClassifier.swift`, `MailAutoIndexService.swift` | **Contourne `AIClient`**, appelle directement `DirectLLMClient`, même si un autre fournisseur est sélectionné. |
| Embeddings textuels | `OneToOne/Services/EmbeddingService.swift`, `MLXEmbeddingEngine.swift` | MLX par défaut, Ollama historique ; configuration dans `UserDefaults`, indépendante des réglages LLM. |
| Transcription différée | `OneToOne/Services/TranscriptionService.swift`, `STT/` | Cohere, Voxtral et Qwen3-ASR locaux ; protocole `STTEngine` couplé à `MLXArray`. |
| Transcription en direct | `OneToOne/Services/Live/` | Capture → VAD → fenêtres audio → moteur local → fusion ; ce n’est pas du streaming de tokens. |
| Diarisation et identité vocale | `PyannoteDiarizer.swift`, `SpeakerMatcher.swift`, `DiarizationService.swift`, `STT/DiarizeFirstTranscriber.swift` dans `OneToOne/Services/` | Tours de parole, vecteurs vocaux et rapprochement avec les collaborateurs. |
| OCR de documents et slides | `OneToOne/Services/OCRService.swift`, `ScreenCaptureService.swift`, `SlideCapture/` | Apple Vision et capture macOS, sans LLM. |
| Noyau d’agent de tâches | `OneToOne/Services/Agent/` | Processus Claude CLI, outils, session `--resume`, flux `stream-json`, fichiers de travail et contrat `etat.json`. |
| Configuration et sauvegarde | `OneToOne/Models/AppSettings.swift`, `SchemaVersions.swift`, `OneToOne/Views/SettingsView.swift`, `OneToOne/Services/BackupService.swift` | Migration des préférences, des secrets et des sauvegardes à traiter ensemble. |

### Points précis à corriger pendant le chantier

- `AIProvider` contient six anciens choix, avec des valeurs persistées servant aussi
  de libellés ; le fournisseur inconnu retombe sur `.direct`. Ajouter des identifiants
  stables pour les nouveaux profils et éviter les réinitialisations silencieuses.
- Le transport actuel dispense de clé uniquement `.ollama` : LM Studio sans
  authentification échouerait avant la requête. Les délais et erreurs locales sont
  également spécifiques à Ollama.
- La liste de modèles des réglages appelle `/api/tags`, propre à Ollama.
  `updateDefaults(for:)` écrase endpoint et modèle au changement de fournisseur.
- Le lecteur SSE ne traite que `delta.content` et ignore les autres événements,
  notamment une erreur reçue après HTTP 200 ; il peut retourner une réponse partielle
  comme si la génération avait réussi.
- `AppSettings.cloudToken` est stocké en SwiftData et exporté par `BackupService`.
  Le Trousseau existe pour OAuth, mais pas pour toutes les clés API, contrairement
  à ce que laisse entendre la documentation générale.
- `TranscriptChunk.embeddingModel` existe, mais `RAGQuery.search` et
  `searchByVector` ne filtrent pas les chunks par modèle. La similarité renvoie zéro
  pour des dimensions différentes ; deux modèles de même dimension sont comparés
  malgré des espaces vectoriels incompatibles.
- Plusieurs producteurs étiquettent les vecteurs avec `EmbeddingService.model`
  **après** un `await` : un changement de configuration en cours de calcul peut
  attribuer au résultat le mauvais modèle.

## 3. Ce qui peut passer par ces endpoints

État des API vérifié dans les documentations officielles le 2026-09-05. La présence
d’une route HTTP ne garantit ni la qualité ni toutes les capacités du modèle choisi.

| Fonction | LM Studio | OpenRouter | Proposition |
| --- | --- | --- | --- |
| Texte, rapports, reformulation, chat, classement | Oui, chat compatible OpenAI | Oui, chat compatible OpenAI | Périmètre initial. |
| Réponses JSON métier | Selon modèle et support de sortie structurée | Selon modèle et paramètres disponibles | Garder la validation applicative ; vérifier le JSON sur les cas réels. |
| Embeddings textuels | Oui, `/v1/embeddings` | Oui, `/api/v1/embeddings` | Modèle et migration d’index distincts du LLM. |
| Compréhension d’images | Selon modèle visuel | Selon modèle visuel | Extension possible ; l’OCR Vision actuel n’en dépend pas. |
| Transcription d’enregistrements | Pas de route STT dans la liste compatible consultée | API STT dédiée documentée | Conserver le local en première livraison ; prototype OpenRouter séparé. |
| Horodatage et diarisation distante | Pas de contrat équivalent identifié | Disponibles selon fournisseur et modèle | Évaluer explicitement les résultats et les options nécessaires. |
| Reconnaissance des collaborateurs par leur voix | Pas de remplacement équivalent identifié | Les labels de locuteurs ne remplacent pas les empreintes locales | Conserver `SpeakerMatcher` et les modèles vocaux. |
| Transcription live avec VAD et fusion | Pas de remplacement direct identifié | Une API de fichiers ne remplace pas ce pipeline | Garder le traitement local ; étude de latence séparée. |
| Agent avec outils et fichiers | Un modèle peut participer, mais le runtime doit exister | Même distinction | Ne pas remplacer Claude CLI par un simple appel de chat. |

LM Studio expose les routes compatibles chat, modèles et embeddings ;
la configuration proposée utilisera `http://localhost:1234/v1` comme adresse initiale.
Le serveur doit être lancé et un modèle exploitable disponible. La liste peut
inclure les modèles téléchargés mais non chargés si le chargement à la demande
est activé. Sources : [API compatible LM Studio](https://lmstudio.ai/docs/developer/openai-compat),
[liste des modèles](https://lmstudio.ai/docs/developer/openai-compat/models).

LM Studio n’exige pas de jeton par défaut, mais peut activer l’authentification :
le formulaire doit accepter une clé facultative et gérer le refus du serveur.
Source : [authentification LM Studio](https://lmstudio.ai/docs/developer/core/authentication).

OpenRouter utilise une clé Bearer et des identifiants de modèles issus du catalogue.
Les modalités et paramètres disponibles doivent guider la sélection ; une liste
statique de quelques noms deviendrait rapidement obsolète.
Source : [catalogue OpenRouter](https://openrouter.ai/docs/guides/overview/models).

OpenRouter propose les embeddings et un catalogue dédié : il serait incorrect de
les exclure du projet par principe. Sources :
[création d’embeddings](https://openrouter.ai/docs/api/api-reference/embeddings/submit-an-embedding-request),
[modèles d’embeddings](https://openrouter.ai/docs/api/api-reference/embeddings/list-embeddings-models).

OpenRouter documente `/api/v1/audio/transcriptions`, acceptant du JSON avec audio
base64 ou un formulaire multipart. Les segments horodatés, mots et labels de
locuteurs dépendent du fournisseur ; certains modèles refusent `verbose_json`.
Les options de diarisation sont spécifiques et les contraintes de taille et durée
doivent être vérifiées avant une intégration sur de longues réunions. Cela rend une
extension STT possible, sans établir l’équivalence avec les empreintes vocales et le
pipeline live actuels. Source :
[transcription OpenRouter](https://openrouter.ai/docs/guides/overview/multimodal/stt).

## 4. Architecture proposée

### 4.1 Une configuration par usage, un transport partagé

```text
Rapports / reformulation / imports / manager / chat / classement mails
    → AIClient (façade métier conservée)
    → instantané de configuration de génération
    → OpenAICompatibleClient
        → LM Studio ou OpenRouter : chat/completions

Indexation / recherche RAG
    → EmbeddingService
    → configuration d’embeddings indépendante
        → MLX existant, puis LM Studio ou OpenRouter : embeddings

Capture / transcription / diarisation / identité vocale
    → pipeline audio local existant

Agent de tâches
    → runtime Claude CLI existant, migration éventuelle distincte
```

Types proposés, dans `OneToOne/Services/AI/` sauf les types persistés :

- `AIEndpointKind` : `lmStudio`, `openRouter`, identifiants techniques stables.
- `AIEndpointConfiguration` : identifiant de profil, type, URL de base, référence
  de secret ; mémorisation séparée des réglages LM Studio et OpenRouter.
- `AIModelSelection` : profil, identifiant exact du modèle, paramètres de génération.
- `AIRequestConfiguration` : valeur immutable `Sendable`, résolue avant la requête ;
  pas d’objet SwiftData mutable transmis au transport.
- `AIModelDescriptor` : id, nom, capacités connues/inconnues, contexte et paramètres
  supportés lorsque disponibles. Ne pas déduire une capacité uniquement du nom.
- `AIModelCatalog` : découverte, cache par profil, rafraîchissement et annulation.
- `OpenAICompatibleClient` : JSON typé, `URLSession` injectable, chat et streaming.
- `AIConfigurationStore` et `AICredentialStore` : préférences et Trousseau séparés.

Conserver au début la signature `AIClient.send(prompt:settings:onProgress:)` et
`AIClientProtocol` pour limiter les changements métier. La façade résout le profil
puis délègue au nouveau client. Les nouveaux tests ciblent le transport avec une
session simulée ; une évolution vers des événements de progression typés pourra
être interne, adaptée au callback texte existant.

### 4.2 Réglages visibles

Parcours principal : **type d’endpoint → connexion → modèle → test → enregistrer**.

- LM Studio : URL éditable, jeton facultatif, état de connexion, liste actualisable.
- OpenRouter : URL initiale `https://openrouter.ai/api/v1`, clé masquée au Trousseau,
  catalogue filtrable avec recherche. Ne pas réutiliser la clé d’un autre profil.
- Conserver la sélection propre à chaque endpoint lorsque l’utilisateur alterne.
- Prévoir une saisie d’identifiant manuel quand le catalogue est indisponible ;
  distinguer modèle inconnu, incompatible, absent et serveur injoignable.
- « Tester » utilise le brouillon complet des réglages et un texte neutre, avec
  une sortie bornée. Il ne modifie pas implicitement la configuration active.
- En première livraison, un modèle de génération commun. Une rubrique séparée
  indique que transcription et recherche sémantique utilisent leurs moteurs locaux.
- Au lot embeddings, ajouter un choix de moteur et de modèle propre à la recherche,
  avec état de l’index et commande de réindexation. Changer le LLM seul ne réindexe rien.

La sélection d’OpenRouter implique l’envoi des textes concernés au service distant,
y compris le contexte RAG. Le classement des mails, jusqu’ici forcé en local et
exécuté en arrière-plan, mérite une option explicite « utiliser l’endpoint configuré
pour classer les mails », désactivée lors de la migration vers un profil distant.
Si elle est désactivée, conserver le résultat heuristique existant. Aucun basculement
automatique de LM Studio vers OpenRouter en cas de panne.

### 4.3 Contrat du client HTTP

- Normaliser les URL sans doubler `/v1`, préserver le préfixe `/api/v1` d’OpenRouter.
  Vérifier schéma et hôte ; ne pas transférer une clé entre profils ni vers un nouvel
  hôte par redirection. HTTP local doit fonctionner dans l’application packagée :
  vérifier `Info.plist` et les règles réseau sans ajouter d’exception globale inutile.
- Distinguer connexion, attente du premier token et inactivité en streaming ;
  prévoir le chargement à froid local et propager l’annulation à `URLSession`.
- SSE : assembler les événements, ignorer les commentaires, traiter `[DONE]`,
  `finish_reason`, usage, erreurs en cours de flux et interruption prématurée.
  Ne jamais valider automatiquement un rapport tronqué ou une réponse vide.
- Séparer texte de réponse et champs de raisonnement ; ne pas injecter ces derniers
  dans un rapport. Les appels d’outils sont hors contrat du client texte initial.
- Ne transmettre que les paramètres adaptés au modèle, notamment température,
  limite de sortie et éventuel schéma JSON. Capacité inconnue : contrat minimal,
  test explicite, pas de promesse de support.
- Erreurs lisibles : clé absente/refusée, crédit insuffisant, limite de débit,
  contexte trop long, modèle absent, serveur arrêté, contenu refusé ou tronqué.
  Reprises bornées pour les erreurs transitoires avant réception de contenu ;
  pas de répétition automatique d’une génération déjà partiellement reçue.
- Journaliser fournisseur, modèle, durée, identifiant de requête et usage disponible,
  sans clés ni corps de prompts ; garder les réponses partielles comme brouillons.

Les commentaires SSE et les erreurs après démarrage du flux sont documentés par
[OpenRouter Streaming](https://openrouter.ai/docs/api_reference/streaming).

## 5. Lots de modification et critères de fin

### Lot 1 — Configuration, compatibilité et secrets

Fichiers : `AppSettings.swift`, `SchemaVersions.swift`, `BackupService.swift` ;
nouveaux types de configuration, résolveur de profils et stockage de clés.

1. Ajouter les nouveaux profils avec des champs optionnels ou valeurs par défaut,
   sans supprimer les anciens champs ni changer les valeurs historiques.
2. Écrire une migration idempotente des réglages existants. Une installation
   configurée en MLX, Ollama ou ancien cloud continue via une voie de compatibilité
   jusqu’au choix explicite d’un nouvel endpoint ; ne pas convertir un repo HF en
   identifiant LM Studio ni un modèle direct en identifiant OpenRouter par supposition.
3. Une nouvelle installation peut proposer LM Studio, sans prétendre qu’un serveur
   ou un modèle existe. L’absence de configuration laisse les fonctions non IA utilisables.
4. Migrer les clés API vers le Trousseau avec vérification de l’écriture avant
   effacement de la valeur historique. Un échec reste récupérable et visible.
5. Versionner le DTO de sauvegarde, accepter les anciens exports, conserver profils
   et choix de modèles, omettre les secrets dans les nouveaux exports. Restaurer
   sur un autre Mac demande de ressaisir la clé. Les anciens exports contenant des
   clés ne sont pas réécrits par cette migration.

Fin : tests de migration depuis chaque ancien fournisseur, valeur inconnue,
réouverture du store, migration répétée, erreur Trousseau et restauration ancien/nouveau
backup. Utiliser des stores temporaires représentatifs ; examiner un snapshot de
schéma si une transformation dépasse une migration additive.

### Lot 2 — Transport texte LM Studio / OpenRouter

Fichiers : `AIClient.swift`, `AIClientProtocol.swift`, nouveaux clients et décodeur SSE.

Extraire le code compatible OpenAI, injecter `URLSession`, brancher les deux profils
et mettre en œuvre le contrat du §4.3. Garder les chemins historiques isolés le temps
de la transition. Ne pas ajouter de SDK fournisseur : Foundation suffit pour ce périmètre.

Fin : tests HTTP simulés pour requête normale et streaming, authentification locale
facultative/activée, clé distante, chemins d’URL, annulation, erreurs HTTP et SSE,
flux interrompu, Unicode, réponse vide, sortie tronquée et dépassement de contexte.

### Lot 3 — Catalogue et interface de réglages

Fichiers : `SettingsView.swift` ; nouveaux `AISettingsView.swift` dans
`OneToOne/Views/Settings/` et `AIModelCatalog.swift`.

Remplacer le sélecteur principal par les deux endpoints, charger `/models`, conserver
les préférences par profil et mettre en œuvre le parcours du §4.2. Les anciens profils
restent accessibles pour revenir à la configuration précédente pendant la transition.
LM Studio peut nécessiter un enrichissement via son catalogue natif pour connaître
le type du modèle ; ne pas inventer les métadonnées absentes de la route compatible.

Fin : sélection restaurée après relance, alternance entre endpoints, catalogue vide
ou hors ligne, clé refusée, recherche et modèle manuel ; une réponse de catalogue
ancienne ne remplace pas celle du profil nouvellement sélectionné. Tester le brouillon
ne sauvegarde pas involontairement la configuration.

### Lot 4 — Couverture de tous les usages textuels

Fichiers : `MailLLMClassifier.swift`, `MailAutoIndexService.swift`, réglages mails ;
services de rapports/import/reformulation/manager/tags et `RAGChatView.swift` pour validation.

Remplacer l’appel direct MLX du classement par le client injecté, appliquer l’option
de classement distant et garder le repli heuristique existant. Tous les usages texte
suivent alors le profil actif. Vérifier les parseurs JSON et les tailles de contexte
sur des jeux de données synthétiques représentatifs ; une compatibilité HTTP ne
garantit pas la qualité des catégories, actions ou rapports.

Fin : mocks confirmant le routage effectif de chaque famille de services, mails sans
appel distant lorsque l’option est désactivée, JSON invalide sans écriture métier
incorrecte ; recette réelle avec un modèle choisi sur chacun des deux endpoints.

**Livraison initiale exploitable : lots 1 à 4.** Transcription, OCR et embeddings
locaux fonctionnent toujours ; les modèles de génération sont choisis dans l’app.

### Lot 5 — Embeddings configurables et cohérence de l’index

Fichiers : `EmbeddingService.swift`, `MLXEmbeddingEngine.swift`, `RAGService.swift`,
`MeetingAttachmentService.swift`, `ProjectMailStore.swift`, `Maintenance/BatchJobsService.swift`,
`OneToOne/Models/MeetingModels.swift`, configuration, sauvegarde et UI de maintenance.

1. Introduire une configuration d’embeddings indépendante avec MLX conservé comme
   défaut et deux adaptateurs HTTP. OpenRouter liste ces modèles via `/embeddings/models`.
2. Utiliser le contrat `input` / `data[].embedding` et réordonner par `index` ;
   vérifier nombre de résultats, dimensions, valeurs finies et lots incomplets.
3. Définir les préfixes query/document selon le contrat du modèle et le prétraitement
   du serveur, sans les déduire du seul backend ni les appliquer deux fois.
4. Introduire une signature d’espace vectoriel : profil/modèle, révision connue ou
   version explicite, dimension, prétraitement et normalisation. Une égalité de
   dimensions ne suffit pas. Conserver `embeddingModel` pour la compatibilité historique.
5. Figer la configuration pendant tout un lot et retourner les vecteurs avec leur
   signature ; ne plus lire le modèle global après l’inférence pour les étiqueter.
6. Filtrer **les deux chemins** de recherche par signature. `searchByVector` doit
   recevoir l’identité de l’espace du vecteur. Exclure un ancien chunk ambigu jusqu’à
   réindexation plutôt que comparer des espaces incompatibles.
7. Afficher les chunks obsolètes, réindexer par lots annulables et reprenables. Écrire
   seulement après validation du lot, conserver textes et liens, et ne pas effacer
   l’ancien vecteur d’un chunk en cas d’échec. Pendant la transition, signaler une
   couverture partielle de recherche. Tester le retour à l’ancien profil ; il peut
   nécessiter une réindexation si les anciens vecteurs ont été remplacés.

Fin : tests de même dimension mais modèles différents, changement de profil en cours
de lot, réponses désordonnées/incomplètes, préfixes, index mixte, interruption/reprise
et persistance. Une comparaison RAG sur un petit corpus français connu valide aussi
la pertinence, au-delà du transport.

### Lot 6 — Retrait du LLM intégré et des anciens fournisseurs

Après validation de la migration, retirer les branches de génération historiques,
`DirectLLMClient` et les écrans obsolètes. Examiner les références avant de supprimer
les clients OAuth ; ne pas toucher au runtime de l’agent par simple rapprochement de nom.

Auditer `Package.swift` et `Package.resolved` : Gemma4Swift est lié au LLM intégré,
mais `mlx-swift-lm` fournit aussi les embeddings et d’autres dépendances peuvent
encore consommer MLX. **Ne pas supprimer MLX/Metal globalement** : STT, VAD,
diarisation et éventuellement embeddings locaux en dépendent. Les caches de modèles
ne sont pas supprimés automatiquement.

Fin : audit des imports et appels directs restants, `swift build`, `swift test`,
application packagée avec transcription/live/diarisation/embeddings toujours fonctionnels.
Mettre à jour `docs/architecture.md`, `CLAUDE.md`, README et `STATUS.md` pour décrire
le comportement effectivement livré.

### Lot 7 — Extensions audio et agent, à cadrer séparément

**Audio OpenRouter** : faire évoluer `STTEngine` vers un contrat audio indépendant
de `MLXArray`, erreurs explicites et résultat structuré. Créer un adaptateur STT,
un catalogue de modèles de transcription et des réglages distincts. Évaluer longs
enregistrements, découpage, timestamps, langue française, qualité et annulation.
Pour une première extension, garder la diarisation locale et transcrire ses tours
de parole à distance préserverait l’identité vocale, au prix de nombreux appels.
Comparer cette option à la transcription distante complète avec labels anonymes.
La migration live exige des mesures de délai, de débit et de fusion ; elle n’est pas
acquise par l’ajout d’une route STT.

**Agent de tâches** : choisir entre un runtime existant compatible avec les endpoints
ou une boucle d’agent propre à OneToOne. Préserver accès aux fichiers, outils Office,
web, permissions, sessions, budget, annulation et contrat `etat.json`. Le choix du
modèle seul ne remplace pas `AgentCommandBuilder`, `AgentStreamDecoder` et
`AgentTurnRunner`. Évaluer les capacités du runtime retenu avant de promettre que
l’agent utilisera les mêmes réglages que les rapports.

## 6. Validation globale et décisions proposées

Ordre : **configuration → transport → réglages → usages métier → embeddings →
nettoyage**, puis extensions éventuelles. Chaque livraison conserve une application
exploitable et possède ses propres critères de fin.

Avant une PR de code : tests ciblés ci-dessus puis `swift test` complet conformément
aux règles du dépôt. Recette sur l’app packagée pour le réseau local, le Trousseau,
le streaming et les fonctions audio. Les tests automatisés n’appellent pas un modèle
payant et ne téléchargent pas de poids. La recette API utilise des données synthétiques
et des modèles réellement disponibles ; aucun choix de modèle précis n’est imposé ici.

Choix proposés à valider lors du lancement de l’implémentation :

- Première livraison centrée sur les usages textuels, avec audio et embeddings locaux.
- Deux profils d’endpoint mémorisés, un modèle de génération commun ; modèle
  d’embeddings séparé dans un deuxième temps.
- Classement des mails distant activé explicitement ; génération sans repli cloud automatique.
- Compatibilité temporaire avec les anciens réglages, puis retrait des fournisseurs
  directs lorsque la migration est éprouvée.
- Transcription distante et runtime d’agent traités comme deux chantiers supplémentaires.

Le gain initial est la suppression du couplage entre fonctions métier et chargement
du LLM dans l’application. Une suppression complète de l’inférence locale nécessiterait
en plus le remplacement des traitements audio et vocaux : ce n’est pas une conséquence
automatique de cette migration des endpoints.
