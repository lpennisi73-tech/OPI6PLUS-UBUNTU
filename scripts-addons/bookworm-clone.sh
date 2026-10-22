#!/bin/bash
# =============================================================================
# bookworm-clone.sh — Clonage et restauration d'un disque entier (dd + zstd), contrôlés
# BOOKWORM Sky1 Kernel Builder
#
# Usage:
#   sudo ./bookworm-clone.sh save    <disque> <dossier>   Cloner un disque dans <dossier>/<nom>/
#   sudo ./bookworm-clone.sh verify  <image>              Revérifier une image (décompression complète)
#   sudo ./bookworm-clone.sh restore <image> <disque>     Restaurer une image sur un disque
#        ./bookworm-clone.sh info    <image>              Afficher les informations d'une image
#        ./bookworm-clone.sh list                         Lister les disques
#
#   <disque> : disque entier, ex. /dev/nvme0n1 ou /dev/sda (pas une partition)
#   <image>  : dossier créé par « save » (contient disk.img.zst et clone.info)
#
# Options de save : --name <nom>  --level <1-19> (zstd, défaut 3)  --yes (pas de question sur la place)
#
# Contrôles :
#   save    : disque non monté (cloner depuis un système live), destination sur un autre disque,
#             empreinte SHA256 calculée pendant la lecture, image écrite en .partial puis renommée,
#             vérification finale par décompression complète (empreinte + taille identiques)
#   restore : image vérifiée AVANT d'écrire, disque cible non monté, ni disque du système en cours
#             ni disque de l'image, assez grand ; confirmation en tapant le nom du disque ;
#             relecture du disque après écriture (empreinte + taille identiques)
#
# Le disque du système en cours ne peut pas être cloné à chaud (fichiers modifiés pendant la copie) :
# démarrer sur une clé live (ISO Ubuntu ou BOOKWORM Sky1), copier ce script sur la clé ou le disque
# de destination, puis le lancer.
# =============================================================================

set -uo pipefail

VERSION=1.0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

die()  { echo -e "${RED}ERREUR: $*${NC}" >&2; exit 1; }
ok()   { echo -e "${GREEN}OK${NC} $*"; }
warn() { echo -e "${YELLOW}ATTENTION${NC} $*"; }
step() { echo ""; echo -e "${BLUE}${BOLD}--- $* ---${NC}"; }
human() { numfmt --to=iec-i --suffix=o "$1" 2>/dev/null || echo "$1 o"; }
usage() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

need_root() { [[ $EUID -eq 0 ]] || die "lancer en root (sudo)"; }
need_tools() {
    local t
    for t in dd zstd sfdisk lsblk blkid findmnt numfmt python3 blockdev; do
        command -v "$t" >/dev/null || die "outil manquant : $t"
    done
}

# Empreinte SHA256 + nombre d'octets de l'entrée standard, en une passe : « <sha256> <octets> »
hash_stream() {
    python3 -c '
import hashlib, sys
h = hashlib.sha256(); n = 0
f = sys.stdin.buffer
while True:
    b = f.read(4 << 20)
    if not b: break
    h.update(b); n += len(b)
print(h.hexdigest(), n)'
}

# Disque parent d'un périphérique bloc (/dev/nvme0n1p2 -> /dev/nvme0n1)
parent_disk() {
    local dev="$1" pk
    pk=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1)
    if [[ -n "$pk" ]]; then echo "/dev/$pk"; else echo "$dev"; fi
}

check_whole_disk() {    # check_whole_disk <disque>
    [[ -b "$1" ]] || die "$1 n'est pas un périphérique bloc"
    case "$(lsblk -dno TYPE "$1")" in
        disk|loop) ;;    # loop : fichier image monté (losetup), utile pour s'entraîner
        *) die "$1 n'est pas un disque entier (ex. /dev/nvme0n1, pas /dev/nvme0n1p2)" ;;
    esac
}

