# Endpoints IA configurables — LM Studio et OpenRouter

Statut : accepté pour les lots 1 à 4. Validation : 2026-09-05, accord utilisateur
« Go » sur le plan `docs/superpowers/plans/2026-09-05-architecture-ia-endpoints.md`.

## Contexte

OneToOne chargeait un LLM MLX dans son processus par défaut. Les autres fournisseurs
partageaient des champs de réglages ; le classement des mails contournait le routeur
et imposait MLX. L’objectif est de choisir un endpoint puis son modèle dans l’app.

## Décision

- Ajouter LM Studio et OpenRouter, avec un profil mémorisé par fournisseur.
- Conserver `AIClient` comme façade métier et introduire un transport HTTP compatible
  OpenAI pour ces deux endpoints, sans SDK supplémentaire.
- Figer la configuration en une valeur avant l’appel réseau. Lire les modèles via
  le catalogue, proposer une recherche et autoriser la saisie manuelle d’identifiant.
- Utiliser un formulaire de brouillon avec test indépendant de l’enregistrement.
- Stocker les secrets dans le Trousseau, les références de secrets et profils en
  SwiftData. Migrer à la première utilisation ou ouverture des réglages, sans vider
  l’ancienne clé tant que l’écriture et sa vérification n’ont pas réussi.
- Exporter les profils sans clés ni références de secrets ; conserver la lecture des
  anciens backups. Après restauration, le classement distant des mails est désactivé.
- Faire passer le classement des mails par `AIClient`. Exiger une activation pour
  les endpoints hors de la boucle locale ; garder le repli heuristique.
- Conserver temporairement les fournisseurs historiques, les embeddings et l’audio
  locaux, l’OCR Vision et le runtime Claude CLI de l’agent.

## Alternatives

Remplacer tous les moteurs d’IA par un même endpoint ne couvre pas les empreintes
vocales ni les outils de l’agent. Supprimer immédiatement les fournisseurs historiques
forcerait la reconfiguration des installations existantes. Un SDK par fournisseur
n’apporte pas d’avantage pour le contrat HTTP utilisé ici.

## Conséquences

Les installations neuves proposent LM Studio sans modèle présélectionné. Les stores
existants gardent leur fournisseur et leur modèle. Les nouveaux profils utilisent
les mêmes services métier et parseurs ; le choix d’un modèle reste déterminant pour
la qualité et la taille du contexte.

Le SSE doit être lu au niveau des octets : `URLSession.AsyncBytes.lines` omet les
lignes vides nécessaires au découpage des événements. Une fin absente, une erreur,
un refus ou une sortie tronquée ne doit pas être traitée comme un résultat terminé.

Les réglages d’embeddings restent indépendants. Leur migration, le retrait de MLX
et la transcription distante ne font pas partie de cette livraison. La compatibilité
du catalogue ne dispense pas d’une recette avec le serveur et le modèle réellement
utilisés.
