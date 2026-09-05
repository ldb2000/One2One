# Niveau de raisonnement par profil et limite de sortie relevée

Statut : accepté le 2026-09-05, après investigation d’un rapport LM Studio resté en
raisonnement plus de dix minutes, puis discussion avec l’utilisateur. Complète
`2026-09-05-endpoints-ia-configurables.md`.

## Constat

Le template `chat_template.jinja` de Qwen3.8 active le raisonnement en « xhigh » par
défaut. À 8,4 tokens/s sur LM Studio, un rapport complet raisonne plusieurs milliers de
tokens avant la première ligne utile, et la limite de sortie de 8 192 tokens, partagée
entre réflexion et rapport, risque de tronquer ce dernier.

Vérifications réelles (prompt rendu observé avec `lms log stream`) :

- LM Studio 0.4.23 ignore `reasoning_effort`, `reasoning: {effort}` et
  `chat_template_kwargs` sur `/v1/chat/completions`. `/api/v1/chat` refuse `reasoning`
  pour ce modèle (HTTP 400). `/v1/responses` ignore `reasoning.effort`. `/no_think`
  dans le prompt allonge le raisonnement et tronque la sortie.
- Sur LM Studio, une consigne système reprenant le texte « low » du template divise le
  raisonnement par 3 à 4 ; un message assistant final `\n</think>\n\n` est repris
  comme continuation et supprime toute réflexion, y compris en streaming.
- Ollama 0.33.2 honore `reasoning_effort` (low, medium, high, xhigh, none) en l’injectant
  dans le template. OpenRouter documente `reasoning: {effort}` avec les mêmes valeurs.

## Décision

- Ajouter `AIEndpointProfile.reasoning` (`AIReasoningLevel` : défaut, désactivé, faible,
  moyen, élevé, maximal), persisté dans le JSON des profils. « Défaut » laisse la requête
  strictement inchangée.
- Mapper par fournisseur : Ollama `reasoning_effort`, OpenRouter `reasoning.effort`,
  LM Studio consigne système reprise du template Qwen (`high` aligné sur `xhigh`, comme
  Ollama ; `medium` rédigé dans le même style, non mesuré). La désactivation LM Studio
  préremplit un bloc de réflexion vide et n’est proposée que si l’identifiant du modèle
  contient « qwen », faute de vérification sur d’autres familles.
- Relever la limite de sortie par défaut à 24 576 tokens. Un profil antérieur au réglage
  (sans clé `reasoning`) resté à 8 192 est relevé une fois au décodage, puis réécrit ;
  toute autre valeur est conservée. Un niveau inconnu retombe sur le défaut.
- Conserver l’avertissement après deux minutes ; ne rien modifier côté LM Studio ou
  Ollama (templates, model.yaml, réglages du serveur).

## Alternatives écartées

Réduire `max_tokens` aurait tronqué le rapport sans raccourcir la réflexion. Modifier le
template du modèle agit hors de l’application et pour tous ses clients. Passer LM Studio
par `/v1/responses` ou `/api/v1/chat` ne change rien pour ce modèle. Envoyer le
préremplissage à tout modèle LM Studio risquait d’insérer un texte parasite hors Qwen.

## Conséquences

Le réglage se teste sur le brouillon (« Tester la connexion ») avant enregistrement et
s’applique à tous les usages passant par `AIClient`. Le test réel facultatif
`liveReasoning` (`ONETOONE_AI_LIVE_REASONING=1`) vérifie l’absence ou la présence de
deltas de raisonnement sur les serveurs locaux. Sur OpenRouter, les modèles à raisonnement
obligatoire refusent « Désactivé » ; le mapping y reste documentaire, non testé.
