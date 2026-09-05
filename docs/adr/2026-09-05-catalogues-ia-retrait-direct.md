# Catalogues IA, Ollama et retrait du moteur Direct

Statut : accepté le 2026-09-05, à la demande explicite de l’utilisateur après essai
du premier écran IA. Complète et remplace les décisions concernées de
`2026-09-05-endpoints-ia-configurables.md`.

## Constat

Le formulaire utilisait des `TextField` SwiftUI alors que le projet possède un
wrapper AppKit pour contourner les difficultés de clavier dans la colonne détail.
La recherche filtrait uniquement un catalogue préalablement chargé. La validation
exigeait aussi une clé pour consulter le catalogue public OpenRouter.

Vérifications réelles : le catalogue OpenRouter répond HTTP 200 sans clé ; le serveur
LM Studio de l’utilisateur répond HTTP 401 et demande un jeton Bearer. Ce refus doit
être affiché près de la liste et pouvoir être corrigé dans un champ sécurisé utilisable.

## Décision

- Employer `EditableTextField`, avec `NSSecureTextField` pour les clés. Renouveler
  le binding du coordinateur lors du changement de profil.
- Charger automatiquement le catalogue au choix d’un endpoint ; garder recherche,
  rafraîchissement manuel et saisie d’identifiant. Fixer la hauteur de la liste dans
  le panneau défilant et conserver un message de catalogue distinct du test.
- Autoriser le catalogue OpenRouter sans clé ; continuer d’exiger une clé pour générer.
  Transmettre le jeton facultatif aux serveurs locaux qui l’exigent.
- Promouvoir Ollama au même niveau que LM Studio/OpenRouter, via `/v1/models` et
  `/v1/chat/completions` dans le transport partagé.
- Retirer `DirectLLMClient`, le lien direct MLXLLM de l’application, Gemma4Swift et
  la dépendance transitive de profilage devenue inutile. Conserver les bibliothèques
  nécessaires aux embeddings et à l’audio ; MLXLLM peut encore être transitif via STT.
- Conserver les anciennes valeurs persistées pour les migrations, masquer Direct
  du sélecteur et migrer son profil actif vers LM Studio. Réutiliser un profil LM Studio
  déjà enregistré ; sinon laisser le choix de modèle vide. Ne pas effacer les caches
  partagés de poids, qui peuvent également être utilisés par d’autres applications.

## Alternatives et conséquences

Masquer uniquement Direct aurait conservé son moteur et ses dépendances dans le build.
Conserver la saisie SwiftUI aurait laissé le même problème sur la recherche et la clé.
Le retrait réduit les composants propres au LLM intégré, sans promettre la suppression
de tous les composants MLX ni la libération des fichiers de poids partagés.
