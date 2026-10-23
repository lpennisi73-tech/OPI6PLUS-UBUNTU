#!/bin/bash
# =============================================================================
# install.sh — Installation kernel Sky1 OrangePi 6 Plus (Ubuntu 26.10)
# BOOKWORM Sky1 Kernel Builder v2.0-ubuntu
#
# Installe le paquet de réglages bookworm-sky1-settings (packaging/build-settings-deb.sh :
# entrées GRUB Sky1, DTB par kernel, dracut, udev, cpufreq, audio, session...), puis
# les paquets .deb produits par `make bindeb-pkg` et les méta-paquets linux-image-sky1 /
# linux-headers-sky1 (packaging/build-meta-deb.sh) qui suivent le dernier noyau.
# Les hooks Ubuntu (/etc/kernel/postinst.d) génèrent l'initramfs (dracut), copient
# le DTB (hook du paquet de réglages) et lancent update-grub pendant dpkg -i.
#
# Usage: ./install.sh [--kernel <track>] [--kernel-dir <path>] [--deb-dir <path>] [--with-dbg] [--no-firmware]
# =============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KERNEL_BUILD_DIR=""
KERNEL_TRACK=""
DEB_DIR=""
DO_FIRMWARE=true
DO_DBG=false

usage() {
    echo "Usage: $0 [options]"
    echo "  --kernel <track>      Track (ex: 7.2.12-stable) ; defaut: deduit de --kernel-dir"
    echo "  --kernel-dir <path>   Repertoire build kernel"
    echo "  --deb-dir <path>      Repertoire des .deb (defaut: parent de --kernel-dir)"
    echo "  --with-dbg            Installer aussi linux-image-<kver>-dbg (symboles, crash/kdump)"
    echo "  --no-firmware         Ne pas installer les firmwares VPU de CIX (cix-vpu-firmware)"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel) KERNEL_TRACK="$2"; shift 2 ;;
        --kernel-dir) KERNEL_BUILD_DIR="$2"; shift 2 ;;
        --deb-dir) DEB_DIR="$2"; shift 2 ;;
        --with-dbg) DO_DBG=true; shift ;;
        --no-firmware) DO_FIRMWARE=false; shift ;;
        --help) usage ;;
        *) echo "Option inconnue: $1"; usage ;;
    esac
done

[[ $EUID -ne 0 ]] && { echo -e "${RED}ERREUR: Lance en root (sudo)${NC}"; exit 1; }

# --- Charger la config ---
source "$PROJECT_DIR/config/board.conf" 2>/dev/null || {
    echo -e "${RED}ERREUR: board.conf introuvable${NC}"; exit 1
}

# --- Detection auto UUID root (override board.conf) ---
DETECTED_UUID=$(findmnt -no UUID / 2>/dev/null)
if [[ -n "$DETECTED_UUID" ]]; then
    [[ -n "$ROOT_UUID" && "$DETECTED_UUID" != "$ROOT_UUID" ]] && \
        echo -e "${YELLOW}UUID root detecte: $DETECTED_UUID (board.conf: $ROOT_UUID)${NC}"
    ROOT_UUID="$DETECTED_UUID"
fi

