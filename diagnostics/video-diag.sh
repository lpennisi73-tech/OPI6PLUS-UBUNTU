#!/bin/bash
# =============================================================================
# video-diag.sh — Lecture vidéo saccadée : relevé du système + mesures comparées
# BOOKWORM Sky1 Kernel Builder
#
# À lancer dans la session graphique (terminal GNOME), en utilisateur normal (pas sudo),
# avec une vidéo LOCALE (pas sur le réseau). Relève l'état utile (paquets, environnement
# de session, décodeurs, fréquences CPU/GPU, journaux), puis lit la vidéo plusieurs fois,
# DURÉE secondes chacune, en comptant les images affichées et perdues :
#   1. décodage seul, sans affichage ni horloge (vitesse brute du décodeur)
#   2. comme Showtime : playbin3 + gtk4paintablesink (fenêtre GTK4), son compris
#   3. pareil avec le rendu GTK en GL (GSK_RENDERER=gl)
#   4. affichage GL direct (glimagesink)
#   5. affichage Wayland direct (waylandsink)
# Des fenêtres s'ouvrent l'une après l'autre : ne pas les fermer, ne rien toucher.
# Ne modifie rien sur le système. Résultat : un dossier video-diag-<machine>-<date>
# à côté du script (ou dans -o <dossier>), avec resume.txt à me renvoyer en entier.
#
# Usage: diagnostics/video-diag.sh [-o <dossier>] <vidéo> [durée_s=20]
# =============================================================================

set -u

