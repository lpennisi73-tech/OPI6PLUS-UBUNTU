#!/bin/bash
# =============================================================================
# audio-dp-regs.sh — Relevé des registres audio du contrôleur DP du HDMI (14224000)
# BOOKWORM Sky1 Kernel Builder
#
# Son HDMI intermittent : comparer ce relevé entre un boot AVEC son et un boot SANS son.
# Joue un son de test sur la sortie HDMI, puis lit deux fois (à 2 s d'écart) les registres
# du flux secondaire (audio) : activation, sélection d'entrée, MAUD/NAUD, FIFO_READY,
# débordement, compteur de paquets, fenêtre de données… Lecture seule ; la file de données
# (0x928/0x92c), qu'une lecture viderait, n'est pas lue.
# Résultat : /root/sky1-audio-diag/sec-<étiquette>-HHMM.txt
#
# Usage: sudo ./audio-dp-regs.sh <étiquette>     (ex. avec-son, sans-son)
# =============================================================================

set -u
[[ $EUID -eq 0 ]] || { echo "À lancer avec sudo (accès aux registres)"; exit 1; }
USER_NAME="${SUDO_USER:?Lancer avec sudo depuis la session graphique}"
LABEL="${1:?étiquette manquante (avec-son ou sans-son)}"
command -v busybox >/dev/null || { echo "busybox manquant (sudo apt install busybox)"; exit 1; }

SINK=alsa_output.platform-sound.pro-output-1
base=$(grep -E ' : 14224000.dp dp$' /proc/iomem | awk '{print $1}' | cut -d- -f1)
[[ -n "$base" ]] || { echo "Contrôleur 14224000.dp introuvable dans /proc/iomem"; exit 1; }
B=$((16#$base))
REGS="0x800 0x804 0x808 0x900 0x904 0x908 0x910 0x914 0x918 0x91c 0x920 0x924 0x930 0x934 0x93c
      0x940 0x944 0x948 0x94c 0x950 0x954 0x958 0x95c 0x960 0x964 0x968"
dump() { for r in $REGS; do printf '%s=%s\n' "$r" "$(busybox devmem $((B + r)) 32)"; done; }

UID_USER=$(id -u "$USER_NAME")
runuser -u "$USER_NAME" -- env XDG_RUNTIME_DIR="/run/user/$UID_USER" \
    gst-launch-1.0 -q audiotestsrc volume=0.15 freq=440 ! audioconvert ! audioresample \
    ! pipewiresink target-object="$SINK" >/dev/null 2>&1 &
TONE=$!
trap 'kill $TONE 2>/dev/null; wait $TONE 2>/dev/null' EXIT
sleep 3

OUT="/root/sky1-audio-diag/sec-$LABEL-$(date +%H%M).txt"
mkdir -p "$(dirname "$OUT")"
{
    echo "# $(date) — $(uname -r) — carte cix_sky1 : $(grep -l '^cixsky1$' /proc/asound/card*/id | grep -oE 'card[0-9]+') — son de test sur $SINK"
    dump > /tmp/.sec0; sleep 2; dump > /tmp/.sec1
    paste -d' ' /tmp/.sec0 /tmp/.sec1 | awk '{split($1,a,"="); split($2,b,"="); printf "%s %s %s%s\n", a[1], a[2], b[2], (a[2]!=b[2] ? "  (change)" : "")}'
    rm -f /tmp/.sec0 /tmp/.sec1
} | tee "$OUT"
echo "-> $OUT"