# --- Track kernel ---
# Ordre : --kernel <track>, sinon deduit de --kernel-dir (linux-7.0 -> le .conf dont
# KERNEL_TARBALL est linux-7.0.tar.xz). Jamais de choix par defaut : un mauvais track
# donne un mauvais nom de fichier GRUB et un mauvais titre de menu.
if [[ -z "$KERNEL_TRACK" && -n "$KERNEL_BUILD_DIR" ]]; then
    src_name="$(basename "$(cd "$KERNEL_BUILD_DIR" 2>/dev/null && pwd)")"
    matches=()
    for conf in "$PROJECT_DIR/config/kernels/"*.conf; do
        tb=$( source "$conf"; echo "${KERNEL_TARBALL%.tar.xz}" )
        [[ "$tb" == "$src_name" ]] && matches+=("$(basename "$conf" .conf)")
    done
    if [[ ${#matches[@]} -eq 1 ]]; then
        KERNEL_TRACK="${matches[0]}"
    elif [[ ${#matches[@]} -gt 1 ]]; then
        echo -e "${RED}ERREUR: plusieurs tracks pour $src_name : ${matches[*]} — preciser --kernel <track>${NC}"
        exit 1
    fi
fi
[[ -z "$KERNEL_TRACK" ]] && {
    echo -e "${RED}ERREUR: track kernel inconnu — preciser --kernel <track> (ex: 7.2.12-stable)${NC}"
    echo "  Tracks: $(ls "$PROJECT_DIR/config/kernels/" | sed 's/\.conf$//' | tr '\n' ' ')"
    exit 1
}
KERNEL_CONF="$PROJECT_DIR/config/kernels/${KERNEL_TRACK}.conf"
[[ -f "$KERNEL_CONF" ]] || { echo -e "${RED}ERREUR: $KERNEL_CONF introuvable${NC}"; exit 1; }
source "$KERNEL_CONF"

# Auto-detecter le repertoire build
if [[ -z "$KERNEL_BUILD_DIR" ]]; then
    for candidate in \
        "${BUILD_DIR}/linux-${KERNEL_FULL_VERSION}" \
        "${BUILD_DIR}/linux-${KERNEL_VERSION}" \
        "/usr/src/linux-${KERNEL_FULL_VERSION}"; do
        if [[ -f "$candidate/arch/arm64/boot/Image" ]]; then
            KERNEL_BUILD_DIR="$candidate"
            break
        fi
    done
fi

[[ -z "$KERNEL_BUILD_DIR" ]] && {
    echo -e "${RED}ERREUR: Repertoire build kernel non trouve${NC}"
    echo "  Specifie avec: --kernel-dir /path/to/linux-${KERNEL_FULL_VERSION}"
    exit 1
}
KERNEL_BUILD_DIR="$(cd "$KERNEL_BUILD_DIR" && pwd)"
[[ -z "$DEB_DIR" ]] && DEB_DIR="$(dirname "$KERNEL_BUILD_DIR")"

# kver reel (= nom de /lib/modules/<kver>, ex. 7.0.0-sky1-custom)
KVER=$(make -s -C "$KERNEL_BUILD_DIR" kernelrelease 2>/dev/null)
[[ -z "$KVER" ]] && { echo -e "${RED}ERREUR: kernelrelease introuvable dans $KERNEL_BUILD_DIR${NC}"; exit 1; }

# Paquets .deb les plus recents pour ce kver (jamais linux-libc-dev ; -dbg seulement avec --with-dbg)
DEB_IMAGE=$(ls -t "$DEB_DIR"/linux-image-"${KVER}"_*.deb 2>/dev/null | head -1)
DEB_HEADERS=$(ls -t "$DEB_DIR"/linux-headers-"${KVER}"_*.deb 2>/dev/null | head -1)
DEB_DBG=""
if $DO_DBG && [[ -n "$DEB_IMAGE" ]]; then
    # Seulement le -dbg du même build : même version et construit après l'image
    # (un build --no-dbg laisse l'ancien -dbg ; la version repart à -1 sur un arbre neuf)
    DEB_DBG=$(ls -t "$DEB_DIR"/linux-image-"${KVER}"-dbg_*.deb 2>/dev/null | head -1)
    if [[ -n "$DEB_DBG" ]] && { [[ "$(dpkg-deb -f "$DEB_DBG" Version)" != "$(dpkg-deb -f "$DEB_IMAGE" Version)" ]] \
            || [[ "$DEB_DBG" -ot "$DEB_IMAGE" ]]; }; then
        DEB_DBG=""
    fi
fi
if $DO_DBG && [[ -z "$DEB_DBG" ]]; then
    echo -e "${YELLOW}ATTENTION: --with-dbg mais aucun linux-image-${KVER}-dbg_*.deb de ce build (--no-dbg, KERNEL_DBG_PKG=no ou KERNEL_DEBUG_INFO=no ?)${NC}"
fi
[[ -z "$DEB_IMAGE" ]] && {
    echo -e "${RED}ERREUR: linux-image-${KVER}_*.deb introuvable dans $DEB_DIR${NC}"
    echo "  Compile d'abord : ./bookworm-sky1-build.sh --kernel <track>"
    exit 1
}

# =============================================================================
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   BOOKWORM Sky1 Kernel Installer v2.0-ubuntu   ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""
echo -e "Board        : ${CYAN}${BOARD_NAME}${NC}"
echo -e "Track        : ${CYAN}${KERNEL_TRACK} (${SKY1_TRACK})${NC}"
echo -e "Kernel       : ${CYAN}${KVER}${NC}"
echo -e "Build dir    : ${CYAN}${KERNEL_BUILD_DIR}${NC}"
echo -e "Paquet image : ${CYAN}$(basename "$DEB_IMAGE")${NC}"
[[ -n "$DEB_HEADERS" ]] && echo -e "Paquet hdrs  : ${CYAN}$(basename "$DEB_HEADERS")${NC}"
[[ -n "$DEB_DBG" ]] && echo -e "Paquet dbg   : ${CYAN}$(basename "$DEB_DBG")${NC}"
echo ""

# =============================================================================
# ETAPE 1 — Paquet de réglages bookworm-sky1-settings (AVANT le kernel : son hook
# copie le DTB et sa config dracut sert à l'initramfs générés pendant dpkg -i)
# =============================================================================
echo -e "${YELLOW}--- Etape 1: Paquet bookworm-sky1-settings ---${NC}"
"$PROJECT_DIR/packaging/build-settings-deb.sh" --out "$DEB_DIR"
DEB_SETTINGS=$(ls -t "$DEB_DIR"/bookworm-sky1-settings_*_arm64.deb | head -1)

# Migration : les anciennes versions d'install.sh copiaient les réglages dans /etc, qui passe
# avant /usr. Une copie identique au dépôt est retirée (le paquet fournit la même chose sous
# /usr) ; une copie modifiée est gardée, avec un avertissement.
drop_if_same() {    # drop_if_same <fichier /etc> <contenu attendu (fichier)>
    [[ -e "$1" ]] || return 0
    if cmp -s "$1" "$2"; then
        rm -f "$1"
        echo -e "${GREEN}OK${NC} ancienne copie retirée : $1"
    else
        echo -e "${YELLOW}GARDE${NC} $1 modifié (prioritaire sur le réglage du paquet)"
    fi
}
EXPECTED=$(mktemp)
C="$PROJECT_DIR/config"
drop_if_same /etc/dracut.conf.d/sky1.conf "$PROJECT_DIR/dracut/sky1.conf"
for f in "$C"/udev/*.rules; do drop_if_same "/etc/udev/rules.d/$(basename "$f")" "$f"; done
for f in "$C"/systemd/sleep.conf.d/*.conf; do drop_if_same "/etc/systemd/sleep.conf.d/$(basename "$f")" "$f"; done
for f in "$C"/environment.d/*.conf; do drop_if_same "/etc/environment.d/$(basename "$f")" "$f"; done
for f in "$C"/wireplumber/*.conf; do drop_if_same "/etc/wireplumber/wireplumber.conf.d/$(basename "$f")" "$f"; done
for f in "$C"/pipewire/pipewire-pulse.conf.d/*.conf; do
    drop_if_same "/etc/pipewire/pipewire-pulse.conf.d/$(basename "$f")" "$f"
done
for mod in ${MODULES_AUTOLOAD:-}; do
    echo "$mod" > "$EXPECTED"; drop_if_same "/etc/modules-load.d/sky1-${mod}.conf" "$EXPECTED"
done
for entry in ${MODPROBE_OPTIONS:-}; do
    echo "options ${entry%%:*} ${entry#*:}" > "$EXPECTED"
    drop_if_same "/etc/modprobe.d/sky1-${entry%%:*}.conf" "$EXPECTED"
done
rm -f "$EXPECTED"
drop_if_same /usr/local/sbin/sky1-cpufreq-tune "$C/cpufreq/sky1-cpufreq-tune"
if head -1 /etc/systemd/system/sky1-cpufreq-tune.service 2>/dev/null | grep -q '^# BOOKWORM Sky1'; then
    systemctl disable sky1-cpufreq-tune.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/sky1-cpufreq-tune.service
    echo -e "${GREEN}OK${NC} ancien service /etc/systemd/system/sky1-cpufreq-tune.service retiré"
fi
# Anciennes entrées GRUB à UUID en dur (remplacées par /etc/grub.d/07_sky1 du paquet)
for old in /etc/grub.d/0[67]_sky1_*; do
    [[ -f "$old" ]] && grep -q 'Genere automatiquement par install.sh' "$old" || continue
    rm -f "$old"
    echo -e "${GREEN}OK${NC} ancienne entrée GRUB retirée : $old"
done

# --force-confold : un /etc/default/* modifié par l'utilisateur est gardé sans question
dpkg -i --force-confold "$DEB_SETTINGS"
echo -e "${GREEN}OK${NC} $(basename "$DEB_SETTINGS")"

# =============================================================================
# ETAPE 2 — Paquets .deb (kernel, modules, dtbs ; initramfs, DTB et GRUB via hooks)
# =============================================================================
echo ""
echo -e "${YELLOW}--- Etape 2: Installation paquets ---${NC}"
# Méta-paquets linux-image-sky1 (+ linux-headers-sky1) : suivent ce noyau, puis les noyaux du
# dépôt APT BOOKWORM (packaging/build-meta-deb.sh), construits à côté des paquets du noyau
mapfile -t DEB_META < <("$PROJECT_DIR/packaging/build-meta-deb.sh" "$DEB_IMAGE" ${DEB_HEADERS:+"$DEB_HEADERS"})
dpkg -i "$DEB_IMAGE" ${DEB_HEADERS:+"$DEB_HEADERS"} ${DEB_DBG:+"$DEB_DBG"} "${DEB_META[@]}"
echo -e "${GREEN}OK${NC} Paquets installes ($(for d in "${DEB_META[@]}"; do basename "$d"; done | paste -sd' '))"

KERNEL_IMG="/boot/vmlinuz-${KVER}"
INITRD="/boot/initrd.img-${KVER}"
DTB_PATH="/boot/dtb/${DTB_NAME%.dtb}-${KVER}.dtb"
[[ -f "$KERNEL_IMG" ]] || { echo -e "${RED}ERREUR: $KERNEL_IMG absent apres dpkg${NC}"; exit 1; }

# =============================================================================
# ETAPE 3 — DTB (copié par le hook /etc/kernel/postinst.d/zz-bookworm-sky1-dtb)
# =============================================================================
echo ""
echo -e "${YELLOW}--- Etape 3: DTB ---${NC}"
[[ -f "$DTB_PATH" ]] || { echo -e "${RED}ERREUR: $DTB_PATH absent (${DTB_NAME} manque dans le paquet ?)${NC}"; exit 1; }
echo -e "${GREEN}OK${NC} DTB: $DTB_PATH ($(du -h "$DTB_PATH" | cut -f1))"

# =============================================================================
# ETAPE 4 — Firmwares. VPU : paquet officiel de CIX (cix-vpu-firmware, avec sa licence),
# téléchargé et vérifié par packaging/fetch-cix-firmware.sh. APRÈS l'étape 1 : les anciens
# paquets de réglages (<= 1.0.17x) livraient eux-mêmes les .fwb, retirés par la mise à jour.
# GPU Mali : fourni par Ubuntu (linux-firmware-misc), seulement contrôlé.
# =============================================================================
echo ""
echo -e "${YELLOW}--- Etape 4: Firmwares ---${NC}"
if $DO_FIRMWARE; then
    DEB_CIX_FW=$("$PROJECT_DIR/packaging/fetch-cix-firmware.sh")
    dpkg -i "$DEB_CIX_FW"
    echo -e "${GREEN}OK${NC} $(basename "$DEB_CIX_FW") (VPU)"
else
    echo -e "${YELLOW}SKIP${NC} firmwares VPU (--no-firmware)"
fi
if compgen -G "/lib/firmware/arm/mali/arch12.8/mali_csffw.bin*" > /dev/null; then
    echo -e "${GREEN}OK${NC} firmware GPU Mali (linux-firmware)"
else
    echo -e "${YELLOW}ATTENTION${NC} firmware GPU Mali absent : sudo apt install linux-firmware"
fi

# =============================================================================
# ETAPE 5 — ALSA -> PipeWire (les applications ALSA/GStreamer passent par PipeWire)
# Sans ces liens, le peripherique "default" ouvre directement cix_sky1 (DisplayPort),
# deja tenu par PipeWire en profil Pro Audio : pas de son dans Totem et les apps ALSA.
# Sous Ubuntu, le paquet pipewire-alsa cree normalement deja ces liens.
# =============================================================================
ALSA_SRC=/usr/share/alsa/alsa.conf.d
if [[ -d "$ALSA_SRC" ]]; then
    echo ""
    echo -e "${YELLOW}--- Etape 5: ALSA -> PipeWire ---${NC}"
    mkdir -p /etc/alsa/conf.d
    for f in 50-pipewire.conf 99-pipewire-default.conf; do
        if [[ ! -e "$ALSA_SRC/$f" ]]; then
            echo -e "${YELLOW}ATTENTION${NC} $ALSA_SRC/$f absent (sudo apt install pipewire-alsa)"
        elif [[ -L "/etc/alsa/conf.d/$f" ]]; then
            echo -e "${GREEN}OK${NC} alsa: $f deja lie"
        elif [[ -e "/etc/alsa/conf.d/$f" ]]; then
            echo -e "${YELLOW}SKIP${NC} /etc/alsa/conf.d/$f existe deja (fichier utilisateur conserve)"
        else
            ln -s "$ALSA_SRC/$f" "/etc/alsa/conf.d/$f"
            echo -e "${GREEN}OK${NC} alsa: $f"
        fi
    done
fi

# =============================================================================
# ETAPE 6 — Initramfs (normalement deja genere par le hook dracut de dpkg)
# =============================================================================
echo ""
echo -e "${YELLOW}--- Etape 6: Initramfs ---${NC}"
if [[ -f "$INITRD" ]]; then
    echo -e "${GREEN}OK${NC} Initramfs: $INITRD ($(du -h "$INITRD" | cut -f1))"
else
    echo "Initramfs absent, creation pour $KVER ..."
    dracut --force --kver "$KVER" "$INITRD"
    echo -e "${GREEN}OK${NC} Initramfs: $INITRD ($(du -h "$INITRD" | cut -f1))"
fi

# =============================================================================
# ETAPE 7 — GRUB : /etc/grub.d/07_sky1 (paquet) crée une entrée par noyau Sky1,
# la plus récente en premier (entrée 0 = défaut), disque détecté par update-grub.
# /etc/default/grub n'est pas modifié (menu, délai et GRUB_DEFAULT restent ceux de l'utilisateur)
# =============================================================================
echo ""
echo -e "${YELLOW}--- Etape 7: Configuration GRUB ---${NC}"
update-grub
if grep -q "vmlinuz-${KVER} " /boot/grub/grub.cfg; then
    echo -e "${GREEN}OK${NC} grub.cfg regenere, entree Sky1 pour ${KVER} presente"
else
    echo -e "${RED}ERREUR: aucune entree pour ${KVER} dans /boot/grub/grub.cfg${NC}"; exit 1
fi

# =============================================================================
# RESUME FINAL
# =============================================================================
echo ""
echo -e "${BLUE}=== Installation terminee ===${NC}"
echo ""
echo -e "  Kernel  : ${GREEN}${KERNEL_IMG}${NC}"
echo -e "  DTB     : ${GREEN}${DTB_PATH}${NC}"
echo -e "  Initrd  : ${GREEN}${INITRD}${NC}"
echo -e "  GRUB    : ${GREEN}/etc/grub.d/07_sky1 (réglages : /etc/default/bookworm-sky1)${NC}"
echo ""
echo -e "${YELLOW}Prochaine etape:${NC}"
echo "  reboot  (choisir l'entree « Sky1 ... » dans le menu GRUB)"
echo ""
echo -e "${CYAN}Desinstaller ce kernel:${NC}"
echo "  sudo apt remove linux-image-${KVER} linux-headers-${KVER}   (DTB et entrée GRUB retirés par les hooks)"
echo -e "${CYAN}Retirer tous les réglages Sky1:${NC}"
echo "  sudo apt purge bookworm-sky1-settings"
echo ""
echo -e "${CYAN}Post-boot:${NC}"
echo "  ${PROJECT_DIR}/diagnostics/check-system.sh"
