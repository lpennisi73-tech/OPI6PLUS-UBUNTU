#!/bin/bash
# =============================================================================
# export-public.sh — Publication du dépôt : copie propre vers un dépôt public séparé
# BOOKWORM Sky1 Kernel Builder
#
# Le dépôt de travail (privé) garde tout son historique. Le dépôt public ne reçoit
# que l'état commité (HEAD), sans les fichiers privés, en un commit par publication :
# aucun ancien commit, binaire ou fichier retiré ne peut y apparaître.
#   - fichiers privés retirés : PRIVATE_FILES ci-dessous ;
#   - contrôle avant commit : aucun motif de .public-forbidden (fichier privé, une
#     expression régulière par ligne) ne doit rester, sinon arrêt sans rien écrire ;
#   - auteur du commit : identité git du dépôt de travail.
# Ne pousse jamais : le push vers GitHub reste à faire à la main.
#
# Usage: tools/export-public.sh <dossier du dépôt public> [-m "<message>"]
#        Le dossier est créé (git init) s'il n'existe pas.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
die() { echo -e "${RED}ERREUR: $*${NC}" >&2; exit 1; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE_FILES=(CLAUDE.md .public-forbidden)
FORBIDDEN="$SRC/.public-forbidden"

DEST=""; MSG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m) MSG="$2"; shift 2 ;;
        --help|-h) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "option inconnue : $1" ;;
        *) DEST="$1"; shift ;;
    esac
done
[[ -n "$DEST" ]] || die "dossier du dépôt public manquant (voir --help)"
[[ -f "$FORBIDDEN" ]] || die "$FORBIDDEN absent : liste des motifs interdits nécessaire"
[[ -z "$(git -C "$SRC" status --porcelain)" ]] || die "dépôt de travail modifié : commiter d'abord (seul HEAD est publié)"
DEST="$(realpath -m "$DEST")"
[[ "$DEST" != "$SRC"* ]] || die "le dépôt public doit être hors du dépôt de travail"

REV=$(git -C "$SRC" rev-parse --short HEAD)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# 1. État commité, sans les fichiers privés
git -C "$SRC" archive HEAD | tar -x -C "$STAGE"
for f in "${PRIVATE_FILES[@]}"; do rm -rf "${STAGE:?}/$f"; done

# 2. Contrôle des motifs interdits (contenu des fichiers et noms de fichiers)
patterns=$(grep -vE '^\s*(#|$)' "$FORBIDDEN")
hits=$(cd "$STAGE" && grep -rnIE -f <(echo "$patterns") . || true)
names=$(cd "$STAGE" && find . | grep -E -f <(echo "$patterns") || true)
if [[ -n "$hits$names" ]]; then
    echo -e "${RED}Données privées trouvées, rien n'est publié :${NC}"
    [[ -n "$hits" ]] && echo "$hits" | cut -c1-200 | head -40
    [[ -n "$names" ]] && echo "$names"
    exit 1
fi
echo -e "${GREEN}OK${NC} aucun motif interdit ($(echo "$patterns" | wc -l) motifs, $(find "$STAGE" -type f | wc -l) fichiers)"

# 3. Dépôt public : remplacer son contenu par l'export, un commit
if [[ ! -d "$DEST/.git" ]]; then
    mkdir -p "$DEST"
    git -C "$DEST" init -q -b main
    echo -e "${YELLOW}Nouveau dépôt public${NC} : $DEST"
fi
git -C "$DEST" config user.name "$(git -C "$SRC" config user.name)"
git -C "$DEST" config user.email "$(git -C "$SRC" config user.email)"
find "$DEST" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -a "$STAGE"/. "$DEST"/
git -C "$DEST" add -A
if git -C "$DEST" diff --cached --quiet; then
    echo -e "${GREEN}OK${NC} dépôt public déjà à jour"
    exit 0
fi
git -C "$DEST" commit -q -m "${MSG:-Publication du $(date +%Y-%m-%d)}"
echo -e "${GREEN}OK${NC} commit $(git -C "$DEST" rev-parse --short HEAD) dans $DEST (depuis $REV)"
echo "Vérifier puis publier :"
echo "  git -C $DEST show --stat | head"
echo "  git -C $DEST remote add origin https://github.com/lpennisi73-tech/OPI6PLUS-UBUNTU.git   (1re fois)"
echo "  git -C $DEST push -u origin main"
