#!/bin/bash
# =============================================================================
# build-settings-deb.sh — Paquet bookworm-sky1-settings (réglages Orange Pi 6 Plus)
# BOOKWORM Sky1 Kernel Builder
#
# Rassemble les réglages système du dépôt dans un .deb, comme ubuntu-x1e-settings
# pour les portables Snapdragon : utilisé par install/install.sh et par l'ISO
# (iso/build-iso.sh). Désinstallation : apt purge bookworm-sky1-settings.
#
# Contenu : entrées GRUB Sky1 (/etc/grub.d/07_sky1, disque détecté par update-grub),
# DTB par noyau (hook /etc/kernel), dracut, udev, veille, gouverneur CPU, modules,
# WirePlumber / PipeWire, environnement de session.
# Les firmwares VPU viennent du paquet officiel de CIX (packaging/fetch-cix-firmware.sh).
# Les réglages par défaut vont sous /usr ; /etc reste à l'utilisateur et passe en priorité.
# Version : 1.0.<nombre de commits du dépôt>.
#
# Usage: ./build-settings-deb.sh [--out <dir>]     (défaut : BUILD_DIR de board.conf)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT_DIR="$2"; shift 2 ;;
        --help|-h) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo -e "${RED}Option inconnue: $1${NC}" >&2; exit 1 ;;
    esac
done

source "$PROJECT_DIR/config/board.conf"
OUT_DIR="${OUT_DIR:-$BUILD_DIR}"
mkdir -p "$OUT_DIR"

PKG=bookworm-sky1-settings
COUNT=$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || echo 0)
VERSION="1.0.${COUNT}"
if [[ -n "$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null)" ]]; then
    echo -e "${YELLOW}ATTENTION: dépôt modifié non commité, le paquet ${VERSION} ne correspond à aucun commit${NC}"
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
R="$STAGE/root"
C="$PROJECT_DIR/config"

inst() {    # inst <mode> <source> <destination dans le paquet>
    install -D -m "$1" "$2" "$R$3"
}

# --- GRUB, DTB par noyau, réglages de démarrage ---
inst 755 "$C/grub/07_sky1" /etc/grub.d/07_sky1
inst 755 "$C/kernel/zz-bookworm-sky1-dtb" /etc/kernel/postinst.d/zz-bookworm-sky1-dtb
inst 755 "$C/kernel/zz-bookworm-sky1-dtb" /etc/kernel/postrm.d/zz-bookworm-sky1-dtb
mkdir -p "$R/etc/default"
cat > "$R/etc/default/bookworm-sky1" << EOF
# BOOKWORM Sky1 — réglages de démarrage des noyaux Sky1 (paquet $PKG)
# Lu par /etc/grub.d/07_sky1 et le hook DTB. Après modification : sudo update-grub

# false = pas d'entrée Sky1 dans le menu GRUB
SKY1_GRUB_ENABLE=true

SKY1_BOARD_NAME="${BOARD_NAME}"
SKY1_DTB_NAME="${DTB_NAME}"

# Paramètres du noyau Sky1 (boot devicetree : acpi=off obligatoire)
SKY1_CMDLINE="${KERNEL_CMDLINE}"
EOF

