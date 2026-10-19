#!/bin/bash
# regen_all.sh — réécrit chaque patch de $SERIES depuis les commits de $PORT_TREE
# (apres-<n-1>..apres-<n>, --binary). Un patch au diff inchangé garde son fichier ;
# sinon note « rebased » (contexte rafraîchi) si aucune note de portage n'existe déjà.
set -eu
source "$(dirname "$0")/env.sh"
cd "$PORT_TREE"
prev=$(git rev-list --max-parents=0 HEAD)
kept=0; rewritten=0
norm() { grep -avE '^(index |diff --git |--- |\+\+\+ |@@ )' | grep -aE '^[-+ ]'; }
for P in $(ls "$SERIES"/*.patch | sort); do
    num=$(basename "$P" | cut -c1-4)
    new=$(git diff --binary --full-index "$prev" "apres-$num")
    if [ "$(awk '/^diff --git/{p=1} p' "$P" | norm)" = "$(echo "$new" | norm)" ] && ! grep -q 'GIT binary patch' <<<"$new"; then
        kept=$((kept+1))
    else
        hdr=$(awk '/^---$/{exit} {print}' "$P")
        grep -qE "(ported to|rebased on) $PORT_LABEL" <<<"$hdr" || \
            hdr="$hdr"$'\n\n'"[rebased on $PORT_LABEL by BOOKWORM: context refreshed]"
        { printf '%s\n---\n' "$hdr"; git diff --stat "$prev" "apres-$num" | tail -1; echo; echo "$new"; echo; } > "$P"
        rewritten=$((rewritten+1)); echo "réécrit : $(basename "$P")"
    fi
    prev="apres-$num"
done
echo "inchangés : $kept, réécrits : $rewritten"
