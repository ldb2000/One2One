#!/bin/zsh
# Hook PostToolUse (Bash) : après `gh pr create` ou `git push`, si la PR touche un dossier
# listé dans docs/documentation.yml (code_documente), injecte à l'agent la consigne de lancer
# le skill documenter-application. N'écrit rien, ne bloque jamais (exit 0).
# Enregistrement : ~/.claude/settings.json, PostToolUse, matcher Bash ; le `~` n'étant pas
# développé dans `command`, écrire "$HOME/.claude/hooks/documentation-apres-pr.sh".
set -u
entree=$(cat)
commande=$(printf '%s' "$entree" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command",""))' 2>/dev/null) || exit 0
case "$commande" in
  *"gh pr create"*|*"git push"*) ;;
  *) exit 0 ;;
esac
cwd=$(printf '%s' "$entree" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null)
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null
racine=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
manifeste="$racine/docs/documentation.yml"
[ -f "$manifeste" ] || exit 0
base=$(sed -n 's/^branche_principale:[[:space:]]*//p' "$manifeste" | head -1); base=${base:-master}
dossiers=$(awk '/^code_documente:/{f=1;next} /^[^ ]/{f=0} f && /^[[:space:]]*-[[:space:]]*/{sub(/^[[:space:]]*-[[:space:]]*/,""); print}' "$manifeste")
[ -n "$dossiers" ] || exit 0
changes=$(git -C "$racine" diff --name-only "origin/$base...HEAD" 2>/dev/null || git -C "$racine" diff --name-only "$base...HEAD" 2>/dev/null)
touches=""
# Ancrage au préfixe de chemin depuis la racine du dépôt (pas de sous-chaîne libre) :
# une entrée dossier ("Scripts/") matche un préfixe ("Scripts/x.sh") ; une entrée fichier
# ("Package.swift") exige une égalité stricte (pour ne pas matcher "Package.swift.bak" ni
# "Prototypes/BlockEditorProbe/Package.swift").
while IFS= read -r d; do
  [ -n "$d" ] || continue
  compte=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$d" in
      */)
        case "$f" in
          "$d"*) touches="$touches$f"$'\n'; compte=$((compte + 1)) ;;
        esac
        ;;
      *)
        case "$f" in
          "$d") touches="$touches$f"$'\n'; compte=$((compte + 1)) ;;
        esac
        ;;
    esac
    [ "$compte" -ge 5 ] && break
  done <<< "$changes"
done <<< "$dossiers"
[ -n "$touches" ] || exit 0
liste=$(printf '%s' "$touches" | sort -u | tr '\n' ' ')
python3 - "$liste" <<'PY'
import json, sys
msg = ("Documentation : cette PR modifie du code documenté (" + sys.argv[1].strip() + "). "
       "Lancer le skill documenter-application avant de clore, puis pousser le commit de documentation "
       "sur la branche de la PR.")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg}}))
PY
exit 0
