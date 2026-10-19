#!/bin/bash
# triage.sh [début] [arbre] [série] — repart de l'état avant <début> (ex. 0008, défaut : base),
# applique les patches de la série dans l'ordre, commite chacun avec un tag « apres-NNNN »,
# range les hunks refusés dans $REJ_DIR/<patch>/. Statut par patch :
#   OK (strict) | AMONT (déjà présent) | FUZZ (patch --fuzz=3) | REJ(n) (n fichiers refusés) | +ABSENT
# Sans 2e/3e argument : $PORT_TREE et $SERIES. Pour bâtir REF_TREE : ./triage.sh 0000 "$REF_TREE" <série d'origine>
set -u
source "$(dirname "$0")/env.sh"
START=${1:-0000}; TREE=${2:-$PORT_TREE}; PDIR=${3:-$SERIES}
cd "$TREE" || exit 1
prev=$(git rev-list --max-parents=0 HEAD)
for p in $(ls "$PDIR"/*.patch | sort); do
    num=$(basename "$p" | cut -c1-4); [[ "$num" < "$START" ]] || break; prev="apres-$num"
done
git reset -q --hard "$prev" && git clean -qfdx
mkdir -p "$REJ_DIR"
for p in $(ls "$PDIR"/*.patch | sort); do
    n=$(basename "$p" .patch); num=${n:0:4}
    [[ "$num" < "$START" ]] && continue
    rm -rf "${REJ_DIR:?}/$n"
    if git apply --check "$p" 2>/dev/null; then
        git apply "$p" 2>/dev/null; st="OK"
    elif git apply --check -R "$p" 2>/dev/null; then
        st="AMONT"
    else
        out=$(patch -p1 --fuzz=3 -f --no-backup-if-mismatch < "$p" 2>&1)
        st="FUZZ"
        if find . -name '*.rej' -not -path './.git/*' | grep -q .; then
            mkdir -p "$REJ_DIR/$n"; echo "$out" > "$REJ_DIR/$n/patch.log"
            find . -name '*.rej' -not -path './.git/*' | while read -r r; do
                d="$REJ_DIR/$n/$(dirname "${r#./}")"; mkdir -p "$d"; mv "$r" "$d/"
            done
            st="REJ($(find "$REJ_DIR/$n" -name '*.rej' | wc -l))"
        fi
        echo "$out" | grep -q "can't find file" && st="$st+ABSENT"
    fi
    "${G[@]}" add -A && "${G[@]}" commit -q --allow-empty -m "$n [$st]"
    git tag -f "apres-$num" >/dev/null
    echo "$st $n"
done
