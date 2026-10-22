#!/bin/bash
# =============================================================================
# build-iso.sh — ISO d'installation Ubuntu + noyau Sky1 (Orange Pi 6 Plus)
# BOOKWORM Sky1 Kernel Builder
#
# Distribution de base choisie par --distro : config/distros/<distro>.conf (ISO officielle,
# empreinte, étiquette, nom de sortie). L'ISO officielle est téléchargée si absente
# (liste d'empreintes signée par Ubuntu vérifiée), puis son empreinte est contrôlée.
# Remasterise l'ISO officielle (non modifiée) :
#   1. noyau Sky1, paquet bookworm-sky1-settings et firmwares VPU de CIX (cix-vpu-firmware)
#      installés dans la couche squashfs
#      `minimal` (base du système live ET du système installé) ;
#   2. ces paquets ajoutés à la base dpkg de chaque couche supérieure (chaque
#      couche a sa copie de /var/lib/dpkg/status, qui masquerait celle de minimal) ;
#   3. initrd casper refait pour le noyau Sky1 (initramfs-tools de la couche live) ;
#   4. entrée GRUB Sky1 par défaut (devicetree + acpi=off), entrée générique gardée ;
#   5. ISO refaite par xorriso avec le démarrage EFI de l'ISO d'origine.
# Sur le disque installé, /etc/grub.d/07_sky1 (paquet de réglages) crée l'entrée Sky1.
# Dépendances : sudo ./install-deps.sh --with-iso
#
# Usage: sudo ./build-iso.sh [--distro <distro>] [--iso <ubuntu.iso>] [--kernel-deb <linux-image.deb>]
#                            [--out <sortie.iso>] [--work <dir>] [--keep-work] [--resume]
#   --distro      Distribution de base, fichier config/distros/<distro>.conf (défaut : ubuntu-26.10)
#   --list-distros  Lister les distributions disponibles
#   --iso         ISO officielle à utiliser telle quelle (défaut : celle de la distribution,
#                 dans /usr/src/build/sky1-iso/, téléchargée si absente)
#   --kernel-deb  Paquet noyau (défaut : linux-image-*-sky1-custom le plus récent de BUILD_DIR)
#   --out         ISO produite (défaut : à côté de l'ISO officielle, datée)
#   --work        Dossier de travail, ~30 Go (défaut : <dossier de l'ISO>/work)
#   --keep-work   Garder le dossier de travail
#   --resume      Reprendre à l'étape 7 (métadonnées + ISO) avec un dossier de travail
#                 dont les étapes 1-6 sont finies (après un échec en fin de script)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config/board.conf"

