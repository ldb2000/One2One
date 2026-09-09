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
#   ⚠️ `CFFIXED_USER_HOME` isole `NSHomeDirectory()`, **pas `cfprefsd`** : les
#   `UserDefaults` du bundle de recette restent dans le vrai
#   `~/Library/Preferences/`. Ce n'est pas un oubli, c'est indépassable — le
#   démon de préférences ne lit aucune des deux variables. Voir le piège n° 6.
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
#     1a  cockpit de réunion (En séance)        1c  poste de pilotage (Relire)
#     1b  espaces et indicateurs (En séance)    2a  1:1 mené, En séance
#     3a  tiroir Ressources (En séance)         2b  1:1 mené, Préparer
#     3b  fiche projet en panneau               4a  sélecteur de capture
#     5a  1:1 subi, En séance                   5b  1:1 subi, Préparer
#     6a  atelier, planche plein cadre          6b  atelier, planche de séance
#
#   Cette liste est **lue** dans `RecetteScreen.swift`, pas recopiée : la
#   recopier l'avait déjà fait diverger (le code `5a` du lot 13 manquait ici
#   alors que la table le déclarait, et une faute de frappe aurait ouvert le
#   cockpit sans le dire). Le tableau ci-dessus est donc indicatif : le script
#   accepte exactement ce que la table déclare, ni plus ni moins.
#
# Deux gardes avant lancement
#   Verrou d'écran : sur session verrouillée, toute capture est noire et le
#   redimensionnement par l'API Accessibility échoue en silence — cinq recettes
#   de la refonte ont été perdues ainsi. La clé est rendue **sans espaces**
#   autour du `=` par `ioreg -r` : chercher `"CGSSessionScreenIsLocked" = Yes`
#   ne correspond jamais.
#   Teams (ou Zoom) en réunion : la recette redimensionne des fenêtres et
#   photographie l'écran. Les titres de fenêtres sont lus par
#   `CGWindowListCopyWindowInfo`, via `Scripts/window-titles.swift`, et
#   **jamais par AppleScript** — « first process whose unix id is … » résout mal
#   le processus quand deux instances partagent le `CFBundleIdentifier`, et
#   c'est ce qui a redimensionné une fenêtre de production le 7 septembre 2026.
#   En Swift et non en Python : `Quartz` (pyobjc) n'est pas dans le python3 du
#   système sur ce poste.
#
# Piège n° 6 — les préférences et l'état des fenêtres ne suivent pas le home
#   jetable, et sont partagés par identifiant de bundle.
#   `CFFIXED_USER_HOME` isole `NSHomeDirectory()`, **pas `cfprefsd`** : les
#   réglages du bundle de recette vont dans le **vrai**
#   `~/Library/Preferences/<CFBundleIdentifier>.plist`, et son état de fenêtres
#   dans le vrai `~/Library/Saved Application State/`. Ni l'un ni l'autre n'est
#   effacé par `--reset` version d'origine, et **deux bundles de recette
#   empaquetés dans deux dossiers partagent le même identifiant**, donc les
#   mêmes réglages et les mêmes cadres de fenêtres.
#
#   Ce que ça a coûté, le 9 septembre 2026 : le domaine portait un cadre de
#   fenêtre principale à `x = 2048`, sur un second écran 1920 × 1050 débranché
#   depuis. Restaurée là, la fenêtre principale était entièrement hors de tout
#   écran — aucune surface, aucun rendu, `onAppear` jamais parti, aucun semis.
#   Le garde-fou d'isolation affichait pourtant « ✓ » (voir le piège n° 7), et
#   la seule fenêtre visible de la session — celle d'un binaire lancé hors
#   bundle sept heures plus tôt, immobile sur un `ProgressView` — a été prise
#   pour celle du bundle en recette. Trois heures de diagnostic.
#
#   Deux parades, toutes deux en place :
#     • `-ApplePersistenceIgnoreState YES` au lancement — AppKit repart d'une
#       session vierge, sans rouvrir les fenêtres de la fois précédente ;
#     • sous `--reset`, `defaults delete <bundle id>` + `killall cfprefsd`
#       (sans le second, le cache du démon réécrit ce qu'on efface), **et
#       seulement sur un identifiant suffixé `.recette`** — jamais sur
#       `com.onetoone.app`, le bundle de l'utilisateur.
#   Corollaire à vérifier soi-même : `ps -Ao pid,lstart,command | grep -i
#   onetoone` avant de capturer. Une fenêtre OneToOne n'est pas forcément la
#   sienne.
#
# Piège n° 7 — lire le store de recette sans le journal WAL rend zéro partout.
#   Le store SwiftData est en mode WAL : le fichier `OneToOne.store` seul ne
#   contient pas les écritures récentes, qui vivent dans `OneToOne.store-wal`.
#   Une première mesure du 9 septembre 2026 a conclu « store vide, l'application
#   ne sème rien » sur un store qui portait soixante-seize projets — le `-wal`
#   pesait 333 Ko. Pour interroger le store, **copier les trois fichiers** :
#
#     cp "<store>" "<store>-wal" "<store>-shm" /tmp/chk/
#     sqlite3 /tmp/chk/OneToOne.store 'select count(*) from ZPROJECT;'
#
#   C'est ce que fait la fonction `gabarits_semes` de ce script.
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
#   --ignore-lock    lance malgré une session verrouillée
#   --ignore-teams   lance malgré une réunion Teams détectée
#
# Vérification (manuelle — aucun test SwiftPM n'exécute un script shell)
#   1. Scripts/recette-run.sh --help
#      → douze codes listés
#   2. sed -n 's/^ *case [a-zA-Z]* = "\([0-9a-z]*\)"/\1/p' \
#        OneToOne/Services/Debug/RecetteScreen.swift | tr '\n' ' '
#      → la même liste que celle que le script accepte : douze codes de réunion
#        plus les six écrans préfixés `p` de la refonte de la gestion des
#        projets (`p2b p1a p1c p1d p1f p2a`), qui ouvrent la fenêtre
#        principale et non une réunion
#   3. ioreg -n Root -d1 -r | grep -c 'CGSSessionScreenIsLocked"=Yes'
#      → 1 écran verrouillé (le script doit refuser), 0 déverrouillé
#   4. Scripts/recette-run.sh --screen 9z --app … → « Code d'écran inconnu »
#   5. swift Scripts/window-titles.swift MSTeams MicrosoftTeams
#      → une ligne par fenêtre Teams nommée ; « Calendar | APRIL | … » ne
#        déclenche rien, un titre de réunion oui
#   6. ps -Ao pid,lstart,command | grep -i onetoone | grep -v grep
#      → aucune autre instance de OneToOne. Sinon sa fenêtre serait confondue
#        avec celle de la recette (piège n° 6) — à arrêter soi-même, le script
#        ne tue jamais un processus qui n'est pas le sien
#   7. après lancement, en copiant les **trois** fichiers du store (piège n° 7)
#      → `select count(*) from ZREPORTTEMPLATE` > 0 : la fenêtre principale a
#        bien été rendue. C'est ce que le script vérifie désormais lui-même
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
IGNORE_LOCK=""
IGNORE_TEAMS=""

