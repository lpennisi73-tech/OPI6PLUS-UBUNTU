#!/bin/bash
# init-tree.sh <tarball.tar.xz> <dossier> — extrait un noyau et en fait un dépôt git
# (un commit « base ») utilisable comme REF_TREE ou PORT_TREE.
set -eu
TAR=$1; DEST=$2
[ -e "$DEST" ] && { echo "ERREUR: $DEST existe déjà" >&2; exit 1; }
source "$(dirname "$0")/env.sh"
mkdir -p "$DEST"
tar xf "$TAR" -C "$DEST" --strip-components=1
cd "$DEST" && git init -q && "${G[@]}" add -A -f && "${G[@]}" commit -q -m "base $(basename "$TAR" .tar.xz)"
echo "arbre prêt : $DEST"