check_not_mounted() {    # check_not_mounted <disque> : aucune partition montée ni en swap
    local m
    m=$(lsblk -nrpo NAME,MOUNTPOINTS "$1" | awk 'NF > 1')
    if [[ -n "$m" ]]; then
        echo -e "${RED}Partitions de $1 encore montées :${NC}"
        echo "$m" | sed 's/^/  /'
        die "démonter ces partitions (ou démarrer sur une clé live si c'est le disque du système)"
    fi
}

# Disque portant la racine du système en cours (vide si la racine n'est pas un disque : live)
root_disk() {
    local src
    src=$(findmnt -no SOURCE / 2>/dev/null)
    [[ "$src" == /dev/* ]] && parent_disk "$src"
}

# Disque portant un dossier (vide si le dossier n'est pas sur un disque : tmpfs, overlay du live)
dir_disk() {
    local src
    src=$(df --output=source "$1" 2>/dev/null | tail -1)
    [[ "$src" == /dev/* ]] && parent_disk "$src"
}

disk_desc() {    # disk_desc <disque>
    lsblk -dno SIZE,MODEL,SERIAL,TRAN "$1" | sed 's/  */ /g'
}

show_disk() {    # show_disk <disque>
    echo -e "  ${CYAN}$1${NC} : $(disk_desc "$1")"
    lsblk -no NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$1" | sed 's/^/    /'
}

load_info() {    # load_info <dossier image> : charge clone.info
    local d="$1"
    [[ -f "$d/clone.info" && -f "$d/disk.img.zst" ]] || die "$d n'est pas une image complète (clone.info ou disk.img.zst absent)"
    # shellcheck disable=SC1091
    source "$d/clone.info"
    [[ -n "${SHA256_RAW:-}" && -n "${SIZE_BYTES:-}" ]] || die "$d/clone.info incomplet"
}

# Décompresse toute l'image et compare empreinte + taille à clone.info
verify_image() {    # verify_image <dossier image>
    local d="$1" res sha n
    load_info "$d"
    echo "Décompression complète de $(basename "$d")/disk.img.zst ($(human "$(stat -c %s "$d/disk.img.zst")") → $(human "$SIZE_BYTES"))..."
    res=$(zstd -dc -q "$d/disk.img.zst" | hash_stream) || { echo -e "${RED}échec de décompression (image abîmée)${NC}"; return 1; }
    read -r sha n <<< "$res"
    if [[ "$sha" == "$SHA256_RAW" && "$n" == "$SIZE_BYTES" ]]; then
        ok "image intacte : empreinte et taille identiques au disque cloné ($(human "$n"))"
        return 0
    fi
    echo -e "${RED}IMAGE NON CONFORME${NC} : attendu $SHA256_RAW / $SIZE_BYTES o, lu $sha / $n o"
    return 1
}

# =============================================================================
cmd_list() {
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MODEL,TRAN,MOUNTPOINTS
    local r; r=$(root_disk)
    echo ""
    if [[ -n "$r" ]]; then
        echo -e "Disque du système en cours : ${YELLOW}$r${NC} (ne peut être ni cloné ni restauré d'ici)"
    else
        echo "Système live (la racine n'est pas un disque) : tous les disques peuvent être clonés."
    fi
}

# =============================================================================
cmd_save() {
    local disk="" dest="" name="" level=3 yes=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --level) level="$2"; shift 2 ;;
            --yes) yes=true; shift ;;
            -*) die "option inconnue : $1" ;;
            *) if [[ -z "$disk" ]]; then disk="$1"; elif [[ -z "$dest" ]]; then dest="$1"; else die "argument en trop : $1"; fi; shift ;;
        esac
    done
    [[ -n "$disk" && -n "$dest" ]] || usage 1
    [[ "$level" =~ ^[0-9]+$ ]] && (( level >= 1 && level <= 19 )) || die "--level : 1 à 19"
    need_root; need_tools
    disk=$(realpath "$disk")
    check_whole_disk "$disk"
    check_not_mounted "$disk"
    [[ -d "$dest" ]] || die "dossier de destination absent : $dest"
    dest=$(realpath "$dest")
    local ddisk; ddisk=$(dir_disk "$dest")
    [[ -n "$ddisk" ]] || die "$dest n'est pas sur un disque (mémoire ou système live) : choisir un disque externe"
    [[ "$ddisk" != "$disk" ]] || die "la destination est sur le disque à cloner"

    local size free
    size=$(blockdev --getsize64 "$disk")
    free=$(( $(df --output=avail -B1 "$dest" | tail -1) ))
    name="${name:-clone-$(basename "$disk")-$(date +%Y%m%d-%H%M)}"
    local out="$dest/$name"
    [[ -e "$out" ]] && die "$out existe déjà (choisir --name)"

    echo -e "${BLUE}${BOLD}=== BOOKWORM clone v$VERSION — clonage ===${NC}"
    echo "Disque source :"; show_disk "$disk"
    echo -e "Destination   : ${CYAN}$out${NC} (disque $ddisk, $(human "$free") libres)"
    echo -e "Compression   : zstd niveau $level, tous les cœurs"
    if (( free < size )); then
        warn "place libre ($(human "$free")) inférieure à la taille du disque ($(human "$size"))."
        echo "  La taille de l'image dépend du contenu : l'espace vide déjà effacé se compresse presque à rien,"
        echo "  les anciennes données jamais effacées non. Si la place manque, le clonage s'arrête proprement."
        if ! $yes; then
            read -r -p "Continuer ? [o/N] " a < /dev/tty
            [[ "$a" == [oOyY]* ]] || die "annulé"
        fi
    fi

    mkdir -p "$out" || die "impossible de créer $out"
    local log="$out/clone.log"
    exec > >(tee -a "$log") 2>&1

    step "1. Informations du disque"
    sfdisk -d "$disk" > "$out/partitions.sfdisk" 2>/dev/null && ok "table de partitions : partitions.sfdisk" \
        || warn "pas de table de partitions lisible"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTUUID "$disk" > "$out/lsblk.txt"
    blkid $(lsblk -nrpo NAME "$disk") > "$out/blkid.txt" 2>/dev/null
    ok "lsblk.txt, blkid.txt"

    step "2. Lecture du disque et compression ($(human "$size"))"
    local img="$out/disk.img.zst" rc
    # Globales : le nettoyage de sortie (trap EXIT) s'exécute hors de cette fonction
    FIFO=$(mktemp -u); HASHF=$(mktemp)
    mkfifo "$FIFO"
    trap 'rm -f "${FIFO:-}" "${HASHF:-}"' EXIT
    trap 'echo; die "interrompu : image incomplète laissée en $img.partial"' INT TERM
    hash_stream < "$FIFO" > "$HASHF" &
    local hpid=$!
    local start=$SECONDS
    dd if="$disk" bs=4M iflag=fullblock status=progress \
        | tee "$FIFO" | zstd -T0 -"$level" -q -c > "$img.partial"
    rc=("${PIPESTATUS[@]}")
    wait "$hpid"
    [[ "${rc[0]}" == 0 && "${rc[1]}" == 0 && "${rc[2]}" == 0 ]] \
        || die "échec de la copie (dd=${rc[0]} tee=${rc[1]} zstd=${rc[2]}), place insuffisante ? Image incomplète : $img.partial"
    local sha n
    read -r sha n < "$HASHF"
    [[ "$n" == "$size" ]] || die "octets lus ($n) différents de la taille du disque ($size) : image incomplète laissée en $img.partial"
    sync
    mv "$img.partial" "$img"
    ok "lu $(human "$n") en $(( (SECONDS - start) / 60 )) min $(( (SECONDS - start) % 60 )) s, image $(human "$(stat -c %s "$img")")"

    cat > "$out/clone.info" << EOF
