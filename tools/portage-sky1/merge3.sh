#!/bin/bash
# merge3.sh <num> <fichier>... — fusion à trois voies pour le patch <num>, écrite dans $PORT_TREE :
#   amont        = $PORT_TREE avant le patch (nouvelle base + série déjà portée)
#   base         = $REF_TREE avant le patch
#   constructeur = $REF_TREE après le patch (résultat voulu)
# Laisse des marqueurs <<<<<<< amont / >>>>>>> constructeur à résoudre (pick.py).
set -u
source "$(dirname "$0")/env.sh"
NUM=$1; shift
W=$(mktemp -d)
for f in "$@"; do
    git -C "$PORT_TREE" show "$(prev_tag "$PORT_TREE" "$NUM"):$f" > "$W/ours" 2>/dev/null || : > "$W/ours"
    git -C "$REF_TREE" show "$(prev_tag "$REF_TREE" "$NUM"):$f" > "$W/base" 2>/dev/null || : > "$W/base"
    git -C "$REF_TREE" show "apres-$NUM:$f" > "$W/theirs"
    git merge-file -L amont -L base -L constructeur "$W/ours" "$W/base" "$W/theirs"
    n=$?
    cp "$W/ours" "$PORT_TREE/$f"
    [ $n -eq 0 ] && echo "  fusion propre : $f" || echo "  CONFLITS ($n) : $f"
done
rm -rf "$W"
