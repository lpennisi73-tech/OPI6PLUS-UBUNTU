#!/bin/bash
# =============================================================================
# gpu-dvfs-stress.sh — Blocage GPU panthor : le provoquer par des changements de fréquence ?
# BOOKWORM Sky1 Kernel Builder
#
# Défaut (2026-10-12 → 2026-10-23) : de temps en temps le GPU entier cesse de répondre
# (« CSG n update request timedout » sur les 8 groupes, « Failed to stop MCU »,
# « Soft reset timeout ») ; la session repart en rendu logiciel jusqu'au redémarrage.
# Hypothèse : un changement de fréquence (DVFS) du GPU, fait par le firmware SCP via le
# domaine SCMI « perf », surtout depuis les niveaux 72 / 216 MHz que le firmware ajoute
# au DT de CIX (350-1000 MHz). Le script fait tourner glmark2 dans la session (charge GPU
# continue) et impose une nouvelle fréquence toutes les STEP ms (min_freq = max_freq),
# en alternant bas et haut (72 ↔ 1000 MHz compris). Il s'arrête au premier message de
# blocage et remet le gouverneur et les bornes d'origine.
# Essai A : --floor 72 (tous les niveaux) ; essai B : --floor 350 (niveaux du DT seulement).
# ATTENTION : s'il reproduit le défaut, le GPU reste perdu jusqu'au prochain démarrage
# (session relancée en rendu logiciel) : enregistrer son travail avant.
# Résultat : /root/sky1-gpu-diag/dvfs-HHMM.log
#
# Usage: sudo ./gpu-dvfs-stress.sh [--floor <MHz>] [--minutes <n>] [--step-ms <ms>]
#        (défauts : --floor 72, --minutes 30, --step-ms 150 ; le pilote limite à 1 changement / 100 ms)
# =============================================================================

set -u
[[ $EUID -eq 0 ]] || { echo "À lancer avec sudo"; exit 1; }
USER_NAME="${SUDO_USER:?Lancer avec sudo depuis la session graphique}"

FLOOR_MHZ=72
MINUTES=30
STEP_MS=150
while [[ $# -gt 0 ]]; do
    case "$1" in
        --floor) FLOOR_MHZ="$2"; shift 2 ;;
        --minutes) MINUTES="$2"; shift 2 ;;
        --step-ms) STEP_MS="$2"; shift 2 ;;
        --help|-h) sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Option inconnue: $1"; exit 1 ;;
    esac
done

DF=/sys/class/devfreq/15000000.gpu
[[ -d "$DF" ]] || { echo "devfreq du GPU introuvable ($DF)"; exit 1; }
command -v glmark2-es2-wayland >/dev/null || { echo "glmark2-es2-wayland manquant (sudo apt install glmark2-es2-wayland)"; exit 1; }
UID_USER=$(id -u "$USER_NAME")
RUNDIR=/run/user/$UID_USER
WL=$(cd "$RUNDIR" 2>/dev/null && ls wayland-[0-9] 2>/dev/null | head -1)
[[ -n "$WL" ]] || { echo "Pas de session Wayland pour $USER_NAME"; exit 1; }

