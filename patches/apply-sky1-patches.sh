#!/bin/bash
# =============================================================================
# apply-sky1-patches.sh — applique la série Sky1 en mode strict
#
# Usage (depuis la racine des sources noyau) :
#   apply-sky1-patches.sh <dossier de la série>     ex. patches/sky1-7.2
#
# Strict : aucun fuzz, aucun décalage toléré au-delà de ce que fait `patch` sans
# fuzz, arrêt au premier patch qui ne s'applique pas. La série du dépôt est
# régénérée pour s'appliquer exactement sur la version visée (voir
# tools/portage-sky1/check-strict.sh) : un patch qui ne passe plus signale une
# base différente, à porter avec tools/portage-sky1, pas à forcer. (Le fuzz peut
# placer un ajout au mauvais endroit sans aucune erreur.)
#
# Kenny / BOOKWORM — OrangePi 6 Plus / CIX CD8180 — Ubuntu ARM64
# =============================================================================
set -e

PATCHES_DIR="${1:?Usage: $0 <dossier de la série>}"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

[[ -d "$PATCHES_DIR" ]] || { echo -e "${RED}ERREUR: dossier de patches introuvable: $PATCHES_DIR${NC}"; exit 1; }
[[ -f Makefile ]]       || { echo -e "${RED}ERREUR: lancer depuis la racine des sources noyau${NC}"; exit 1; }

mapfile -t PATCHES < <(ls "$PATCHES_DIR"/*.patch 2>/dev/null | sort)
[[ ${#PATCHES[@]} -gt 0 ]] || { echo -e "${RED}ERREUR: aucun .patch dans $PATCHES_DIR${NC}"; exit 1; }

echo -e "${BLUE}=== Série Sky1 : ${#PATCHES[@]} patches (${PATCHES_DIR}), mode strict ===${NC}"

applied=0
for pfile in "${PATCHES[@]}"; do
    pname="$(basename "$pfile")"
    if ! out=$(patch -p1 --dry-run --fuzz=0 --no-backup-if-mismatch < "$pfile" 2>&1); then
        echo -e "  ${RED}ÉCHEC${NC}  $pname"
        echo "$out" | head -20
        echo -e "${RED}Arrêt : $applied/${#PATCHES[@]} appliqués. Sources partiellement patchées :${NC}"
        echo "  ré-extraire le noyau avant de relancer (voir tools/portage-sky1/README.md)."
        exit 1
    fi
    patch -p1 --fuzz=0 --no-backup-if-mismatch -s < "$pfile"
    echo -e "  ${GREEN}OK${NC}  $pname"
    applied=$((applied + 1))
done

echo -e "${CYAN}$applied/${#PATCHES[@]} patches appliqués${NC}"
