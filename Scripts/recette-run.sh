#!/bin/bash
# recette-run.sh — lance le .app de recette dans un HOME jetable.
#
# À quoi ça sert
#   Une recette visuelle a besoin de données : le jeu de démonstration de la
#   refonte (`RefonteDemoSeed`). Le semer dans le store de production
#   ajouterait un projet, une réunion, douze actions et cinq risques fictifs
#   aux vraies données de l'utilisateur. Ce script lance le bundle avec un
#   « home » jetable : le store SwiftData atterrit sous
#   `<home>/Library/Application Support/OneToOne/OneToOne.store` et le store
#   réel n'est jamais ouvert.
#
#   ⚠️ `HOME` **ne suffit pas**. `URL.applicationSupportDirectory` passe par
#   `NSHomeDirectory()`, qui pour une application **en bundle** lit la base des
#   utilisateurs et ignore `HOME` : le 7 septembre 2026, une recette lancée
#   avec le seul `HOME` a ouvert le store de production et y a semé le jeu de
#   démonstration. La variable qui compte est `CFFIXED_USER_HOME`, honorée par
#   Core Foundation. Les deux sont posées, et un **garde-fou** vérifie après
#   lancement que le store apparaît bien dans le home jetable : sinon le
#   processus est tué immédiatement.
#
#   `--seed` pose `ONETOONE_SEED_DEMO=1`, lu au démarrage par `ContentView` :
#   la réunion de démonstration est semée et ouverte sans passer par le menu.
#
#   `--screen <code>` pose `ONETOONE_SEED_DEMO_SCREEN=<code>` et implique
#   `--seed`. Le code est celui de la capture de référence
#   (`docs/superpowers/specs/refonte-2026-09/ecrans/`) : l'application sème
#   alors tout le jeu de la refonte et ouvre **cet** écran, au bon mode, sans
#   un clic. C'est le crochet unique de la recette depuis l'intégration de la
#   vague 5 — il remplace `ONETOONE_SEED_OPEN`, que le lot 12 avait ajouté à
#   côté. Table : `OneToOne/Services/Debug/RecetteScreen.swift`.
#
#     1a  cockpit de réunion (En séance)      1c  poste de pilotage (Relire)
#     1b  espaces et indicateurs (En séance)  2a  1:1 mené, En séance
#     3a  tiroir Ressources (En séance)       2b  1:1 mené, Préparer
#     3b  fiche projet en panneau             4a  sélecteur de capture
#     6a  atelier, planche plein cadre
#
# Usage
#   Scripts/recette-app.sh /tmp/recette
#   Scripts/recette-run.sh --app /tmp/recette/OneToOne.app --seed
#   Scripts/recette-run.sh --app /tmp/recette/OneToOne.app --screen 2b
#
#   --app <bundle>   défaut : "${TMPDIR}/onetoone-recette/OneToOne.app"
#   --home <dossier> défaut : <dossier du bundle>/home — réutilisable d'un
#                    lancement à l'autre pour retrouver l'état de la veille
#   --seed           pose ONETOONE_SEED_DEMO=1
#   --screen <code>  pose ONETOONE_SEED_DEMO_SCREEN=<code> et implique --seed
#   --reset          efface le HOME de recette avant de lancer
#   --wait           reste au premier plan (par défaut, le script rend la main)
#
# Le Trousseau, lui, reste celui de la session : un endpoint IA configuré hors
# recette peut donc être lu. C'est voulu — sinon l'encart de suggestions serait
# intestable en recette. En revanche `UserDefaults` suit le home jetable, donc
# les réglages de l'application (endpoint choisi, modèle) repartent des défauts.

set -e

APP=""
FAKE_HOME=""
SEED=""
SCREEN=""
RESET=""
WAIT=""

# Les codes acceptés par `RecetteScreen`. Vérifiés ici, parce qu'une faute de
# frappe passerait autrement inaperçue : l'application retomberait sur le
# cockpit et la capture serait celle du mauvais écran.
SCREENS="1a 1b 1c 2a 2b 3a 3b 4a 6a"

while [ $# -gt 0 ]; do
    case "$1" in
        --app)    APP="$2"; shift 2 ;;
        --app=*)  APP="${1#*=}"; shift ;;
        --home)   FAKE_HOME="$2"; shift 2 ;;
        --home=*) FAKE_HOME="${1#*=}"; shift ;;
        --seed)   SEED="1"; shift ;;
        --screen)   SCREEN="$2"; SEED="1"; shift 2 ;;
        --screen=*) SCREEN="${1#*=}"; SEED="1"; shift ;;
        --reset)  RESET="1"; shift ;;
        --wait)   WAIT="1"; shift ;;
        -h|--help) sed -n '2,48p' "$0"; exit 0 ;;
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

if [ -n "${SCREEN}" ]; then
    case " ${SCREENS} " in
        *" ${SCREEN} "*) ;;
        *)
            echo "✗ Code d'écran inconnu : ${SCREEN}"
            echo "  Codes acceptés : ${SCREENS}"
            exit 1
            ;;
    esac
fi

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
[ -n "${SCREEN}" ] && echo "→ ONETOONE_SEED_DEMO_SCREEN=${SCREEN} (écran ouvert au démarrage)"

export HOME="${FAKE_HOME}"
# La variable qui isole réellement : `NSHomeDirectory()` ignore `HOME` pour une
# application en bundle, pas `CFFIXED_USER_HOME`.
export CFFIXED_USER_HOME="${FAKE_HOME}"
[ -n "${SEED}" ] && export ONETOONE_SEED_DEMO=1
[ -n "${SCREEN}" ] && export ONETOONE_SEED_DEMO_SCREEN="${SCREEN}"

STORE="${FAKE_HOME}/Library/Application Support/OneToOne/OneToOne.store"

if [ -n "${WAIT}" ]; then
    # Mode premier plan : pas de garde-fou possible (le script cède son
    # processus). À réserver au débogage, sur un poste sans store réel.
    echo "⚠️  --wait : aucun garde-fou d'isolation. Vérifie toi-même que"
    echo "    ${STORE}"
    echo "    est bien créé, et arrête l'application sinon."
    exec "${BINARY}"
fi

"${BINARY}" > "${FAKE_HOME}/app.log" 2>&1 &
PID=$!
echo "✓ Lancé (pid ${PID}) — journal : ${FAKE_HOME}/app.log"

# ----------------------------------------------------------------------
# Garde-fou d'isolation. Si le store n'apparaît pas dans le home jetable,
# l'application a ouvert celui de production : on la tue sans attendre.
# ----------------------------------------------------------------------
for _ in $(seq 1 30); do
    if [ -f "${STORE}" ]; then
        echo "✓ Isolation vérifiée : ${STORE}"
        exit 0
    fi
    if ! kill -0 "${PID}" 2>/dev/null; then
        echo "✗ Le processus s'est arrêté avant de créer son store."
        echo "  Journal : ${FAKE_HOME}/app.log"
        exit 1
    fi
    sleep 0.5
done

kill -9 "${PID}" 2>/dev/null || true
echo "✗ ISOLATION ÉCHOUÉE — aucun store dans le home jetable après 15 s."
echo "  L'application a probablement ouvert le store de production ;"
echo "  le processus vient d'être tué. Vérifie"
echo "  \"\${HOME}/Library/Application Support/OneToOne/OneToOne.store\"."
exit 1
