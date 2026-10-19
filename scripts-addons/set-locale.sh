#!/usr/bin/env bash
# set-locale.sh - langue, clavier (écran de connexion, console) et fuseau horaire, Ubuntu/systemd.
# Usage : sudo ./set-locale.sh --lang fr_CH [--tz Europe/Zurich] [--kbd ch:fr] [--dry-run]
# Facultatif, hors install.sh.
#
#  --lang xx_YY   génère xx_YY.UTF-8 et en fait la langue du système (localectl set-locale)
#  --kbd  l[:v]   disposition[:variante] clavier ; par défaut, déduite de --lang
#  --tz   Zone    fuseau horaire (timedatectl set-timezone), ex. Europe/Zurich
#
# Le clavier est réglé par « localectl set-x11-keymap » : sous Ubuntu, systemd-localed écrit
# /etc/default/keyboard, que lisent aussi la console texte (console-setup) et GDM.
# La session GNOME de chaque utilisateur garde ses propres « Sources de saisie »
# (Paramètres → Clavier) : ce script règle le système, pas les sessions existantes.
set -euo pipefail

LANG_ID="" TZ_ID="" KBD="" DRY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --lang) LANG_ID="$2"; shift 2 ;;
        --tz)   TZ_ID="$2"; shift 2 ;;
        --kbd)  KBD="$2"; shift 2 ;;      # ex: ch:fr (disposition[:variante])
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "Option inconnue : $1" >&2; exit 1 ;;
    esac
done
[[ $LANG_ID =~ ^[a-z]{2,3}_[A-Z]{2}$ ]] || { echo "Il faut --lang xx_YY (ex: fr_CH)" >&2; exit 1; }
[[ $EUID -eq 0 || $DRY -eq 1 ]] || { echo "À lancer en root (ou --dry-run)" >&2; exit 1; }

# langue -> "disposition variante"
case "$LANG_ID" in
    fr_CH) MAP="ch fr" ;;   de_CH) MAP="ch -" ;;
    fr_FR) MAP="fr -" ;;    fr_BE) MAP="be -" ;;
    de_DE) MAP="de -" ;;    it_IT) MAP="it -" ;;
    es_ES) MAP="es -" ;;    en_GB) MAP="gb -" ;;
    en_US) MAP="us -" ;;    pt_BR) MAP="br -" ;;
    *) c="${LANG_ID#*_}"; MAP="${c,,} -" ;;
esac
read -r XLAYOUT XVARIANT <<<"$MAP"
[[ $XVARIANT == "-" ]] && XVARIANT=""
if [[ -n $KBD ]]; then   # clavier indépendant de la langue
    XLAYOUT="${KBD%%:*}"; XVARIANT=""; [[ $KBD == *:* ]] && XVARIANT="${KBD#*:}"
fi

run() { if ((DRY)); then echo "[dry-run] $*"; else "$@"; fi; }

echo "== Langue ${LANG_ID}.UTF-8 | clavier ${XLAYOUT}${XVARIANT:+/$XVARIANT} | fuseau ${TZ_ID:-inchangé}"

# 1. locale (Ubuntu : locale-gen accepte directement le nom de la locale)
run locale-gen "${LANG_ID}.UTF-8"
run localectl set-locale "LANG=${LANG_ID}.UTF-8"

# 2. clavier : écran de connexion (GDM), nouvelles sessions et console texte
if localectl list-x11-keymap-layouts 2>/dev/null | grep -qx "$XLAYOUT"; then
    # arguments : disposition modèle variante
    run localectl set-x11-keymap "$XLAYOUT" pc105 "$XVARIANT"
else
    echo "Disposition clavier '${XLAYOUT}' inconnue : étape ignorée (voir localectl list-x11-keymap-layouts)"
fi

# 3. fuseau (optionnel)
if [[ -n $TZ_ID ]]; then
    run timedatectl set-timezone "$TZ_ID"
fi

echo "== Terminé. Nouvel état :"
((DRY)) || { localectl status; timedatectl | grep -i 'time zone'; }
echo "La langue s'applique aux sessions ouvertes après une déconnexion/reconnexion."
