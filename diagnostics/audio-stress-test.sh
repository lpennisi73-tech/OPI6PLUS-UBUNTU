#!/bin/bash
# =============================================================================
# audio-stress-test.sh — Son HDMI : le bloquer en rouvrant la sortie de nombreuses fois ?
# BOOKWORM Sky1 Kernel Builder
#
# Hypothèse (2026-10-20) : à chaque ouverture de la sortie HDMI (premier son après un
# silence, lancement d'une vidéo), le pilote du DP coupe puis rallume son audio ; de temps
# en temps la file audio du contrôleur DP (SEC0_AUDIO_FIFO_READY) reste alors bloquée
# jusqu'au redémarrage. Le script répète N fois : son de test d'1 s (FIFO_READY lu pendant
# le son), puis attente que PipeWire FERME vraiment la sortie (PCM « closed » dans
# /proc/asound, ~5 s de silence). Des sons rapprochés ne suffisent pas : PipeWire garde
# la sortie ouverte quelques secondes, le pilote ne voit alors ni arrêt ni reprise.
# Il s'arrête au premier blocage.
# Avec les sorties toujours ouvertes (config/wireplumber/52-sky1-hdmi-buffer.conf, depuis le
# 2026-10-20), PipeWire ne ferme plus la sortie : retirer ce réglage le temps du test.
# ATTENTION : s'il reproduit le défaut, le son HDMI reste coupé jusqu'au prochain démarrage.
# Résultat : /root/sky1-audio-diag/stress-HHMM.log (~7 s par cycle)
#
# Usage: sudo ./audio-stress-test.sh [cycles=40]
# =============================================================================

set -u
[[ $EUID -eq 0 ]] || { echo "À lancer avec sudo (accès aux registres)"; exit 1; }
USER_NAME="${SUDO_USER:?Lancer avec sudo depuis la session graphique}"
CYCLES="${1:-40}"
command -v busybox >/dev/null || { echo "busybox manquant (sudo apt install busybox)"; exit 1; }

SINK=alsa_output.platform-sound.pro-output-1          # HDMI = périphérique 1 de cix_sky1
CARD=$(grep -l '^cixsky1$' /proc/asound/card*/id | grep -oE 'card[0-9]+')
PCM=/proc/asound/$CARD/pcm1p/sub0/status
[[ -r "$PCM" ]] || { echo "Sortie HDMI introuvable ($PCM)"; exit 1; }
base=$(grep -E ' : 14224000.dp dp$' /proc/iomem | awk '{print $1}' | cut -d- -f1)
[[ -n "$base" ]] || { echo "Contrôleur 14224000.dp introuvable dans /proc/iomem"; exit 1; }
B=$((16#$base))
fifo() { busybox devmem $((B + 0x930)) 32; }

LOG="/root/sky1-audio-diag/stress-$(date +%H%M).log"
mkdir -p "$(dirname "$LOG")"
log() { echo "$*" | tee -a "$LOG"; }

UID_USER=$(id -u "$USER_NAME")
tone() {   # tone <durée en s> : son de test sur le HDMI
    runuser -u "$USER_NAME" -- env XDG_RUNTIME_DIR="/run/user/$UID_USER" \
        timeout -s INT "$1" gst-launch-1.0 -q audiotestsrc volume=0.1 freq=660 ! audioconvert \
        ! audioresample ! pipewiresink target-object="$SINK" >/dev/null 2>&1
}
wait_closed() {   # attend la fermeture de la sortie par PipeWire (max 15 s)
    local t
    for ((t = 0; t < 150; t++)); do
        grep -q '^closed' "$PCM" && return 0
        sleep 0.1
    done
    return 1
}

log "=== $(date) — $(uname -r) — $CYCLES cycles d'ouverture/fermeture de la sortie HDMI ($CARD)"
for ((i = 1; i <= CYCLES; i++)); do
    wait_closed || { log "Cycle $i : la sortie ne se ferme pas (un autre son joue ?) — arrêt"; exit 1; }
    tone 2 & p=$!
    sleep 1.2
    f=$(fifo); st=$(head -1 "$PCM")
    wait "$p" 2>/dev/null
    if [[ $(( f & 1 )) -eq 1 ]]; then
        log "Cycle $i : sortie rouverte ($st), FIFO_READY = 1"
    else
        log "=== RÉSULTAT : bloqué au cycle $i (sortie $st, FIFO_READY = 0)."
        [[ $i -eq 1 ]] && log "(bloqué dès le 1er cycle : ce démarrage était peut-être déjà « sans son »)"
        log "Le son HDMI restera coupé jusqu'au prochain démarrage."
        journalctl -k --since "-2 min" --no-pager | tail -20 >> "$LOG"
        exit 0
    fi
done
log "=== Non reproduit : $CYCLES ouvertures sans blocage."
log "Journal : $LOG"
