#!/bin/bash
# check-strict.sh <tarball.tar.xz> — test final : extrait une source vierge dans un dossier
# temporaire, applique $SERIES en mode strict (git apply, sans fuzz), compare le résultat
# au dernier tag de $PORT_TREE, puis supprime le dossier temporaire.
set -u
source "$(dirname "$0")/env.sh"
TAR=$1
C=$(mktemp -d "$WORK_DIR/check-XXXXXX")
W=$(mktemp -d "$WORK_DIR/cmp-XXXXXX")
trap 'rm -rf "$C" "$W"' EXIT
tar xf "$TAR" -C "$C" --strip-components=1
cd "$C"; n=0; tot=$(ls "$SERIES"/*.patch | wc -l)
for p in $(ls "$SERIES"/*.patch | sort); do
    git apply --whitespace=nowarn "$p" 2>/dev/null || { echo "ÉCHEC strict : $(basename "$p")"; git apply --check "$p" 2>&1 | head -3; exit 1; }
    n=$((n+1))
done
echo "$n/$tot appliqués en mode strict"
last=$(ls "$SERIES"/*.patch | sort | tail -1 | xargs basename | cut -c1-4)
git -C "$PORT_TREE" archive "apres-$last" | tar -x -C "$W"
# Fichiers présents seulement dans la source vierge mais ignorés par git dans $PORT_TREE
# (ex. Documentation/.renames.txt, exclu par le .gitignore du noyau) : non significatifs.
d=$(diff -rq "$C" "$W" | while read -r l; do
    if [[ "$l" =~ ^(Seulement\ dans|Only\ in)\ $C/?([^:]*):\ (.*)$ ]]; then
        rel="${BASH_REMATCH[2]:+${BASH_REMATCH[2]}/}${BASH_REMATCH[3]}"
        git -C "$PORT_TREE" check-ignore -q --no-index "$rel" && continue
    fi
    echo "$l"
done)
if [ -z "$d" ]; then echo "résultat identique à $PORT_TREE (apres-$last)"; else echo "DIFFÉRENCES avec $PORT_TREE :"; echo "$d" | head; fi
