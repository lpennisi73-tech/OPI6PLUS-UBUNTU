#!/bin/bash
# verify.sh <num> [fichiers adaptés...] — compare, fichier par fichier, les lignes +/- du patch
# <num> dans $REF_TREE et dans $PORT_TREE (état courant, ou PEND=apres-<num> pour un patch
# déjà commité). Les fichiers adaptés exprès sont signalés « ADAPTÉ » au lieu de « DIFFÈRE ».
# Limite : ne vérifie pas l'EMPLACEMENT des ajouts → compléter par anchors.py.
set -u
source "$(dirname "$0")/env.sh"
NUM=$1; shift; ADAPT=" $* "
rprev=$(prev_tag "$REF_TREE" "$NUM"); pprev=$(prev_tag "$PORT_TREE" "$NUM")
git -C "$PORT_TREE" add -A -N . 2>/dev/null
ok=0; ko=0
for f in $(git -C "$REF_TREE" diff --name-only "$rprev" "apres-$NUM"); do
    a=$(git -C "$REF_TREE" diff "$rprev" "apres-$NUM" -- "$f" | grep -aE '^[+-]' | grep -avE '^(\+\+\+|---) ')
    b=$(git -C "$PORT_TREE" diff "$pprev" ${PEND:-} -- "$f" | grep -aE '^[+-]' | grep -avE '^(\+\+\+|---) ')
    if [ "$a" = "$b" ]; then ok=$((ok+1))
    elif [[ "$ADAPT" == *" $f "* ]]; then echo "  ADAPTÉ   $f"
    else ko=$((ko+1)); echo "  DIFFÈRE  $f ($(diff <(echo "$a") <(echo "$b") | grep -c '^[<>]') lignes)"; fi
done
echo "patch $NUM : $ok fichiers identiques à la référence, $ko différents"
