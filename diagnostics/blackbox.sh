#!/bin/bash
# =============================================================================
# blackbox.sh — Enregistreur pour les redémarrages brutaux (docs/notes-materiel.md §12)
# BOOKWORM Sky1 Kernel Builder
#
# Toutes les N secondes (3 par défaut), écrit sur disque, avec sync : charge, mémoire,
# températures SCMI, fréquences CPU et GPU, et les nouvelles lignes noyau importantes.
# Passe aussi le niveau de la console noyau à 8 : tous les messages partent sur la
# console série (ttyAMA2), à enregistrer depuis une autre machine.
# Un fichier par démarrage ; ceux de plus de 14 jours sont supprimés au lancement.
# Après un redémarrage brutal : tail -40 de l'avant-dernier /var/log/sky1-blackbox/blackbox-*.log
#
# Usage: sudo ./blackbox.sh [intervalle]      lancement direct (Ctrl+C pour arrêter)
#        sudo ./blackbox.sh --install [s]     service permanent sky1-blackbox (à chaque démarrage)
#        sudo ./blackbox.sh --uninstall       retire le service (les journaux restent)
# =============================================================================

LOG_DIR=/var/log/sky1-blackbox
UNIT=/etc/systemd/system/sky1-blackbox.service
BIN=/usr/local/sbin/sky1-blackbox

case "${1:-}" in
    --install)
        INTERVAL="${2:-3}"
        install -m 755 "$0" "$BIN"
        cat > "$UNIT" << EOF
[Unit]
Description=BOOKWORM Sky1 : enregistreur des redémarrages brutaux (diagnostic)
After=local-fs.target

[Service]
ExecStart=$BIN $INTERVAL
Nice=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now sky1-blackbox.service
        systemctl --no-pager --lines=0 status sky1-blackbox.service
        exit 0 ;;
    --uninstall)
        systemctl disable --now sky1-blackbox.service 2>/dev/null
        rm -f "$UNIT" "$BIN"
        systemctl daemon-reload
        echo "Service retiré ; journaux gardés dans $LOG_DIR"
        exit 0 ;;
    --help|-h) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

INTERVAL="${1:-3}"
mkdir -p "$LOG_DIR"
find "$LOG_DIR" -name 'blackbox-*.log' -mtime +14 -delete
LOG="$LOG_DIR/blackbox-$(date +%Y%m%d-%H%M%S)-$(uname -r).log"
GPU_DEV=/sys/devices/platform/soc@0/15000000.gpu
GPU_FREQ=$(ls -d /sys/class/devfreq/*.gpu 2>/dev/null | head -1)
dmesg -n 8 2>/dev/null

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
