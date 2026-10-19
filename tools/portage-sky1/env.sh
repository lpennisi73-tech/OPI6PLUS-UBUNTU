#!/bin/bash
# env.sh — paramètres communs des outils de portage Sky1 (sourcé par chaque outil).
# Tout se surcharge par variable d'environnement, ex. pour un portage vers 7.3 :
#   PORT_TREE=/usr/src/build/sky1-kernel/port-7.3 SERIES=$PWD/patches/sky1-7.3 PORT_LABEL="Linux 7.3" ./triage.sh
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR=${WORK_DIR:-/usr/src/build/sky1-kernel}
REF_TREE=${REF_TREE:-$WORK_DIR/ref-7.0}          # base d'origine + série d'origine (tags apres-NNNN)
PORT_TREE=${PORT_TREE:-$WORK_DIR/port-7.2.11}    # nouvelle base + série portée (tags apres-NNNN)
SERIES=${SERIES:-$PROJECT_DIR/patches/sky1-7.2}  # série en cours de portage (modifiée sur place)
REJ_DIR=${REJ_DIR:-$WORK_DIR/rej}                # hunks refusés, par patch
PORT_LABEL=${PORT_LABEL:-Linux 7.2}              # libellé des notes ajoutées aux en-têtes
G=(git -c user.name=port -c user.email=port@local)

# prev_tag <arbre> <num> : tag de l'état avant le patch <num> (commit de base pour 0001)
prev_tag() {
    local p; p=$(printf '%04d' $((10#$2 - 1)))
    if [ "$p" = "0000" ]; then git -C "$1" rev-list --max-parents=0 HEAD; else echo "apres-$p"; fi
}
