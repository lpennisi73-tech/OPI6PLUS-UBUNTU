#!/bin/bash
# =============================================================================
# install-deps.sh — Dépendances apt de BOOKWORM Sky1 Kernel Builder (Ubuntu 26.10)
#
# À lancer avant le premier build. Ne réinstalle rien de ce qui est déjà présent.
#
# Usage: sudo ./install-deps.sh [--check] [--yes] [--with-diag] [--with-distcc] [--with-iso]
#   --check        Lister seulement ce qui manque (pas besoin de root)
#   --yes          Installer sans confirmation (apt-get -y)
#   --with-diag    Ajouter les outils de diagnostic (glxinfo, vulkaninfo, v4l2-ctl, nvme…)
#   --with-distcc  Ajouter distcc (voir distcc-env.sh)
#   --with-iso     Ajouter les outils de remasterisation de l'ISO (iso/build-iso.sh)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

CHECK=false; YES=false; DIAG=false; DISTCC=false; ISO=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) CHECK=true ;;
        --yes) YES=true ;;
        --with-diag) DIAG=true ;;
        --with-distcc) DISTCC=true ;;
        --with-iso) ISO=true ;;
        --help|-h) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo -e "${RED}Option inconnue: $1${NC}" >&2; exit 1 ;;
    esac
    shift
done

# Build kernel + paquets .deb (make bindeb-pkg)
PKGS_BUILD="build-essential bc flex bison gawk cpio rsync kmod zstd xz-utils dpkg-dev debhelper
libssl-dev libelf-dev libdw-dev libncurses-dev python3"
# Sources, patches, veille Sky1-Linux
PKGS_SOURCES="git wget curl patch"
# Installation / boot (déjà présents sur une Ubuntu standard, vérifiés quand même)
PKGS_INSTALL="dracut grub-efi-arm64 pciutils util-linux pipewire-alsa"
# Diagnostic post-boot (diagnostics/check-system.sh, scripts-addons)
PKGS_DIAG="mesa-utils vulkan-tools glmark2-es2-drm v4l-utils nvme-cli usbutils"
# Remasterisation de l'ISO Ubuntu (extraction, couches squashfs, image EFI, gravure)
PKGS_ISO="xorriso squashfs-tools mtools dosfstools"

PKGS="$PKGS_BUILD $PKGS_SOURCES $PKGS_INSTALL"
$DIAG && PKGS="$PKGS $PKGS_DIAG"
$DISTCC && PKGS="$PKGS distcc"
$ISO && PKGS="$PKGS $PKGS_ISO"

echo -e "${BLUE}=== BOOKWORM Sky1 — dépendances Ubuntu ===${NC}"
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "Système : ${PRETTY_NAME:-?} ($(uname -m))"
    [[ "${ID:-}" == "ubuntu" ]] || echo -e "${YELLOW}ATTENTION: système non Ubuntu, noms de paquets non garantis${NC}"
fi
[[ "$(uname -m)" == "aarch64" ]] || echo -e "${YELLOW}ATTENTION: pas en ARM64 (build natif prévu)${NC}"
echo ""

MISSING=()
for p in $PKGS; do
    status=$(dpkg-query -W -f='${db:Status-Abbrev}' "$p" 2>/dev/null || true)
    if [[ "$status" == ii* ]]; then
        echo -e "  ${GREEN}OK${NC}      $p"
    else
        echo -e "  ${RED}MANQUE${NC}  $p"
        MISSING+=("$p")
    fi
done
echo ""

if [[ ${#MISSING[@]} -eq 0 ]]; then
    echo -e "${GREEN}✓ Toutes les dépendances sont installées.${NC}"
    exit 0
fi

echo -e "${YELLOW}Manquants (${#MISSING[@]}) :${NC} ${MISSING[*]}"
if $CHECK; then
    opts=""
    $DIAG && opts+=" --with-diag"
    $DISTCC && opts+=" --with-distcc"
    $ISO && opts+=" --with-iso"
    echo "Installer avec : sudo $0$opts"
    exit 10
fi

[[ $EUID -eq 0 ]] || { echo -e "${RED}ERREUR: lancer en root (sudo) pour installer, ou --check${NC}" >&2; exit 1; }

apt-get update
if $YES; then
    apt-get install -y "${MISSING[@]}"
else
    apt-get install "${MISSING[@]}"
fi

echo ""
echo -e "${GREEN}✓ Dépendances installées.${NC} Ensuite : ./bookworm-sky1-build.sh --kernel <track>"
