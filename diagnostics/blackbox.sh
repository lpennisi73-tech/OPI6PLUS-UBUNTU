#!/bin/bash
# =============================================================================
# blackbox.sh — Enregistreur pour les redémarrages brutaux (docs/notes-materiel.md §12)
# BOOKWORM Sky1 Kernel Builder
#
# Toutes les N secondes (3 par défaut), écrit sur disque, avec sync : charge, mémoire,
# températures SCMI, fréquences CPU et GPU, et les nouvelles lignes noyau importantes.
# Après un redémarrage brutal : tail -40 du dernier /var/log/sky1-blackbox/blackbox-*.log
#
# Usage: sudo ./blackbox.sh [intervalle]      (Ctrl+C pour arrêter)
#        sudo nohup ./blackbox.sh >/dev/null 2>&1 &
# =============================================================================

INTERVAL="${1:-3}"
LOG_DIR=/var/log/sky1-blackbox
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/blackbox-$(date +%Y%m%d-%H%M%S)-$(uname -r).log"
GPU_DEV=/sys/devices/platform/soc@0/15000000.gpu
GPU_FREQ=$(ls -d /sys/class/devfreq/*.gpu 2>/dev/null | head -1)

echo "Enregistrement dans $LOG (toutes les ${INTERVAL} s)"
{
    echo "# $(uname -a)"
    echo "# cmdline : $(cat /proc/cmdline)"
} >> "$LOG"

while true; do
    {
        echo "== $(date '+%F %T') charge $(cut -d' ' -f1-3 /proc/loadavg)"
        LC_ALL=C free -m | awk '/^Mem/ {printf "mem utilisée %s Mo / dispo %s Mo", $3, $7} /^Swap/ {printf " | swap %s Mo\n", $3}'
        temps=""
        for h in /sys/class/hwmon/hwmon*; do
            [[ "$(cat "$h/name" 2>/dev/null)" == scmi_sensors ]] || continue
            for t in "$h"/temp*_input; do
                [[ -f "$t" ]] || continue
                temps+="$(cat "${t%_input}_label" 2>/dev/null)=$(( $(cat "$t") / 1000 )) "
            done
        done
        echo "temp °C : ${temps:-?}"
        freqs=""
        for p in /sys/devices/system/cpu/cpufreq/policy*; do
            freqs+="${p##*policy}=$(( $(cat "$p/scaling_cur_freq") / 1000 )) "
        done
        echo "cpu MHz : $freqs| gpu : $(( $(cat "$GPU_FREQ/cur_freq" 2>/dev/null || echo 0) / 1000000 )) MHz $(cat "$GPU_DEV/power/runtime_status" 2>/dev/null)"
        dmesg --since "-${INTERVAL}s" 2>/dev/null | grep -iE 'scmi|panthor|warning|bug|error|thermal|watchdog|nvme|oom' | tail -5
    } >> "$LOG"
    sync "$LOG"
    sleep "$INTERVAL"
done