ISO_DIR=/usr/src/build/sky1-iso
DISTRO_DIR="$PROJECT_DIR/config/distros"
DISTRO="ubuntu-26.10"
SRC_ISO=""
KERNEL_DEB=""
OUT_ISO=""
WORK=""
KEEP_WORK=false
RESUME=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --distro) DISTRO="$2"; shift 2 ;;
        --list-distros)
            for f in "$DISTRO_DIR"/*.conf; do
                ( source "$f"; printf '  %-18s %-22s %-10s %s\n' "$(basename "$f" .conf)" "$DISTRO_NAME" "$STATUS" "$DISTRO_SUPPORT" )
            done
            exit 0 ;;
        --iso) SRC_ISO="$2"; shift 2 ;;
        --kernel-deb) KERNEL_DEB="$2"; shift 2 ;;
        --out) OUT_ISO="$2"; shift 2 ;;
        --work) WORK="$2"; shift 2 ;;
        --keep-work) KEEP_WORK=true; shift ;;
        --resume) RESUME=true; shift ;;
        --help|-h) awk 'NR > 2 && /^# =+$/ { exit } NR > 2 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
        *) echo -e "${RED}Option inconnue: $1${NC}" >&2; exit 1 ;;
    esac
done

die() { echo -e "${RED}ERREUR: $*${NC}" >&2; exit 1; }
step() { echo ""; echo -e "${YELLOW}--- $* ---${NC}"; }

[[ $EUID -eq 0 ]] || die "lancer en root (sudo) : chroot, montages"
for t in xorriso unsquashfs mksquashfs python3 md5sum lsinitrd sha256sum; do
    command -v "$t" >/dev/null || die "$t manquant (sudo ./install-deps.sh --with-iso)"
done

# --- Distribution de base ---
DISTRO_CONF="$DISTRO_DIR/$DISTRO.conf"
[[ -f "$DISTRO_CONF" ]] || die "distribution inconnue : $DISTRO (voir --list-distros)"
source "$DISTRO_CONF"
for v in DISTRO_NAME ISO_FILE ISO_URL ISO_SHA256 OUT_PREFIX VOLUME_ID GRUB_ANCHOR STATUS; do
    [[ -n "${!v:-}" ]] || die "$DISTRO_CONF : $v manquant"
done
(( ${#VOLUME_ID} <= 32 )) || die "$DISTRO_CONF : VOLUME_ID dépasse 32 caractères"
[[ "$GRUB_ANCHOR" == *'" {' ]] || die "$DISTRO_CONF : GRUB_ANCHOR doit finir par '\" {'"

# Télécharge l'ISO officielle si absente : liste d'empreintes signée par Ubuntu (clé cdimage),
# puis ISO contrôlée contre cette liste ; le fichier final n'apparaît qu'une fois vérifié
fetch_iso() {    # fetch_iso <destination>
    local dest="$1" keyring=/usr/share/keyrings/ubuntu-cdimage-keyring.gpg tmp
    for t in curl gpgv; do command -v "$t" >/dev/null || die "$t manquant pour télécharger l'ISO"; done
    [[ -f "$keyring" ]] || die "$keyring absent (paquet ubuntu-keyring)"
    tmp=$(mktemp -d)
    echo -e "${YELLOW}Téléchargement${NC} de la liste d'empreintes signée : $ISO_URL"
    curl -fsSL -o "$tmp/SHA256SUMS" "$ISO_URL/SHA256SUMS" && curl -fsSL -o "$tmp/SHA256SUMS.gpg" "$ISO_URL/SHA256SUMS.gpg" \
        || { rm -rf "$tmp"; die "liste d'empreintes introuvable sur $ISO_URL"; }
    gpgv --keyring "$keyring" "$tmp/SHA256SUMS.gpg" "$tmp/SHA256SUMS" 2>/dev/null \
        || { rm -rf "$tmp"; die "signature de SHA256SUMS invalide : téléchargement refusé"; }
    grep -E "^$ISO_SHA256 [ *]$ISO_FILE\$" "$tmp/SHA256SUMS" >/dev/null \
        || { rm -rf "$tmp"; die "l'empreinte figée de $ISO_FILE ne correspond pas à la liste signée d'Ubuntu"; }
    rm -rf "$tmp"
    echo -e "${YELLOW}Téléchargement${NC} de $ISO_FILE (plusieurs Go)…"
    mkdir -p "$(dirname "$dest")"
    curl -fL --retry 3 -o "$dest.partial" "$ISO_URL/$ISO_FILE" || { rm -f "$dest.partial"; die "téléchargement de $ISO_FILE"; }
    [[ "$(sha256sum < "$dest.partial" | cut -d' ' -f1)" == "$ISO_SHA256" ]] \
        || { rm -f "$dest.partial"; die "empreinte de $ISO_FILE téléchargée incorrecte"; }
    mv "$dest.partial" "$dest"
    echo -e "${GREEN}OK${NC} $ISO_FILE téléchargée, signature et empreinte vérifiées"
}

if [[ -z "$SRC_ISO" ]]; then
    SRC_ISO="$ISO_DIR/$ISO_FILE"
    [[ -f "$SRC_ISO" ]] || fetch_iso "$SRC_ISO"
    echo -e "${YELLOW}Contrôle${NC} de l'empreinte de $ISO_FILE…"
    [[ "$(sha256sum < "$SRC_ISO" | cut -d' ' -f1)" == "$ISO_SHA256" ]] \
        || die "$SRC_ISO ne correspond pas à l'ISO officielle de $DISTRO_NAME (empreinte différente : la supprimer pour la retélécharger)"
else
    [[ -f "$SRC_ISO" ]] || die "ISO officielle introuvable : $SRC_ISO"
    [[ "$(sha256sum < "$SRC_ISO" | cut -d' ' -f1)" == "$ISO_SHA256" ]] \
        || echo -e "${YELLOW}ATTENTION${NC} : $SRC_ISO n'est pas l'ISO officielle attendue pour $DISTRO_NAME (empreinte différente)"
fi
SRC_ISO="$(realpath "$SRC_ISO")"
WORK="$(realpath -m "${WORK:-$(dirname "$SRC_ISO")/work}")"

if [[ -z "$KERNEL_DEB" ]]; then
    KERNEL_DEB=$(ls -t "$BUILD_DIR"/linux-image-*-sky1-custom_*_arm64.deb 2>/dev/null | grep -v -- '-dbg_' | head -1 || true)
fi
[[ -f "$KERNEL_DEB" ]] || die "paquet noyau introuvable (--kernel-deb, ou compiler : ./bookworm-sky1-build.sh)"
KERNEL_DEB="$(realpath "$KERNEL_DEB")"
KPKG=$(dpkg-deb -f "$KERNEL_DEB" Package)
KVER="${KPKG#linux-image-}"
KPKG_VERSION=$(dpkg-deb -f "$KERNEL_DEB" Version)
[[ "$KVER" == *-sky1-* ]] || die "$KERNEL_DEB n'est pas un noyau Sky1 ($KPKG)"
DATE=$(date +%Y%m%d)
OUT_ISO="$(realpath -m "${OUT_ISO:-$ISO_DIR/${OUT_PREFIX}-${DATE}.iso}")"

FREE_GB=$(( $(df --output=avail -k "$(dirname "$WORK")" | tail -1) / 1024 / 1024 ))
(( FREE_GB >= 35 )) || die "place insuffisante sous $(dirname "$WORK") : ${FREE_GB} Go libres, 35 Go nécessaires"

echo -e "${BLUE}=== BOOKWORM Sky1 — ISO d'installation ===${NC}"
echo -e "Distribution   : ${CYAN}$DISTRO_NAME ($DISTRO, $STATUS)${NC}"
echo -e "ISO officielle : ${CYAN}$SRC_ISO${NC}"
echo -e "Noyau          : ${CYAN}$KVER ($KPKG_VERSION)${NC}"
echo -e "Travail        : ${CYAN}$WORK${NC}"
echo -e "Sortie         : ${CYAN}$OUT_ISO${NC}"

# --- Montages : suivis et démontés à la sortie, même en cas d'erreur ---
MOUNTS=()
track_mount() {    # track_mount <options mount...> <point de montage>
    mount "$@"
    MOUNTS+=("${@: -1}")
}
release_mounts() {    # release_mounts [<préfixe>] : démonte (ordre inverse) ce qui est sous <préfixe>
    local prefix="${1:-/}" i m keep=()
    for (( i=${#MOUNTS[@]}-1; i>=0; i-- )); do
        m="${MOUNTS[i]}"
        if [[ "$m" == "$prefix"* ]]; then
            mountpoint -q "$m" && { umount "$m" 2>/dev/null || umount -l "$m"; }
        fi
    done
    for m in "${MOUNTS[@]}"; do [[ "$m" == "$prefix"* ]] || keep+=("$m"); done
    MOUNTS=("${keep[@]}")
}
# grep sans -q : avec pipefail, « grep -q » coupe le tuyau au premier résultat et le SIGPIPE de
# l'autre commande ferait échouer le test (code 141) même quand il trouve
mounts_under() { findmnt -rn -o TARGET | grep "^$1\(/\|$\)" >/dev/null; }
safe_rm_work() {
    mounts_under "$WORK" && die "montage encore actif sous $WORK : rien n'est supprimé"
    rm -rf "$WORK"
}
trap 'release_mounts /' EXIT

chroot_enter() {    # chroot_enter <racine> : /dev, /proc, /sys, /run + pas de démarrage de services
    local r="$1"
    track_mount --bind /dev "$r/dev"
    track_mount --bind /dev/pts "$r/dev/pts"
    track_mount -t proc proc "$r/proc"
    track_mount -t sysfs sysfs "$r/sys"
    track_mount -t tmpfs tmpfs "$r/run"
    [[ -e "$r/usr/sbin/policy-rc.d" ]] && die "$r/usr/sbin/policy-rc.d existe déjà"
    printf '#!/bin/sh\nexit 101\n' > "$r/usr/sbin/policy-rc.d"
    chmod 755 "$r/usr/sbin/policy-rc.d"
}
chroot_leave() {    # chroot_leave <racine>
    rm -f "$1/usr/sbin/policy-rc.d"
    release_mounts "$1"
}
in_chroot() {    # in_chroot <racine> <commande...>
    local r="$1"; shift
    chroot "$r" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 \
        DEBIAN_FRONTEND=noninteractive FLASH_KERNEL_SKIP=1 "$@"
}
squash() {    # squash <dossier> <fichier.squashfs> : même compression que l'ISO officielle
    rm -f "$2"
    mksquashfs "$1" "$2" -noappend -comp xz -b 131072 -xattrs -quiet
}

CASPER="$WORK/iso/casper"
STATE="$WORK/state.env"
if $RESUME; then
    [[ -f "$STATE" ]] || die "--resume : $STATE absent (étapes 1-6 pas terminées)"
    source "$STATE"
    [[ "${STATE_DISTRO:-}" == "$DISTRO" ]] || die "--resume : le dossier de travail vient de ${STATE_DISTRO:-?}, pas de $DISTRO"
    KVER="${KPKG#linux-image-}"
    echo -e "${YELLOW}Reprise à l'étape 7 : $KPKG $KPKG_VERSION, réglages $SETTINGS_VERSION${NC}"
else
# =============================================================================
step "1. Extraction de l'ISO officielle"
[[ -e "$WORK" ]] && safe_rm_work
mkdir -p "$WORK"/{layers,debs,ovl}
xorriso -osirrox on -indev "$SRC_ISO" -extract / "$WORK/iso" > "$WORK/xorriso-extract.log" 2>&1 \
    || { tail -20 "$WORK/xorriso-extract.log"; die "extraction de l'ISO"; }
chmod -R u+w "$WORK/iso"
[[ -f "$CASPER/minimal.squashfs" && -f "$WORK/iso/boot/grub/grub.cfg" ]] || die "structure d'ISO inattendue"
echo -e "${GREEN}OK${NC} $(du -sh "$WORK/iso" | cut -f1) extraits"

# =============================================================================
step "2. Paquets : bookworm-sky1-settings + cix-vpu-firmware + $KPKG"
"$PROJECT_DIR/packaging/build-settings-deb.sh" --out "$WORK/debs"
SETTINGS_DEB=$(ls "$WORK"/debs/bookworm-sky1-settings_*_arm64.deb)
FW_DEB=$("$PROJECT_DIR/packaging/fetch-cix-firmware.sh")
cp "$KERNEL_DEB" "$WORK/debs/"

# =============================================================================
step "3. Couche minimal : installation du noyau Sky1 et des réglages"
MIN="$WORK/layers/minimal"
unsquashfs -q -d "$MIN" "$CASPER/minimal.squashfs"
SIZE_BEFORE=$(du -sb "$MIN" | cut -f1)
chroot_enter "$MIN"
mkdir -p "$MIN/tmp/sky1-debs"
cp "$SETTINGS_DEB" "$FW_DEB" "$KERNEL_DEB" "$MIN/tmp/sky1-debs/"
# Réglages d'abord : hook DTB et config dracut servent à l'installation du noyau
in_chroot "$MIN" dpkg -i --force-confold "/tmp/sky1-debs/$(basename "$SETTINGS_DEB")"
in_chroot "$MIN" dpkg -i "/tmp/sky1-debs/$(basename "$FW_DEB")"
in_chroot "$MIN" dpkg -i "/tmp/sky1-debs/$(basename "$KERNEL_DEB")"
rm -rf "$MIN/tmp/sky1-debs"
chroot_leave "$MIN"
# Règles udev Sky1 dans l'initramfs du système installé (sinon course au démarrage sur le port USB-C 0).
# lsinitrd de la machine de build : la couche minimal n'a pas cpio ni skipcpio pour le faire elle-même
lsinitrd "$MIN/boot/initrd.img-$KVER" 2>/dev/null | grep 'usr/lib/udev/rules.d/90-sky1-typec-usb-pm.rules' >/dev/null \
    || die "règles udev Sky1 absentes de l'initramfs de la couche minimal (config dracut du paquet ?)"
for f in "boot/vmlinuz-$KVER" "boot/initrd.img-$KVER" "boot/dtb/${DTB_NAME%.dtb}-$KVER.dtb" etc/grub.d/07_sky1 \
         usr/lib/firmware/h264dec.fwb usr/share/doc/cix-vpu-firmware/copyright; do
    [[ -f "$MIN/$f" ]] || die "$f absent de la couche minimal après installation"
done
SIZE_DELTA=$(( $(du -sb "$MIN" | cut -f1) - SIZE_BEFORE ))
echo -e "${GREEN}OK${NC} noyau, initramfs, DTB et réglages dans minimal (+$(( SIZE_DELTA / 1024 / 1024 )) Mo)"

# Entrées dpkg de nos paquets, à reporter dans les couches supérieures
STATUS_ADD="$WORK/sky1-status.txt"
python3 - "$MIN/var/lib/dpkg/status" "$STATUS_ADD" "$KPKG" bookworm-sky1-settings cix-vpu-firmware << 'EOF'
import sys
src, out, *names = sys.argv[1:]
stanzas = open(src, encoding='utf-8').read().strip('\n').split('\n\n')
keep = [s for s in stanzas if s.split('\n', 1)[0].split(': ', 1)[1] in names]
assert len(keep) == len(names), f"entrées dpkg trouvées : {len(keep)} sur {len(names)}"
open(out, 'w', encoding='utf-8').write('\n\n'.join(keep) + '\n')
EOF
SETTINGS_VERSION=$(dpkg-deb -f "$SETTINGS_DEB" Version)
FW_VERSION=$(dpkg-deb -f "$FW_DEB" Version)

# =============================================================================
step "4. Couches supérieures : base dpkg"
merge_status() {    # merge_status <status de la couche>
    python3 - "$1" "$STATUS_ADD" << 'EOF'
import sys
dst, add = sys.argv[1:]
name = lambda s: s.split('\n', 1)[0].split(': ', 1)[1]
new = open(add, encoding='utf-8').read().strip('\n').split('\n\n')
names = {name(s) for s in new}
old = [s for s in open(dst, encoding='utf-8').read().strip('\n').split('\n\n') if name(s) not in names]
open(dst, 'w', encoding='utf-8').write('\n\n'.join(old + new) + '\n')
EOF
}
for sq in "$CASPER"/*.squashfs; do
    layer=$(basename "$sq" .squashfs)
    [[ "$layer" == minimal ]] && continue
    dir="$WORK/layers/$layer"
    unsquashfs -q -d "$dir" "$sq"
    if [[ "$layer" == minimal.standard.live ]]; then
        # Le noyau Sky1 n'a pas de module ZFS : à la fermeture, l'installateur lance « zpool export -a »,
        # qui échoue sans /dev/zfs et affiche un rapport de plantage (installation pourtant terminée).
        # /usr/local/sbin passe avant /usr/sbin dans le PATH de l'installateur ; couche live seulement,
        # le système installé n'est pas concerné.
        mkdir -p "$dir/usr/local/sbin"
        cat > "$dir/usr/local/sbin/zpool" << 'ZPOOL'
#!/bin/sh
# BOOKWORM Sky1 (système live) : sans module ZFS (noyau Sky1), aucun pool n'existe et
# « zpool export » n'a rien à faire ; tout le reste passe au vrai zpool.
if [ ! -e /dev/zfs ] && [ "$1" = export ]; then
    exit 0
fi
exec /usr/sbin/zpool "$@"
ZPOOL
        chmod 755 "$dir/usr/local/sbin/zpool"
    fi
    if [[ -f "$dir/var/lib/dpkg/status" ]]; then
        merge_status "$dir/var/lib/dpkg/status"
        # standard et live servent encore à l'initrd (étape 5)
        if [[ "$layer" != minimal.standard && "$layer" != minimal.standard.live ]]; then
            squash "$dir" "$sq"
            rm -rf "$dir"
        fi
        echo -e "${GREEN}OK${NC} $layer"
    else
        rm -rf "$dir"
        echo -e "${GREEN}OK${NC} $layer (sans base dpkg, inchangée)"
    fi
done

# =============================================================================
step "5. Initrd du système live (casper) pour $KVER"
L="$WORK/layers"
OVL="$WORK/ovl/root"
mkdir -p "$WORK/ovl/upper" "$WORK/ovl/work" "$OVL"
track_mount -t overlay overlay \
    -o "lowerdir=$L/minimal.standard.live:$L/minimal.standard:$L/minimal,upperdir=$WORK/ovl/upper,workdir=$WORK/ovl/work" "$OVL"
chroot_enter "$OVL"
in_chroot "$OVL" mkinitramfs -o /tmp/initrd-sky1 "$KVER"
in_chroot "$OVL" unmkinitramfs /tmp/initrd-sky1 /tmp/initrd-sky1.x
find "$OVL/tmp/initrd-sky1.x" -path '*/usr/lib/udev/rules.d/90-sky1-typec-usb-pm.rules' | grep . >/dev/null \
    || die "règles udev Sky1 absentes de l'initrd casper (hook initramfs-tools du paquet ?)"
