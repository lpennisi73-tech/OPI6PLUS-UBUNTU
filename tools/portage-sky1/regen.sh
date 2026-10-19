#!/bin/bash
# regen.sh <num> — enregistre la résolution du patch <num> (état courant de $PORT_TREE) :
# un commit propre au-dessus de l'état avant le patch, tag « apres-<num> », puis réécrit
# $SERIES/<num>-*.patch (en-tête d'origine + note de portage + diff réel, --binary).
# Après : ./triage.sh <num+1> pour réappliquer la suite.
set -eu
source "$(dirname "$0")/env.sh"
NUM=$1
cd "$PORT_TREE"
P=$(ls "$SERIES"/"$NUM"-*.patch)
prev=$(prev_tag "$PORT_TREE" "$NUM")
git reset -q --soft "$prev"
"${G[@]}" add -A
"${G[@]}" commit -q -m "$(basename "$P" .patch) [RESOLU]"
git tag -f "apres-$NUM" >/dev/null
hdr=$(awk '/^---$/{exit} {print}' "$P")
{
    printf '%s\n' "$hdr"
    grep -q "ported to $PORT_LABEL" <<<"$hdr" || printf '\n[ported to %s by BOOKWORM: conflicts with upstream resolved]\n' "$PORT_LABEL"
    echo "---"
    git diff --stat "$prev" HEAD | tail -1
    echo
    git diff --binary --full-index "$prev" HEAD
} > "$P.new"
mv "$P.new" "$P"
echo "régénéré : $(basename "$P") ($(grep -c '^diff --git' "$P") fichiers)"