# Les codes acceptés par `RecetteScreen`, **lus dans la table** et non
# recopiés. Une faute de frappe passerait autrement inaperçue (l'application
# retomberait sur le cockpit, et la capture serait celle du mauvais écran) — et
# une liste recopiée finit par mentir : celle-ci ignorait `5a`, ajouté au
# lot 13.
RECETTE_SCREEN_SWIFT="OneToOne/Services/Debug/RecetteScreen.swift"
SCREENS=""
if [ -f "${RECETTE_SCREEN_SWIFT}" ]; then
    SCREENS="$(sed -n 's/^ *case [a-zA-Z]* = "\([0-9a-z]*\)"/\1/p' \
        "${RECETTE_SCREEN_SWIFT}" | tr '\n' ' ')"
fi
if [ -z "${SCREENS}" ]; then
    # Repli : le script s'utilise aussi hors du dépôt, à côté du seul bundle.
    SCREENS="1a 1b 1c 2a 2b 3a 3b 4a 5a 5b 6a 6b p2b p1a p1c p1d p1f p2a "
    echo "⚠️  ${RECETTE_SCREEN_SWIFT} illisible — liste de codes par défaut."
fi

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
        --ignore-lock)  IGNORE_LOCK="1"; shift ;;
        --ignore-teams) IGNORE_TEAMS="1"; shift ;;
        -h|--help) sed -n '2,88p' "$0"; exit 0 ;;
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

# ----------------------------------------------------------------------
# Garde 1 — verrou d'écran. Sur session verrouillée, `screencapture` rend une
# image noire et `AXUIElement…` échoue sans message : la recette « réussit »
# et ne montre rien. La clé n'a pas d'espaces autour du `=` dans la sortie de
# `ioreg -r`, contrairement à ce que les comptes rendus des lots 1 à 5
# cherchaient.
# ----------------------------------------------------------------------
if [ -z "${IGNORE_LOCK}" ] \
   && ioreg -n Root -d1 -r | grep -q 'CGSSessionScreenIsLocked"=Yes'; then
    echo "✗ Session graphique verrouillée : toute capture serait noire et le"
    echo "  redimensionnement échouerait en silence."
    echo "  Déverrouille l'écran puis relance (--ignore-lock pour forcer)."
    exit 1