# Niveaux testés : ceux de devfreq au-dessus du plancher, joués en alternance bas / haut
mapfile -t ALL < <(tr ' ' '\n' < "$DF/available_frequencies" | grep -E '^[0-9]+$' | sort -n)
LEVELS=()
for f in "${ALL[@]}"; do (( f >= FLOOR_MHZ * 1000000 )) && LEVELS+=("$f"); done
(( ${#LEVELS[@]} >= 2 )) || { echo "Moins de 2 niveaux au-dessus de $FLOOR_MHZ MHz"; exit 1; }
SEQ=()
for ((i = 0, j = ${#LEVELS[@]} - 1; i <= j; i++, j--)); do
    SEQ+=("${LEVELS[i]}"); (( i < j )) && SEQ+=("${LEVELS[j]}")
done

[[ "$STEP_MS" =~ ^[0-9]+$ ]] && (( STEP_MS >= 100 )) || { echo "--step-ms : entier >= 100"; exit 1; }
PAUSE=$(awk -v ms="$STEP_MS" 'BEGIN { printf "%.3f", ms / 1000 }')

LOG="/root/sky1-gpu-diag/dvfs-$(date +%H%M).log"
mkdir -p "$(dirname "$LOG")"
log() { echo "$*" | tee -a "$LOG"; }

GOV0=$(cat "$DF/governor"); MIN0=$(cat "$DF/min_freq"); MAX0=$(cat "$DF/max_freq")
TRANS0=$(awk '/Total transition/{print $NF}' "$DF/trans_stat")
GLPID=""
restore() {
    [[ -n "$GLPID" ]] && kill "$GLPID" 2>/dev/null
    # bornes larges d'abord, puis celles d'origine (min <= max à chaque écriture)
    echo "${ALL[0]}" > "$DF/min_freq" 2>/dev/null
    echo "${ALL[-1]}" > "$DF/max_freq" 2>/dev/null
    echo "$MIN0" > "$DF/min_freq" 2>/dev/null
    echo "$MAX0" > "$DF/max_freq" 2>/dev/null
    echo "$GOV0" > "$DF/governor" 2>/dev/null
}
trap 'restore; log "Interrompu — bornes et gouverneur remis"; exit 130' INT TERM

set_freq() {   # set_freq <Hz> : impose la fréquence (ordre des écritures pour garder min <= max)
    if (( $1 > $(cat "$DF/max_freq") )); then
        echo "$1" > "$DF/max_freq"; echo "$1" > "$DF/min_freq"
    else
        echo "$1" > "$DF/min_freq"; echo "$1" > "$DF/max_freq"
    fi
}
PATTERN='CSG [0-9]+ update request timedout|Failed to stop MCU|AS_ACTIVE bit stuck|panthor.*job timeout|Soft reset timeout'
hang_count() { dmesg | grep -cE "$PATTERN"; }

BASE=$(hang_count)
log "=== $(date) — $(uname -r) — plancher $FLOOR_MHZ MHz, pas de $STEP_MS ms, $MINUTES min"
log "Niveaux joués (MHz) : $(for f in "${SEQ[@]}"; do printf '%s ' $((f / 1000000)); done)"
log "Gouverneur d'origine : $GOV0 ($((MIN0 / 1000000))-$((MAX0 / 1000000)) MHz), transitions déjà faites : $TRANS0"

runuser -u "$USER_NAME" -- env XDG_RUNTIME_DIR="$RUNDIR" WAYLAND_DISPLAY="$WL" \
    glmark2-es2-wayland --run-forever --size 800x600 >>"$LOG.glmark2" 2>&1 &
GLPID=$!
sleep 3
kill -0 "$GLPID" 2>/dev/null || { log "glmark2 n'a pas démarré (voir $LOG.glmark2)"; restore; exit 1; }
echo performance > "$DF/governor" 2>/dev/null || true   # sans effet : min = max impose la fréquence

END=$(( $(date +%s) + MINUTES * 60 ))
n=0; misses=0; START=$(date +%s)
while (( $(date +%s) < END )); do
    for f in "${SEQ[@]}"; do
        set_freq "$f" 2>/dev/null
        sleep "$PAUSE"
        (( n++ ))
        [[ "$(cat "$DF/cur_freq")" == "$f" ]] || (( misses++ ))
    done
    if (( $(hang_count) > BASE )); then
        el=$(( $(date +%s) - START ))
        log "!!! BLOCAGE après ${el} s et $n changements de fréquence (dernière imposée : $((f / 1000000)) MHz)"
        dmesg | grep -E "panthor|scmi|$PATTERN" | tail -40 >> "$LOG"
        log "Messages noyau ajoutés au journal. Le GPU restera perdu jusqu'au redémarrage."
        restore
        exit 2
    fi
    if ! kill -0 "$GLPID" 2>/dev/null; then
        log "glmark2 s'est arrêté (après $n changements) — voir $LOG.glmark2"
        restore; exit 1
    fi
    if (( n % 400 < ${#SEQ[@]} )); then
        log "$(date +%T) : $n changements, $misses non appliqués (limiteur du pilote), aucun blocage"
    fi
done
TRANS1=$(awk '/Total transition/{print $NF}' "$DF/trans_stat")
restore
log "=== Fin sans blocage : $n changements demandés, $((TRANS1 - TRANS0)) transitions réelles, $misses non appliqués"