# BOOKWORM clone v$VERSION — informations de l'image (ne pas modifier)
DATE="$(date '+%Y-%m-%d %H:%M:%S')"
SOURCE_DEVICE="$disk"
SIZE_BYTES=$size
MODEL="$(lsblk -dno MODEL "$disk" | sed 's/ *$//')"
SERIAL="$(lsblk -dno SERIAL "$disk" | sed 's/ *$//')"
ZSTD_LEVEL=$level
SHA256_RAW=$sha
SHA256_ZST=$(sha256sum "$img" | cut -d' ' -f1)
HOST="$(hostname)"
EOF
    ok "clone.info (empreinte du disque : ${sha:0:16}…)"

    step "3. Vérification de l'image (décompression complète)"
    if verify_image "$out"; then
        echo "VERIFIED=\"$(date '+%Y-%m-%d %H:%M:%S')\"" >> "$out/clone.info"
        sync
        echo ""
        echo -e "${GREEN}${BOLD}=== Clonage terminé et vérifié ===${NC}"
        echo -e "  Image : ${CYAN}$out${NC}"
        echo "  Restaurer : sudo $0 restore $out <disque>"
    else
        die "l'image écrite ne correspond pas au disque lu : NE PAS l'utiliser (disque de destination défaillant ?)"
    fi
}