UUID_FILE=$(find "$OVL/tmp/initrd-sky1.x" -path '*/conf/uuid.conf' | head -1)
[[ -n "$UUID_FILE" ]] || die "conf/uuid.conf absent de l'initrd casper (hook casper ?)"
CASPER_UUID=$(cat "$UUID_FILE")
install -m 644 "$OVL/tmp/initrd-sky1" "$CASPER/initrd-sky1"
chroot_leave "$OVL"
release_mounts "$OVL"
mounts_under "$WORK/ovl" && die "overlay encore monté"
rm -rf "$WORK/ovl"
echo "$CASPER_UUID" > "$WORK/iso/.disk/casper-uuid-sky1"
echo -e "${GREEN}OK${NC} casper/initrd-sky1 ($(du -h "$CASPER/initrd-sky1" | cut -f1)), uuid $CASPER_UUID"

# =============================================================================
step "6. Recompression des couches minimal, standard, live (xz, plusieurs minutes)"
for layer in minimal minimal.standard minimal.standard.live; do
    squash "$L/$layer" "$CASPER/$layer.squashfs"
    echo -e "${GREEN}OK${NC} $layer.squashfs ($(du -h "$CASPER/$layer.squashfs" | cut -f1))"
done
install -m 644 "$MIN/boot/vmlinuz-$KVER" "$CASPER/vmlinuz-sky1"
install -m 644 "$MIN/boot/dtb/${DTB_NAME%.dtb}-$KVER.dtb" "$CASPER/$DTB_NAME"
rm -rf "$L"
printf 'STATE_DISTRO=%q\nKPKG=%q\nKPKG_VERSION=%q\nSETTINGS_VERSION=%q\nFW_VERSION=%q\nSIZE_DELTA=%q\n' \
    "$DISTRO" "$KPKG" "$KPKG_VERSION" "$SETTINGS_VERSION" "$FW_VERSION" "$SIZE_DELTA" > "$STATE"
