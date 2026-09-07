#!/bin/bash
# recette-run.sh — lance le .app de recette dans un HOME jetable.
#
# À quoi ça sert
#   Une recette visuelle a besoin de données : le jeu de démonstration de la
#   refonte (`RefonteDemoSeed`). Le semer dans le store de production
#   ajouterait six collaborateurs, douze actions et cinq risques fictifs aux
#   vraies données de l'utilisateur. Ce script lance le bundle avec un `HOME`
#   temporaire : le store SwiftData atterrit sous
#   `<home>/Library/Application Support/OneToOne/OneToOne.store` et le store
#   réel n'est jamais ouvert.
#
#   `--seed` pose `ONETOONE_SEED_DEMO=1`, lu au démarrage par `ContentView` :
#   la réunion de démonstration est semée et ouverte sans passer par le menu.
#
# Usage
#   Scripts/recette-app.sh /tmp/recette
#   Scripts/recette-run.sh --app /tmp/recette/OneToOne.app --seed
#
#   --app <bundle>   défaut : "${TMPDIR}/onetoone-recette/OneToOne.app"
#   --home <dossier> défaut : <dossier du bundle>/home — réutilisable d'un
#                    lancement à l'autre pour retrouver l'état de la veille
#   --seed           pose ONETOONE_SEED_DEMO=1
#   --reset          efface le HOME de recette avant de lancer
#   --wait           reste au premier plan (par défaut, le script rend la main)
#
# ⚠️ N'utilise **jamais** ce script sans `--home` pointant un dossier jetable :
# tout ce que l'application écrit (store, réglages, enregistrements) va dans ce
# HOME. Le Trousseau, lui, reste celui de la session : un endpoint IA configuré
# hors recette peut donc être lu. C'est voulu — sinon l'encart de suggestions
# serait intestable en recette.

set -e

APP=""
FAKE_HOME=""
SEED=""
RESET=""
WAIT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --app)    APP="$2"; shift 2 ;;
        --app=*)  APP="${1#*=}"; shift ;;
        --home)   FAKE_HOME="$2"; shift 2 ;;
        --home=*) FAKE_HOME="${1#*=}"; shift ;;
        --seed)   SEED="1"; shift ;;
        --reset)  RESET="1"; shift ;;
        --wait)   WAIT="1"; shift ;;
        -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
        *)
            echo "✗ Argument inconnu : $1 (voir --help)"
            exit 1
            ;;
    esac
done

if [ -z "${APP}" ]; then
    APP="${TMPDIR:-/tmp}onetoone-recette/OneToOne.app"
fi
BINARY="${APP}/Contents/MacOS/OneToOne"

if [ ! -x "${BINARY}" ]; then
    echo "✗ Bundle de recette introuvable : ${APP}"
    echo "  Lance d'abord : Scripts/recette-app.sh"
    exit 1
fi

if [ -z "${FAKE_HOME}" ]; then
    FAKE_HOME="$(dirname "${APP}")/home"
fi

if [ -n "${RESET}" ]; then
    echo "→ Effacement du HOME de recette : ${FAKE_HOME}"
    rm -rf "${FAKE_HOME}"
fi
mkdir -p "${FAKE_HOME}/Library/Application Support"

echo "→ HOME de recette : ${FAKE_HOME}"
[ -n "${SEED}" ] && echo "→ ONETOONE_SEED_DEMO=1 (jeu de démonstration semé au démarrage)"

export HOME="${FAKE_HOME}"
[ -n "${SEED}" ] && export ONETOONE_SEED_DEMO=1

if [ -n "${WAIT}" ]; then
    exec "${BINARY}"
else
    "${BINARY}" > "${FAKE_HOME}/app.log" 2>&1 &
    echo "✓ Lancé (pid $!) — journal : ${FAKE_HOME}/app.log"
fi