# --- initramfs (dracut lit /usr/lib/dracut/dracut.conf.d) ---
inst 644 "$PROJECT_DIR/dracut/sky1.conf" /usr/lib/dracut/dracut.conf.d/10-bookworm-sky1.conf
# Règles udev Sky1 aussi dans l'initramfs : les contrôleurs USB-C y démarrent, et leur xHCI peut
# passer en veille (sans réveil) avant que la règle ne s'applique sur la racine
{
    echo ""
    echo "# Règles udev Sky1 (ajouté par build-settings-deb.sh) : USB-C et GPU sans veille runtime dès l'initramfs"
    printf 'install_items+=" '
    for f in "$C"/udev/*.rules; do printf '/usr/lib/udev/rules.d/%s ' "$(basename "$f")"; done
    echo '"'
} >> "$R/usr/lib/dracut/dracut.conf.d/10-bookworm-sky1.conf"
# Même chose pour initramfs-tools (initrd du système live de l'ISO)
inst 755 "$C/initramfs-tools/hooks/bookworm-sky1" /usr/share/initramfs-tools/hooks/bookworm-sky1

# --- Modules ---
mkdir -p "$R/usr/lib/modules-load.d" "$R/usr/lib/modprobe.d"
{
    echo "# BOOKWORM Sky1 — modules chargés au démarrage (voir config/board.conf)"
    for m in ${MODULES_AUTOLOAD:-}; do echo "$m"; done
} > "$R/usr/lib/modules-load.d/bookworm-sky1.conf"
{
    echo "# BOOKWORM Sky1 — options des modules (voir config/board.conf)"
    for e in ${MODPROBE_OPTIONS:-}; do echo "options ${e%%:*} ${e#*:}"; done
} > "$R/usr/lib/modprobe.d/bookworm-sky1.conf"

# --- udev, veille, session, audio ---
for f in "$C"/udev/*.rules; do inst 644 "$f" "/usr/lib/udev/rules.d/$(basename "$f")"; done
for f in "$C"/systemd/sleep.conf.d/*.conf; do inst 644 "$f" "/usr/lib/systemd/sleep.conf.d/$(basename "$f")"; done
for f in "$C"/environment.d/*.conf; do inst 644 "$f" "/usr/lib/environment.d/$(basename "$f")"; done
for f in "$C"/wireplumber/*.conf; do inst 644 "$f" "/usr/share/wireplumber/wireplumber.conf.d/$(basename "$f")"; done
for f in "$C"/pipewire/pipewire-pulse.conf.d/*.conf; do
    inst 644 "$f" "/usr/share/pipewire/pipewire-pulse.conf.d/$(basename "$f")"
done

# --- Gouverneur CPU ---
inst 755 "$C/cpufreq/sky1-cpufreq-tune" /usr/libexec/bookworm-sky1/sky1-cpufreq-tune
inst 644 "$C/cpufreq/sky1-cpufreq" /etc/default/sky1-cpufreq
inst 644 "$C/systemd/system/sky1-cpufreq-tune.service" /usr/lib/systemd/system/sky1-cpufreq-tune.service

# --- Métadonnées ---
mkdir -p "$R/DEBIAN"
(cd "$R" && find etc -type f | sed 's|^|/|' | sort) > "$R/DEBIAN/conffiles"
SIZE=$(du -sk --exclude=DEBIAN "$R" | cut -f1)
cat > "$R/DEBIAN/control" << EOF
Package: $PKG
Version: $VERSION
Architecture: arm64
Maintainer: kennytech73 <contact@bookworm-mon0.org>
Installed-Size: $SIZE
Depends: systemd
Recommends: pipewire-alsa, wireplumber, cix-vpu-firmware
Section: admin
Priority: optional
Description: Réglages BOOKWORM Sky1 pour Orange Pi 6 Plus (CIX CD8180)
 Entrées GRUB des noyaux Sky1 (devicetree + acpi=off), DTB par noyau,
 initramfs dracut, règles udev (USB-C et GPU sans veille runtime), veille
 système bloquée, gouverneur CPU ondemand réglé, modules, audio DP/HDMI
 (WirePlumber, PipeWire) et environnement de session GNOME. Firmwares VPU :
 paquet cix-vpu-firmware de CIX.
EOF

cat > "$R/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
    # DTB des noyaux Sky1 déjà installés
    for d in /usr/lib/linux-image-*-sky1-*; do
        [ -d "$d" ] && /etc/kernel/postinst.d/zz-bookworm-sky1-dtb "${d#/usr/lib/linux-image-}"
    done
    # Comme debhelper : activé à la première installation, choix de l'administrateur gardé ensuite
    deb-systemd-helper unmask sky1-cpufreq-tune.service >/dev/null || true
    if deb-systemd-helper --quiet was-enabled sky1-cpufreq-tune.service; then
        deb-systemd-helper enable sky1-cpufreq-tune.service >/dev/null || true
    else
        deb-systemd-helper update-state sky1-cpufreq-tune.service >/dev/null || true
    fi
    if [ -d /run/systemd/system ]; then
        systemctl daemon-reload || true
        udevadm control --reload-rules 2>/dev/null || true
    fi
    # Dans le chroot de l'ISO il n'y a pas de grub.cfg : l'installateur lance update-grub
    if [ -e /boot/grub/grub.cfg ] && command -v update-grub >/dev/null; then
        update-grub || true
    fi
fi
EOF
cat > "$R/DEBIAN/postrm" << 'EOF'
#!/bin/sh
set -e
case "$1" in
    remove)
        deb-systemd-helper mask sky1-cpufreq-tune.service >/dev/null || true
        [ -d /run/systemd/system ] && systemctl daemon-reload || true
        ;;
    purge)
        deb-systemd-helper purge sky1-cpufreq-tune.service >/dev/null || true
        deb-systemd-helper unmask sky1-cpufreq-tune.service >/dev/null || true
        rm -f /boot/dtb/sky1-orangepi-6-plus-*-sky1-*.dtb
        rmdir --ignore-fail-on-non-empty /boot/dtb 2>/dev/null || true
        ;;
esac
if [ "$1" = remove ] || [ "$1" = purge ]; then
    if [ -e /boot/grub/grub.cfg ] && command -v update-grub >/dev/null; then
        update-grub || true
    fi
fi
EOF
chmod 755 "$R/DEBIAN/postinst" "$R/DEBIAN/postrm"

DEB="$OUT_DIR/${PKG}_${VERSION}_arm64.deb"
dpkg-deb --root-owner-group -Zxz --build "$R" "$DEB" >/dev/null
echo -e "${GREEN}OK${NC} $DEB"
