#!/bin/bash
# =============================================================================
# audio-snapshot.sh — Photo de l'état audio DP/HDMI (son HDMI perdu certains boots)
# BOOKWORM Sky1 Kernel Builder
#
# Enregistre, pendant qu'un son joue sur la sortie HDMI : horloges, registres I2S
# (regmap), DAPM de la carte cix_sky1, ELD de l'écran, état des PCM et registres
# audio (SEC0) des deux contrôleurs DP (lecture seule par /dev/mem). Deux photos
# (une avec son, une sans) se comparent avec diff -r.
#
# Usage: sudo ./audio-snapshot.sh <etiquette>     (ex. : avec-son, sans-son)
#        → /root/sky1-audio-diag/<etiquette>-HHMM/
# =============================================================================

set -u
[[ $EUID -eq 0 ]] || { echo "À lancer en root (debugfs, /dev/mem)"; exit 1; }
LABEL="${1:?Usage: $0 <etiquette>}"
OUT="/root/sky1-audio-diag/${LABEL}-$(date +%H%M)"
mkdir -p "$OUT"

uname -rv > "$OUT/kernel.txt"
cp /sys/kernel/debug/clk/clk_summary "$OUT/" 2>/dev/null
for r in /sys/kernel/debug/regmap/*; do
    n=$(basename "$r")
    case "$n" in *i2s*|*7110000*) cat "$r/registers" > "$OUT/regmap-$n.txt" 2>/dev/null ;; esac
done

# La carte cix_sky1 change de numéro d'un boot à l'autre : on la cherche par son nom
CARD=$(grep -l '^cixsky1$' /proc/asound/card*/id 2>/dev/null | head -1 | xargs -r dirname)
if [[ -n "$CARD" ]]; then
    for f in "$CARD"/eld#* "$CARD"/pcm*p/sub0/status "$CARD"/pcm*p/sub0/hw_params; do
        echo "== $f"; cat "$f"
    done > "$OUT/card.txt" 2>/dev/null
fi
find /sys/kernel/debug/asoc/cix_sky1 -type f -exec sh -c 'echo "== $1"; cat "$1"' _ {} \; \
    > "$OUT/dapm.txt" 2>/dev/null

# Registres audio SEC0 (0x900-0x97c) des contrôleurs DP (base lue dans /proc/iomem)
if command -v busybox >/dev/null; then
    grep -E ' : [0-9a-f]+\.dp dp$' /proc/iomem | while read -r range _ dev _; do
        base=$((16#${range%-*}))
        for off in $(seq $((0x900)) 4 $((0x97c))); do
            printf '%03x: %s\n' "$off" "$(busybox devmem $((base + off)) 32)"
        done > "$OUT/sec0-${dev}.txt"
    done
fi

echo "Photo enregistrée : $OUT"
