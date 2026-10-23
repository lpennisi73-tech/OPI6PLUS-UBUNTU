#!/bin/bash
# =============================================================================
# build-meta-deb.sh — Méta-paquets linux-image-sky1 / linux-headers-sky1
# BOOKWORM Sky1 Kernel Builder
#
# Le kver fait partie du nom des paquets du noyau (linux-image-7.2.12-sky1-custom) :
# un nouveau noyau est un autre paquet, qu'apt upgrade n'installerait jamais seul.
# Comme linux-image-generic chez Ubuntu, linux-image-sky1 (paquet vide) dépend du noyau
# Sky1 le plus récent et prend sa version : le dépôt APT publie le méta-paquet avec le
# noyau, apt upgrade suit. bookworm-sky1-settings le recommande (systèmes déjà installés).
# Les anciens noyaux restent installés (secours dans GRUB) : à retirer à la main.
#
# Usage: ./build-meta-deb.sh [--out <dir>] <linux-image-<kver>_*.deb> [<linux-headers-<kver>_*.deb>]
#        (défaut de --out : dossier du paquet noyau). Affiche le chemin de chaque .deb produit.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; NC='\033[0m'
die() { echo -e "${RED}ERREUR: $1${NC}" >&2; exit 1; }

OUT_DIR=""
DEBS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT_DIR="$2"; shift 2 ;;
        --help|-h) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "Option inconnue: $1" ;;
        *) DEBS+=("$1"); shift ;;
    esac
done
[[ ${#DEBS[@]} -ge 1 ]] || die "paquet linux-image-<kver> attendu (--help)"

build_meta() {    # build_meta <paquet noyau .deb> <linux-image|linux-headers>
    local deb="$1" kind="$2" pkg version kver meta stage out what
    [[ -f "$deb" ]] || die "$deb introuvable"
    pkg=$(dpkg-deb -f "$deb" Package)
    version=$(dpkg-deb -f "$deb" Version)
    [[ "$pkg" == "$kind"-*-sky1-* ]] || die "$deb : $pkg n'est pas un paquet $kind Sky1"
    kver="${pkg#"$kind"-}"
    meta="${kind}-sky1"
    what="Noyau"
    [[ "$kind" == linux-headers ]] && what="En-têtes du noyau"
    out="${OUT_DIR:-$(dirname "$deb")}"
    mkdir -p "$out"

    stage=$(mktemp -d)
    chmod 755 "$stage"
    mkdir -p "$stage/DEBIAN" "$stage/usr/share/doc/$meta"
    cat > "$stage/DEBIAN/control" << EOF
Package: $meta
Version: $version
Architecture: arm64
Maintainer: kennytech73 <contact@bookworm-mon0.org>
Depends: $pkg (>= $version)
Section: kernel
Priority: optional
Description: $what Sky1 le plus récent pour Orange Pi 6 Plus (méta-paquet)
 Dépend du dernier paquet $kind BOOKWORM Sky1 ($kver) : les mises à jour du dépôt
 APT BOOKWORM installent ainsi chaque nouveau noyau. Les anciens restent
 installés comme secours dans GRUB.
EOF
    printf '%s\n' "Méta-paquet BOOKWORM Sky1 : dépend de $pkg $version." \
        > "$stage/usr/share/doc/$meta/README"
    dpkg-deb --root-owner-group -Zxz --build "$stage" "$out/${meta}_${version}_arm64.deb" >/dev/null
    rm -rf "$stage"
    echo "$out/${meta}_${version}_arm64.deb"
}

build_meta "${DEBS[0]}" linux-image
[[ ${#DEBS[@]} -ge 2 ]] && build_meta "${DEBS[1]}" linux-headers
exit 0