OUT_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "-o" ]]; then OUT_BASE="$2"; shift 2; fi
[[ "${1:-}" =~ ^(-h|--help)$ || $# -lt 1 ]] && { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
VIDEO="$(realpath "$1")"; DUR="${2:-20}"

[[ $EUID -ne 0 ]] || { echo "À lancer sans sudo, depuis la session graphique"; exit 1; }
[[ -f "$VIDEO" ]] || { echo "Vidéo introuvable : $VIDEO"; exit 1; }
[[ -n "${WAYLAND_DISPLAY:-}" ]] || { echo "Pas de session Wayland (lancer depuis un terminal du bureau)"; exit 1; }
for t in gst-launch-1.0 gst-inspect-1.0 gst-discoverer-1.0; do
    command -v "$t" >/dev/null || { echo "$t manquant (sudo apt install gstreamer1.0-tools)"; exit 1; }
done

# Même environnement que les applications du bureau (Showtime est lancé par systemd --user) :
# variables GStreamer/GTK/Mesa de la session reprises, celles du terminal notées à part.
TERM_ENV=$(env | grep -E '^(GST|GDK|GSK|COGL|MESA|LIBGL)' || true)
while IFS= read -r v; do export "${v?}"; done < <(systemctl --user show-environment | grep -E '^(GST|GDK|GSK|COGL|MESA|LIBGL)[A-Z_]*=')

OUT="$OUT_BASE/video-diag-$(hostname)-$(date +%Y%m%d-%H%M)"
mkdir -p "$OUT" || exit 1
SUM="$OUT/resume.txt"
say() { echo "$*" | tee -a "$SUM"; }
URI="file://$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$VIDEO")"

say "=== video-diag $(date '+%F %T') — $(hostname) — $(uname -r)"
say "Vidéo : $VIDEO ($DUR s par test)"

# --- 1. Système ---------------------------------------------------------------
{
    echo "## os-release"; grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
    echo "## cmdline"; cat /proc/cmdline
    echo "## paquets"
    dpkg-query -W -f='${Package} ${Version} ${db:Status-Abbrev}\n' \
        'gstreamer1.0-*' 'libgstreamer1.0-0' 'libgtk-4-1' 'libgl1-mesa-dri' 'mesa-vulkan-drivers' \
        showtime totem vlc gnome-shell mutter 'pipewire' wireplumber bookworm-sky1-settings \
        cix-vpu-firmware 'linux-image-*sky1*' 2>/dev/null | grep -v ' un $'
    echo "## environnement de session (systemd --user)"
    systemctl --user show-environment | grep -E 'GST|GDK|GSK|COGL|MESA|LIBGL|XDG_SESSION_TYPE|WAYLAND'
    echo "## environnement du terminal (avant reprise de celui de la session)"
    echo "${TERM_ENV:-(rien)}"
    echo "## fichiers environment.d"
    ls -l /usr/lib/environment.d/ /etc/environment.d/ ~/.config/environment.d/ 2>&1
    echo "## profil d'énergie"; powerprofilesctl get 2>&1
    echo "## cpufreq"
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        echo "$(basename "$p") $(cat "$p/scaling_governor") cur=$(cat "$p/scaling_cur_freq") max=$(cat "$p/scaling_max_freq") \
up=$(cat "$p/ondemand/up_threshold" 2>/dev/null) sdf=$(cat "$p/ondemand/sampling_down_factor" 2>/dev/null)"
    done
    echo "## devfreq (GPU, VPU)"
    for d in /sys/class/devfreq/*; do echo "$(basename "$d") $(cat "$d/governor") cur=$(cat "$d/cur_freq") min=$(cat "$d/min_freq") max=$(cat "$d/max_freq")"; done
    echo "## veille runtime GPU"
    for f in /sys/bus/platform/devices/15000000.gpu/power/{control,runtime_status}; do echo "$f $(cat "$f" 2>/dev/null)"; done
    echo "## cartes DRM"
    for c in /sys/class/drm/card[0-9]; do echo "$(basename "$c") $(basename "$(readlink -f "$c/device/driver")")"; done
    echo "## décodeurs vus par GStreamer (avec l'environnement de session)"
    for e in avdec_h264 avdec_h265 v4l2h264dec v4l2h265dec openh264dec gtk4paintablesink glimagesink waylandsink fpsdisplaysink; do
        r=$(gst-inspect-1.0 "$e" 2>/dev/null | awk '/^  Rank/{$1=""; print substr($0,2)}')
        echo "$e : ${r:-ABSENT}"
    done
} > "$OUT/systeme.txt" 2>&1

say ""
say "Paquets clés :"
grep -E '^(gstreamer1.0-(libav|gtk4|plugins-bad|plugins-good)|libgl1-mesa-dri|libgtk-4-1|showtime|bookworm-sky1-settings) ' "$OUT/systeme.txt" | sed 's/^/  /' | tee -a "$SUM"
say "Décodeurs (rang) :"
grep -E '^(avdec_h264|v4l2h264dec|openh264dec|gtk4paintablesink|fpsdisplaysink) :' "$OUT/systeme.txt" | sed 's/^/  /' | tee -a "$SUM"
say "Session : $(systemctl --user show-environment | grep -E '^(COGL_DRIVER|GDK_DISABLE|GST_PLUGIN_FEATURE_RANK)=' | cut -c1-40 | tr '\n' ' ')"
say "Énergie : $(powerprofilesctl get 2>/dev/null) ; GPU $(cat /sys/class/devfreq/15000000.gpu/governor 2>/dev/null), control=$(cat /sys/bus/platform/devices/15000000.gpu/power/control 2>/dev/null)"
say "cpufreq : $(for p in /sys/devices/system/cpu/cpufreq/policy*; do printf '%s ' "$(cat "$p/scaling_governor")"; done)"

gst-discoverer-1.0 -v "$URI" > "$OUT/discoverer.txt" 2>&1
say "Fichier : vidéo $(grep -m1 -oE 'codec (vidéo|video): .*' "$OUT/discoverer.txt" | cut -d: -f2-) ;\
 audio $(grep -m1 -oE 'codec audio: .*' "$OUT/discoverer.txt" | cut -d: -f2-) ;\
 $(grep -m1 -oE 'Width: [0-9]+' "$OUT/discoverer.txt") $(grep -m1 -oE 'Height: [0-9]+' "$OUT/discoverer.txt") $(grep -m1 -oE 'Frame rate: [0-9/]+' "$OUT/discoverer.txt")"
if ! gst-inspect-1.0 fpsdisplaysink >/dev/null 2>&1; then
    say "fpsdisplaysink absent (gstreamer1.0-plugins-bad) : mesures impossibles, relevé seul."
    exit 0
fi

# --- 2. Mesures ---------------------------------------------------------------
cpu_ticks() { awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat; }
run() {   # run <n°> <nom> <env…> -- <pipeline…>
    local n="$1" name="$2"; shift 2
    local envs=(); while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done; shift
    local log="$OUT/test$n.log"
    read -r t0 i0 < <(cpu_ticks)
    env "${envs[@]}" timeout -s INT "$((DUR + 5))" gst-launch-1.0 -e -v "$@" > "$log" 2>&1 &
    local pid=$!
    sleep "$DUR"; kill -INT "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    read -r t1 i1 < <(cpu_ticks)
    local cpu=$(( t1 > t0 ? 100 * ( (t1 - t0) - (i1 - i0) ) / (t1 - t0) : 0 ))
    local stats dec err
    stats=$(grep -oE 'rendered: [0-9]+, dropped: [0-9]+, (current: [0-9.,]+, )?average: [0-9.,]+' "$log" | tail -1)
    dec=$(grep -oE '(avdec_[a-z0-9]+|v4l2[a-z0-9]+dec|openh264dec)[0-9]*' "$log" | sort -u | tr '\n' ' ')
    err=$(grep -m1 -E 'ERROR|ERREUR|Erreur' "$log" | cut -c1-150)
    say "$(printf '%-48s' "$n. $name") ${stats:-pas de mesure} | CPU ${cpu} % | décodeur : ${dec:-?}${err:+ | $err}"
}

say ""
say "Mesures ($DUR s chacune ; rendered = images affichées, dropped = perdues, average = images/s) :"
run 1 "décodage seul (sans affichage)" -- \
    uridecodebin3 uri="$URI" caps=video/x-raw ! fpsdisplaysink video-sink=fakesink sync=false text-overlay=false
run 2 "comme Showtime (gtk4paintablesink)" GST_GTK4_WINDOW=1 -- \
    playbin3 uri="$URI" video-sink="fpsdisplaysink video-sink=gtk4paintablesink text-overlay=false"
run 3 "gtk4paintablesink + GSK_RENDERER=gl" GST_GTK4_WINDOW=1 GSK_RENDERER=gl -- \
    playbin3 uri="$URI" video-sink="fpsdisplaysink video-sink=gtk4paintablesink text-overlay=false"
run 4 "glimagesink" -- \
    playbin3 uri="$URI" video-sink="fpsdisplaysink video-sink=glimagesink text-overlay=false"
run 5 "waylandsink" -- \
    playbin3 uri="$URI" video-sink="fpsdisplaysink video-sink=waylandsink text-overlay=false"

# --- 3. Journaux --------------------------------------------------------------
journalctl -b --user --since "-30 min" -p warning --no-pager > "$OUT/journal-user.txt" 2>&1
journalctl -b -k -p warning --no-pager > "$OUT/journal-noyau.txt" 2>&1
say ""
say "WARNING noyau depuis le démarrage : $(grep -cE 'WARNING|BUG:|Oops' "$OUT/journal-noyau.txt")"
say "Dossier complet : $OUT"