fi

# ----------------------------------------------------------------------
# Garde 2 — Teams en réunion. La recette redimensionne des fenêtres et
# photographie l'écran : pendant un appel, c'est exclu. On lit les titres des
# fenêtres du processus `MSTeams` par `CGWindowListCopyWindowInfo` ; **jamais**
# par AppleScript (cf. l'en-tête). Le filtre reste littéral : le 7 septembre
# 2026, la seule fenêtre `MSTeams` portait « Calendar | APRIL | … », qui ne
# déclenche rien.
# ----------------------------------------------------------------------
# `Scripts/window-titles.swift` lit `CGWindowListCopyWindowInfo` et rend une
# ligne par fenêtre nommée. En Swift et non en Python : `Quartz` (pyobjc) n'est
# pas dans le python3 du système, et un garde-fou muet serait pire qu'aucun
# garde-fou. Il vit à côté de ce script ; s'il manque, on le dit.
TITRES_SWIFT="$(dirname "$0")/window-titles.swift"

if [ -z "${IGNORE_TEAMS}" ]; then
    if [ ! -f "${TITRES_SWIFT}" ] || ! command -v swift >/dev/null 2>&1; then
        echo "⚠️  Garde Teams inactive : ${TITRES_SWIFT} ou swift introuvable."
        echo "    Vérifie toi-même qu'aucune réunion n'est en cours."
    else
        EN_REUNION="$(swift "${TITRES_SWIFT}" MSTeams MicrosoftTeams Teams zoom.us 2>/dev/null \
            | grep -iE 'réunion|reunion|meeting|appel|call|en cours' | head -1)"
        if [ -n "${EN_REUNION}" ]; then
            echo "✗ Une réunion ou un appel semble en cours :"
            echo "  ${EN_REUNION}"
            echo "  La recette redimensionne des fenêtres et capture l'écran."
            echo "  Attends la fin de l'appel (--ignore-teams pour forcer)."
            exit 1
        fi
    fi
fi

if [ -z "${FAKE_HOME}" ]; then
    FAKE_HOME="$(dirname "${APP}")/home"
fi

# Le vrai home de l'utilisateur, **capturé avant** l'`export HOME` ci-dessous :
# c'est là que vivent les préférences du bundle de recette, que
# `CFFIXED_USER_HOME` n'isole pas (piège n° 6).
HOME_REEL="${HOME}"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "${APP}/Contents/Info.plist" 2>/dev/null || true)"

if [ -n "${RESET}" ]; then
    echo "→ Effacement du HOME de recette : ${FAKE_HOME}"
    rm -rf "${FAKE_HOME}"

    # ------------------------------------------------------------------
    # Piège n° 6 — les préférences ne suivent pas le home jetable.
    # `cfprefsd` n'honore ni `HOME` ni `CFFIXED_USER_HOME` : le domaine du
    # bundle de recette est le **vrai**
    # `~/Library/Preferences/<bundle id>.plist`. Le 2026-09-09, il portait un
    # cadre de fenêtre principale à x = 2048, sur un écran débranché : la
    # fenêtre était restaurée hors de tout écran, donc jamais rendue,
    # `onAppear` jamais parti, aucun semis — et la seule fenêtre visible de la
    # session, celle d'un autre processus, a été photographiée à sa place.
    # Trois heures de diagnostic.
    #
    # Le `killall cfprefsd` n'est pas décoratif : sans lui, le cache du démon
    # réécrit le domaine qu'on vient d'effacer.
    #
    # **Garde-fou** : on n'efface qu'un domaine suffixé `.recette…`. Le bundle
    # de Laurent est `com.onetoone.app` — effacer ses réglages (endpoint IA,
    # gabarits, fenêtres) pour une capture d'écran serait impardonnable.
    # ------------------------------------------------------------------
    case "${BUNDLE_ID}" in
        *.recette|*.recette.*)
            echo "→ Effacement des réglages de recette : ${BUNDLE_ID}"
            defaults delete "${BUNDLE_ID}" 2>/dev/null || true
            rm -rf "${HOME_REEL}/Library/Saved Application State/${BUNDLE_ID}.savedState"
            killall cfprefsd 2>/dev/null || true
            ;;
        "")
            echo "⚠️  CFBundleIdentifier illisible dans ${APP}/Contents/Info.plist :"
            echo "    les réglages du bundle de recette ne sont pas effacés."
            ;;
        *)
            echo "⚠️  ${BUNDLE_ID} n'est pas un identifiant de recette (suffixe"
            echo "    « .recette » attendu) : ses réglages ne sont **pas** effacés."
            echo "    Reconstruis le bundle avec Scripts/recette-app.sh."
            ;;
    esac
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
    exec "${BINARY}" -ApplePersistenceIgnoreState YES
