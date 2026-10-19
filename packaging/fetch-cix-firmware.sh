#!/bin/bash
# =============================================================================
# fetch-cix-firmware.sh — Paquet officiel des firmwares VPU de CIX (cix-vpu-firmware)
# BOOKWORM Sky1 Kernel Builder
#
# Les firmwares du VPU (amvx : décodage/encodage vidéo V4L2) ne sont pas dans les
# paquets Ubuntu. On reprend le paquet de CIX tel quel, avec sa licence
# (/usr/share/doc/cix-vpu-firmware/copyright) : le dépôt n'en garde aucune copie.
# Téléchargé une fois depuis le dépôt APT de CIX, empreinte SHA256 figée ici,
# puis réutilisé depuis le cache. Utilisé par install/install.sh et iso/build-iso.sh.
#
# Usage: ./fetch-cix-firmware.sh [--out <dir>]     (défaut : BUILD_DIR/cix-firmware)
#        Affiche le chemin du .deb vérifié sur la dernière ligne (stdout).
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR=""

# Version validée sur Orange Pi 6 Plus (2026-10-18 : décodage H.264 identique à l'ancien firmware)
CIX_REPO="https://archive.cixtech.com/debian"
CIX_DEB="cix-vpu-firmware_1.0.1-3_all.deb"
CIX_PATH="pool/main/c/cix-vpu-driver/$CIX_DEB"
CIX_SHA256="89eb2731eb0c5a2b88e96936ceb2679a5ab8f91c035af5ba06f4c7777d34a15d"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT_DIR="$2"; shift 2 ;;
        --help|-h) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo -e "${RED}Option inconnue: $1${NC}" >&2; exit 1 ;;
    esac
done

source "$PROJECT_DIR/config/board.conf"
OUT_DIR="${OUT_DIR:-$BUILD_DIR/cix-firmware}"
mkdir -p "$OUT_DIR"
DEB="$OUT_DIR/$CIX_DEB"

check() { [[ -f "$1" ]] && [[ "$(sha256sum < "$1" | cut -d' ' -f1)" == "$CIX_SHA256" ]]; }

if check "$DEB"; then
    echo -e "${GREEN}OK${NC} $CIX_DEB (cache, empreinte vérifiée)" >&2
else
    echo -e "${YELLOW}Téléchargement${NC} $CIX_REPO/$CIX_PATH" >&2
    curl -fsSL --retry 3 -o "$DEB.partial" "$CIX_REPO/$CIX_PATH" \
        || { rm -f "$DEB.partial"; echo -e "${RED}ERREUR: téléchargement impossible (réseau ? dépôt CIX ?)${NC}" >&2; exit 1; }
    if ! check "$DEB.partial"; then
        rm -f "$DEB.partial"
        echo -e "${RED}ERREUR: empreinte SHA256 de $CIX_DEB inattendue (paquet changé chez CIX ?)${NC}" >&2
        exit 1
    fi
    mv "$DEB.partial" "$DEB"
    echo -e "${GREEN}OK${NC} $CIX_DEB téléchargé, empreinte vérifiée" >&2
fi
echo "$DEB"
