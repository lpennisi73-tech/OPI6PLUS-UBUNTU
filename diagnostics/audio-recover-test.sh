#!/bin/bash
# =============================================================================
# audio-recover-test.sh — Son HDMI perdu : quelle action débloque l'audio du DP ?
# BOOKWORM Sky1 Kernel Builder
#
# À lancer sur un boot SANS son HDMI (problème intermittent : la file audio du
# contrôleur DP, SEC0_AUDIO_FIFO_READY, reste à 0 alors que l'I2S envoie les
# échantillons). Pendant un son de test, essaie une à une des actions de plus en
# plus fortes et relit FIFO_READY après chacune. S'arrête à la première qui marche.
#   1. audio du DP coupé puis rallumé (SEC0_AUDIO_ENABLE 0 -> 1)
#   2. mode d'horloge audio du DP basculé (SEC0_AUDIO_CLOCK_MODE 0 -> 1), remis sinon
#   3. carte son détachée puis rattachée (sky1-asoc-card)
#   4. I2S du HDMI réinitialisé (cdns-i2s-mc détaché/rattaché : reset matériel de l'I2S)
# Résultat dans /root/sky1-audio-diag/recover-HHMM.log
#
# Usage: sudo ./audio-recover-test.sh [sink PipeWire]
#        (défaut : alsa_output.platform-sound.pro-output-1 = HDMI)
# =============================================================================

set -u
[[ $EUID -eq 0 ]] || { echo "À lancer avec sudo (accès aux registres)"; exit 1; }
USER_NAME="${SUDO_USER:?Lancer avec sudo depuis la session graphique}"
SINK="${1:-alsa_output.platform-sound.pro-output-1}"
command -v busybox >/dev/null || { echo "busybox manquant (sudo apt install busybox)"; exit 1; }

DP_DEV=14224000.dp        # contrôleur DP de la sortie HDMI (dptx4)
I2S_DEV=70b0000.i2s       # I2S qui l'alimente
CARD_DEV=sound
LOG="/root/sky1-audio-diag/recover-$(date +%H%M).log"
mkdir -p "$(dirname "$LOG")"

base=$(grep -E " : ${DP_DEV} dp$" /proc/iomem | awk '{print $1}' | cut -d- -f1)
[[ -n "$base" ]] || { echo "Contrôleur $DP_DEV introuvable dans /proc/iomem"; exit 1; }
BASE=$((16#$base))
reg()  { busybox devmem $((BASE + $1)) 32; }
wreg() { busybox devmem $((BASE + $1)) 32 "$2"; }
fifo_ready() { [[ $(( $(reg 0x930) & 1 )) -eq 1 ]]; }

log() { echo "$*" | tee -a "$LOG"; }

UID_USER=$(id -u "$USER_NAME")
TONE_PID=""
tone_start() {
    runuser -u "$USER_NAME" -- env XDG_RUNTIME_DIR="/run/user/$UID_USER" \
        gst-launch-1.0 -q audiotestsrc volume=0.15 freq=440 ! audioconvert ! audioresample \
        ! pipewiresink target-object="$SINK" >/dev/null 2>&1 &
    TONE_PID=$!
    sleep 3
}
tone_stop() { [[ -n "$TONE_PID" ]] && kill "$TONE_PID" 2>/dev/null; wait "$TONE_PID" 2>/dev/null; TONE_PID=""; sleep 1; }
trap tone_stop EXIT

state() { log "  AUDIO_ENABLE=$(reg 0x900) CLOCK_MODE=$(reg 0x920) FIFO_READY=$(reg 0x930) MAUD=$(reg 0x918) NAUD=$(reg 0x91c)"; }
check() {   # check <nom de l'action> : succès si la file audio est prête
    sleep 2
    state
    if fifo_ready; then
        log "=== RÉSULTAT : l'action « $1 » débloque l'audio (FIFO_READY = 1). Écoute : le bip doit s'entendre."
        exit 0
    fi
    log "  -> sans effet"
}

log "=== $(date) — $(uname -r) — carte cix_sky1 : $(grep -l '^cixsky1$' /proc/asound/card*/id | grep -oE 'card[0-9]+')"
tone_start
log "État initial (son de test en cours sur $SINK) :"
state
if fifo_ready; then
    log "FIFO_READY = 1 : la file audio du DP fonctionne, ce boot n'est pas un boot « sans son »."
    exit 0
fi

log "1. Audio du DP coupé puis rallumé"
wreg 0x900 0; sleep 0.2; wreg 0x900 1
check "audio du DP coupé/rallumé"

log "2. Mode d'horloge audio du DP basculé"
old=$(reg 0x920)
wreg 0x920 $(( old ^ 1 ))
check "mode d'horloge audio = $(( old ^ 1 ))"
wreg 0x920 "$old"

log "3. Carte son détachée puis rattachée"
tone_stop
echo "$CARD_DEV" > /sys/bus/platform/drivers/sky1-asoc-card/unbind
sleep 1
echo "$CARD_DEV" > /sys/bus/platform/drivers/sky1-asoc-card/bind
sleep 4; tone_start
check "carte son détachée/rattachée"

log "4. I2S du HDMI réinitialisé (pilote détaché puis rattaché)"
tone_stop
echo "$CARD_DEV" > /sys/bus/platform/drivers/sky1-asoc-card/unbind
echo "$I2S_DEV" > /sys/bus/platform/drivers/cdns-i2s-mc/unbind
sleep 1
echo "$I2S_DEV" > /sys/bus/platform/drivers/cdns-i2s-mc/bind
sleep 1
echo "$CARD_DEV" > /sys/bus/platform/drivers/sky1-asoc-card/bind
sleep 4; tone_start
check "I2S réinitialisé"

log "=== Aucune action n'a débloqué l'audio. Journal noyau des dernières minutes :"
dmesg | tail -40 >> "$LOG"
log "Journal : $LOG"