fi

# `-ApplePersistenceIgnoreState YES` : sixième piège de la recette, voir
# l'en-tête. Sans lui, macOS rouvre les fenêtres de la session précédente du
# bundle `.recette` — dont une fenêtre de réunion à jeton vide, qui tourne sur
# son spinner par-dessus la capture.
"${BINARY}" -ApplePersistenceIgnoreState YES > "${FAKE_HOME}/app.log" 2>&1 &
PID=$!
echo "✓ Lancé (pid ${PID}) — journal : ${FAKE_HOME}/app.log"

# ----------------------------------------------------------------------
# Garde-fou d'isolation. Si le store n'apparaît pas dans le home jetable,
# l'application a ouvert celui de production : on la tue sans attendre.
#
# ⚠️ **Ce garde-fou ne prouve que l'emplacement du store, pas que l'interface
# a été rendue.** Le fichier est créé par `OneToOneApp.init()`, avant toute
# fenêtre : le « ✓ » s'affiche donc aussi sur une application dont la fenêtre
# principale a été restaurée hors écran et n'a rien dessiné (piège n° 6). Le
# témoin de rendu, lui, est le contenu du store — les gabarits intégrés que
# `repairStoreIfNeeded()` sème en fin de `ContentView.onAppear`. Il est
# vérifié ci-dessous, **en copiant les trois fichiers** du store : il est en
# mode WAL, et lire le seul `.store` rend zéro partout (piège n° 7).
# ----------------------------------------------------------------------

# Le store contient-il les gabarits intégrés ? `0` (ou une lecture impossible)
# ⇒ `ContentView.onAppear` n'est pas parti.
gabarits_semes() {
    command -v sqlite3 >/dev/null 2>&1 || { echo "-1"; return; }
    local copie
    copie="$(mktemp -d)"
    cp "${STORE}" "${STORE}-wal" "${STORE}-shm" "${copie}/" 2>/dev/null || true
    sqlite3 "${copie}/OneToOne.store" 'select count(*) from ZREPORTTEMPLATE;' 2>/dev/null \
        || echo 0
    rm -rf "${copie}"
}

for _ in $(seq 1 60); do
    if [ -f "${STORE}" ]; then
        echo "✓ Store dans le home jetable : ${STORE}"
        N="$(gabarits_semes | head -1)"
        if [ "${N}" = "-1" ]; then
            echo "⚠️  sqlite3 introuvable : impossible de vérifier que la fenêtre"
            echo "    principale a été rendue. Regarde la capture avant de conclure."
            exit 0
        fi
        if [ "${N}" -gt 0 ] 2>/dev/null; then
            echo "✓ Interface rendue (${N} gabarits intégrés semés)"
            exit 0
        fi
        # Le store existe mais rien n'est semé : on laisse le temps au
        # `onAppear`, puis on renonce plus bas.
    fi
    if ! kill -0 "${PID}" 2>/dev/null; then
        echo "✗ Le processus s'est arrêté avant de créer son store."
        echo "  Journal : ${FAKE_HOME}/app.log"
        exit 1
    fi
    sleep 0.5
done

kill -9 "${PID}" 2>/dev/null || true
if [ -f "${STORE}" ]; then
    echo "✗ Le store est isolé, mais la fenêtre principale n'a jamais été rendue"
    echo "  (aucun gabarit intégré semé après 30 s) — le processus vient d'être tué."
    echo "  Pistes, dans cet ordre :"
    echo "   1. cadre enregistré hors écran → relance avec --reset (piège n° 6),"
    echo "      ou vérifie \`defaults read ${BUNDLE_ID:-<bundle id>}\` ;"
    echo "   2. une autre instance de OneToOne accapare la session"
    echo "      (\`ps -Ao pid,lstart,command | grep -i onetoone\`) ;"
    echo "   3. journal : ${FAKE_HOME}/app.log"
    exit 1
fi
echo "✗ ISOLATION ÉCHOUÉE — aucun store dans le home jetable après 30 s."
echo "  L'application a probablement ouvert le store de production ;"
echo "  le processus vient d'être tué. Vérifie"
echo "  \"\${HOME}/Library/Application Support/OneToOne/OneToOne.store\"."
exit 1
