#!/bin/bash
# fixpatch.sh <num> <correctif.py> — corrige un patch déjà appliqué strictement :
# repart de l'état avant <num>, applique $SERIES/<num>-*.patch, exécute <correctif.py>
# (depuis la racine de $PORT_TREE), régénère le patch et réapplique la suite.
set -eu
source "$(dirname "$0")/env.sh"
D=$(cd "$(dirname "$0")" && pwd)
NUM=$1; FIX=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
cd "$PORT_TREE"
git reset -q --hard "$(prev_tag "$PORT_TREE" "$NUM")" && git clean -qfdx
git apply --whitespace=nowarn "$SERIES"/"$NUM"-*.patch
python3 -I "$FIX"
bash "$D/regen.sh" "$NUM" | tail -1
next=$(printf '%04d' $((10#$NUM + 1)))
bash "$D/triage.sh" "$next" 2>/dev/null | grep -v '^OK' || true
echo "suite réappliquée depuis $next"