fi

# =============================================================================
step "7. Métadonnées de l'ISO (tailles, manifestes, GRUB, md5sum)"
# Toujours repartir des fichiers de l'ISO officielle : étape rejouable (--resume)
META=(casper/minimal.size casper/install-sources.yaml casper/minimal.manifest boot/grub/grub.cfg .disk/info md5sum.txt)
for f in "$CASPER"/*.manifest.full; do META+=("casper/$(basename "$f")"); done
EXTRACT=()
for f in "${META[@]}"; do EXTRACT+=(-extract "/$f" "$WORK/iso/$f"); done
xorriso -osirrox on -indev "$SRC_ISO" "${EXTRACT[@]}" > "$WORK/xorriso-meta.log" 2>&1 \
    || { tail -20 "$WORK/xorriso-meta.log"; die "relecture des métadonnées de l'ISO officielle"; }
for f in "${META[@]}"; do chmod u+w "$WORK/iso/$f"; done
python3 - "$WORK/iso" "$SIZE_DELTA" "$KPKG=$KPKG_VERSION" "bookworm-sky1-settings=$SETTINGS_VERSION" \
    "cix-vpu-firmware=$FW_VERSION" << 'EOF'
import sys, glob, os, re
iso, delta = sys.argv[1], int(sys.argv[2])
casper = os.path.join(iso, 'casper')
pkgs = dict(a.split('=', 1) for a in sys.argv[3:])
# Taille décompressée de la couche minimal (chaque .size ne compte que sa couche) et
# tailles des sources de l'installateur (cumulées, servent à estimer l'espace disque)
f = os.path.join(casper, 'minimal.size')
n = int(open(f).read().strip())
open(f, 'w').write(f'{n + delta}\n')
y = os.path.join(casper, 'install-sources.yaml')
txt = re.sub(r'(?m)^(\s*size: )(\d+)$', lambda m: f'{m[1]}{int(m[2]) + delta}', open(y).read())
open(y, 'w').write(txt)
# Manifestes : minimal.manifest = ajouts par rapport à rien (« +paquet\tversion ») ;
# *.manifest.full = liste complète de chaque couche
def add_lines(path, prefix):
    lines = open(path).read().splitlines()
    head = [l for l in lines if l.startswith(('---', '+++'))]
    body = [l for l in lines if not l.startswith(('---', '+++'))]
    body = [l for l in body if l.lstrip('+').split('\t')[0] not in pkgs]
    body += [f'{prefix}{p}\t{v}' for p, v in pkgs.items()]
    body.sort(key=lambda l: l.lstrip('+'))
    open(path, 'w').write('\n'.join(head + body) + '\n')
add_lines(os.path.join(casper, 'minimal.manifest'), '+')
for f in glob.glob(casper + '/*.manifest.full'):
    add_lines(f, '')
EOF

GRUB_CFG="$WORK/iso/boot/grub/grub.cfg"
python3 - "$GRUB_CFG" "$KVER" "$BOARD_NAME" "$DTB_NAME" "$KERNEL_CMDLINE" "$GRUB_ANCHOR" << 'EOF'
import sys
cfg, kver, board, dtb, cmdline, anchor = sys.argv[1:]
txt = open(cfg).read()
assert txt.count(anchor) == 1, f'entrée GRUB « {anchor} » introuvable (GRUB_ANCHOR de la distribution)'
entry = f'''menuentry "Essayer ou installer Ubuntu - {board} (noyau Sky1 {kver})" {{
    set gfxpayload=keep
    linux  /casper/vmlinuz-sky1 {cmdline} --- quiet splash
    initrd /casper/initrd-sky1
    devicetree /casper/{dtb}
}}
'''
generic = anchor[:-len('" {')] + ' (noyau Ubuntu generique, ACPI, sans acceleration graphique)" {'
txt = txt.replace(anchor, entry + generic)
open(cfg, 'w').write(txt)
EOF
# .disk/info reste celui de l'ISO officielle : l'installateur (ProductService d'ubuntu-desktop-bootstrap)
# en lit le nom, la version et le nom de code entre guillemets ; une autre ligne le bloque sans message
# avant sa première page. Notre identification va dans un fichier à part.
printf '%s\n' "BOOKWORM Sky1 - ${BOARD_NAME} (non officielle) - $(head -1 "$WORK/iso/.disk/info")" \
    "Noyau : $KVER ($KPKG_VERSION), réglages : bookworm-sky1-settings $SETTINGS_VERSION, firmwares VPU : cix-vpu-firmware $FW_VERSION, construite le $DATE" \
    > "$WORK/iso/.disk/bookworm-sky1-info"

# md5sum.txt (vérifié par casper-md5check dans le système live) : mêmes fichiers que l'original + les nôtres
(
    cd "$WORK/iso"
    { sed 's/^[0-9a-f]*  //' md5sum.txt
      printf '%s\n' ./casper/vmlinuz-sky1 ./casper/initrd-sky1 "./casper/$DTB_NAME" ./.disk/casper-uuid-sky1 \
          ./.disk/bookworm-sky1-info
    } | sort -u | while read -r f; do if [[ -f "$f" ]]; then echo "$f"; fi; done \
      | xargs -d '\n' md5sum > md5sum.txt.new
    mv md5sum.txt.new md5sum.txt
)
echo -e "${GREEN}OK${NC} grub.cfg (entrée Sky1 par défaut), .disk/bookworm-sky1-info, md5sum.txt ($(wc -l < "$WORK/iso/md5sum.txt") fichiers)"

# =============================================================================
step "8. Création de l'ISO (démarrage EFI repris de l'ISO officielle)"
# Options de démarrage de l'original (partition EFI ajoutée, GPT, catalogue El Torito),
# relues par xorriso ; le volume et la date changent
BOOT_OPTS=$(xorriso -indev "$SRC_ISO" -report_el_torito as_mkisofs 2>/dev/null \
    | grep -vE "^-V |^--modification-date=")
eval "BOOT_ARGS=( $BOOT_OPTS )"
rm -f "$OUT_ISO"
xorriso -as mkisofs -r -iso-level 3 -V "$VOLUME_ID" "${BOOT_ARGS[@]}" \
    -o "$OUT_ISO" "$WORK/iso" > "$WORK/xorriso-mkisofs.log" 2>&1 \
    || { tail -20 "$WORK/xorriso-mkisofs.log"; rm -f "$OUT_ISO"; die "création de l'ISO"; }
grep -E 'WARNING|SORRY' "$WORK/xorriso-mkisofs.log" || true
(cd "$(dirname "$OUT_ISO")" && sha256sum "$(basename "$OUT_ISO")" > "$(basename "$OUT_ISO").sha256")

$KEEP_WORK || safe_rm_work

echo ""
echo -e "${BLUE}=== ISO prête ===${NC}"
echo -e "  ${GREEN}$OUT_ISO${NC} ($(du -h "$OUT_ISO" | cut -f1))"
echo -e "  SHA256 : $(cut -d' ' -f1 "$OUT_ISO.sha256")"
echo ""
echo "Clé USB (≥ 8 Go, TOUT son contenu est effacé) : vérifier le périphérique avec lsblk, puis"
echo "  sudo dd if=$OUT_ISO of=/dev/sdX bs=4M conv=fsync status=progress"