# =============================================================================
cmd_verify() {
    [[ $# -eq 1 ]] || usage 1
    need_tools
    local d; d=$(realpath "$1")
    cmd_info "$d"
    step "Vérification"
    if verify_image "$d"; then
        if [[ -w "$d/clone.info" ]]; then
            sed -i '/^VERIFIED=/d' "$d/clone.info"
            echo "VERIFIED=\"$(date '+%Y-%m-%d %H:%M:%S')\"" >> "$d/clone.info"
        fi
    else
        exit 1
    fi
}

# =============================================================================
cmd_info() {
    [[ $# -eq 1 ]] || usage 1
    local d; d=$(realpath "$1")
    load_info "$d"
    echo -e "${BLUE}${BOLD}=== Image $(basename "$d") ===${NC}"
    echo "  Date du clonage : $DATE"
    echo "  Disque d'origine: $SOURCE_DEVICE — ${MODEL:-?} (n° de série ${SERIAL:-?}), machine $HOST"
    echo "  Taille du disque: $(human "$SIZE_BYTES") ($SIZE_BYTES o)"
    echo "  Image           : $(human "$(stat -c %s "$d/disk.img.zst")") (zstd niveau $ZSTD_LEVEL)"
    echo "  Empreinte       : $SHA256_RAW"
    echo "  Dernière vérif. : ${VERIFIED:-jamais}"
    [[ -f "$d/lsblk.txt" ]] && { echo "  Partitions :"; sed 's/^/    /' "$d/lsblk.txt"; }
}

# =============================================================================
cmd_restore() {
    [[ $# -eq 2 ]] || usage 1
    need_root; need_tools
    local d disk
    d=$(realpath "$1"); disk=$(realpath "$2")
    load_info "$d"
    check_whole_disk "$disk"

    local rdisk idisk tsize
    rdisk=$(root_disk); idisk=$(dir_disk "$d")
    [[ "$disk" != "$rdisk" ]] || die "$disk porte le système en cours : démarrer sur une clé live pour le restaurer"
    [[ "$disk" != "$idisk" ]] || die "$disk contient l'image elle-même"
    check_not_mounted "$disk"
    tsize=$(blockdev --getsize64 "$disk")
    (( tsize >= SIZE_BYTES )) || die "$disk trop petit : $(human "$tsize") pour une image de $(human "$SIZE_BYTES")"

    echo -e "${BLUE}${BOLD}=== BOOKWORM clone v$VERSION — restauration ===${NC}"
    cmd_info "$d"
    echo ""
    echo "Disque cible :"; show_disk "$disk"
    (( tsize > SIZE_BYTES )) && warn "le disque cible est plus grand ($(human "$tsize")) : l'espace en plus restera libre après la dernière partition"

    step "1. Vérification de l'image avant écriture"
    verify_image "$d" || die "image non conforme : restauration annulée, le disque cible n'a pas été touché"

    echo ""
    echo -e "${RED}${BOLD}TOUT le contenu de $disk ($(disk_desc "$disk")) va être remplacé.${NC}"
    # Les noms nvme0n1 / nvme1n1 peuvent s'inverser d'un démarrage à l'autre : on compare les n° de série
    local want tserial; want=$(basename "$disk")
    tserial="$(lsblk -dno SERIAL "$disk" | sed 's/ *$//')"
    if [[ -n "$SERIAL" && "$tserial" != "$SERIAL" ]]; then
        echo -e "${RED}${BOLD}ATTENTION : $disk n'est PAS le disque cloné${NC}"
        echo "  image : ${MODEL:-?} (n° de série $SERIAL)"
        echo "  cible : $(disk_desc "$disk")"
        echo "  Avec deux disques, leurs noms (nvme0n1 / nvme1n1) peuvent s'inverser au démarrage."
        local what="nom"
        [[ -n "$tserial" ]] && { want="$tserial"; what="n° de série"; }
        read -r -p "Pour restaurer quand même sur ce disque, tapez son $what ($want) : " a < /dev/tty
    else
        read -r -p "Pour confirmer, tapez le nom du disque ($want) : " a < /dev/tty
    fi
    [[ "$a" == "$want" ]] || die "confirmation incorrecte : restauration annulée, rien n'a été écrit"
    check_not_mounted "$disk"    # le bureau a pu monter une partition entre-temps

    step "2. Écriture sur $disk ($(human "$SIZE_BYTES"))"
    local start=$SECONDS rc
    zstd -dc -q "$d/disk.img.zst" | dd of="$disk" bs=4M iflag=fullblock conv=fsync status=progress
    rc=("${PIPESTATUS[@]}")
    [[ "${rc[0]}" == 0 && "${rc[1]}" == 0 ]] || die "échec de l'écriture (zstd=${rc[0]} dd=${rc[1]}) : le disque est dans un état incomplet, relancer la restauration"
    sync
    ok "écrit en $(( (SECONDS - start) / 60 )) min $(( (SECONDS - start) % 60 )) s"

    step "3. Relecture du disque et comparaison"
    blockdev --flushbufs "$disk"
    echo 3 > /proc/sys/vm/drop_caches    # relire le disque lui-même, pas le cache mémoire
    local res sha n
    res=$(head -c "$SIZE_BYTES" "$disk" | hash_stream) || die "relecture impossible"
    read -r sha n <<< "$res"
    [[ "$sha" == "$SHA256_RAW" && "$n" == "$SIZE_BYTES" ]] \
        || die "le disque relu ne correspond PAS à l'image (attendu ${SHA256_RAW:0:16}…, lu ${sha:0:16}…) : disque cible défaillant ?"
    ok "disque relu identique à l'image ($(human "$n"))"
    partprobe "$disk" 2>/dev/null || blockdev --rereadpt "$disk" 2>/dev/null || true
    (( tsize > SIZE_BYTES )) && warn "disque plus grand que l'original : la table GPT de secours n'est pas à la fin ; « sudo sfdisk --relocate gpt-bak-std $disk » la replace"

    echo ""
    echo -e "${GREEN}${BOLD}=== Restauration terminée et vérifiée ===${NC}"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID "$disk" | sed 's/^/  /'
}

# =============================================================================
[[ $# -ge 1 ]] || usage 1
cmd="$1"; shift
case "$cmd" in
    save) cmd_save "$@" ;;
    restore) cmd_restore "$@" ;;
    verify) cmd_verify "$@" ;;
    info) cmd_info "$@" ;;
    list) cmd_list ;;
    -h|--help|help) usage 0 ;;
    *) echo -e "${RED}Commande inconnue : $cmd${NC}"; usage 1 ;;
esac
