#!/bin/bash
# =============================================================================
# bookworm-sky1-build.sh — Script principal BOOKWORM Sky1 Kernel Builder
# OrangePi 6 Plus / CIX CD8180 — Ubuntu 26.10 ARM64
#
# Usage: ./bookworm-sky1-build.sh [options]
#
# Options:
#   --kernel <track>      Track à compiler, fichier config/kernels/<track>.conf (défaut : 7.2.12-stable)
#   --base-config <path>  Config kernel de base (défaut: config du kernel Ubuntu stock le plus récent)
#   --build-dir <path>    Répertoire de build (défaut: /usr/src/build/sky1-kernel)
#   --jobs <n>            Nombre de jobs parallèles (défaut: nproc)
#   --skip-download       Ne pas re-télécharger si déjà présent
#   --skip-patches        Ne pas re-appliquer les patches
#   --skip-config         Ne pas re-injecter la config
#   --skip-build          Ne pas recompiler
#   --no-dbg              Ne pas construire le paquet -dbg (~16 min et 1,7 Go de moins)
#   --install             Installer automatiquement après build
#   --dry-run             Afficher ce qui serait fait sans exécuter
#   --help                Afficher cette aide
#
# Exemple:
#   ./bookworm-sky1-build.sh --install
#   ./bookworm-sky1-build.sh --kernel 7.2.12-stable --skip-download --install
#
# BOOKWORM — Kenny — OrangePi 6 Plus Sky1 Ubuntu
# =============================================================================

set -e

# =============================================================================
# COULEURS ET HELPERS
# =============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/build-$(date +%Y%m%d_%H%M%S).log"

step()    { echo -e "\n${BLUE}${BOLD}[STEP]${NC} $1" | tee -a "$LOG_FILE"; }
ok()      { echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"; }
fail()    { echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"; }
info()    { echo -e "${CYAN}→${NC} $1" | tee -a "$LOG_FILE"; }
die()     { echo -e "${RED}FATAL: $1${NC}" | tee -a "$LOG_FILE"; exit 1; }

# =============================================================================
# VALEURS PAR DÉFAUT
# =============================================================================
KERNEL_TRACK="7.2.12-stable"
BASE_CONFIG=""
BUILD_DIR="/usr/src/build/sky1-kernel"
# distcc-env.sh exporte SKY1_JOBS (jobs locaux + distants) ; --jobs reste prioritaire
JOBS=${SKY1_JOBS:-$(nproc)}
SKIP_DOWNLOAD=false
SKIP_PATCHES=false
SKIP_CONFIG=false
SKIP_BUILD=false
DO_INSTALL=false
DRY_RUN=false
NO_DBG=false

# =============================================================================
# PARSE ARGUMENTS
# =============================================================================
usage() {
    # En-tête du script seulement (de « Usage: » à la ligne de fermeture « # ==== »)
    awk 'NR > 2 && /^# =+$/ { exit } /^# Usage:/ { p = 1 } p { sub(/^# ?/, ""); print }' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel)       KERNEL_TRACK="$2"; shift 2 ;;
        --base-config)  BASE_CONFIG="$2"; shift 2 ;;
        --build-dir)    BUILD_DIR="$2"; shift 2 ;;
        --jobs)         JOBS="$2"; shift 2 ;;
        --skip-download) SKIP_DOWNLOAD=true; shift ;;
        --skip-patches)  SKIP_PATCHES=true; shift ;;
        --skip-config)   SKIP_CONFIG=true; shift ;;
        --skip-build)    SKIP_BUILD=true; shift ;;
        --no-dbg)        NO_DBG=true; shift ;;
        --install)       DO_INSTALL=true; shift ;;
        --dry-run)       DRY_RUN=true; shift ;;
        --help)          usage ;;
        *) die "Option inconnue: $1 (--help pour l'aide)" ;;
    esac
done

# =============================================================================
# CHARGER LA CONFIG
# =============================================================================
mkdir -p "$LOG_DIR"

BOARD_CONF="$SCRIPT_DIR/config/board.conf"
KERNEL_CONF="$SCRIPT_DIR/config/kernels/${KERNEL_TRACK}.conf"

[[ ! -f "$BOARD_CONF" ]]  && die "board.conf introuvable: $BOARD_CONF"
[[ ! -f "$KERNEL_CONF" ]] && die "Kernel config introuvable: $KERNEL_CONF"

# Sauver BUILD_DIR (defaut ligne 53 ou --build-dir CLI) avant que
# board.conf ne le redefinisse — le choix CLI/defaut doit gagner
BUILD_DIR_OVERRIDE="$BUILD_DIR"

source "$BOARD_CONF"
source "$KERNEL_CONF"

# Restaurer le BUILD_DIR CLI/defaut (prioritaire sur board.conf)
[[ -n "$BUILD_DIR_OVERRIDE" ]] && BUILD_DIR="$BUILD_DIR_OVERRIDE"
$NO_DBG && KERNEL_DBG_PKG="no"

# Répertoires de build
KERNEL_SRC_DIR="$BUILD_DIR/${KERNEL_TARBALL%.tar.xz}"
SKY1_DIR="$BUILD_DIR/linux-sky1"
TARBALL="$BUILD_DIR/${KERNEL_TARBALL}"

# Config de base — config du kernel Ubuntu stock (-generic) le plus récent si non spécifiée.
# On ne part pas du kernel en cours : une fois booté sur un kernel Sky1, sa config
# (déjà dérivée) servirait de base et dériverait d'un build à l'autre.
if [[ -z "$BASE_CONFIG" ]]; then
    RUNNING_KVER=$(uname -r)
    UBUNTU_CONFIG=$(ls -v /boot/config-*-generic 2>/dev/null | tail -1)
    if [[ -n "$UBUNTU_CONFIG" ]]; then
        BASE_CONFIG="$UBUNTU_CONFIG"
    elif [[ -f "/boot/config-${RUNNING_KVER}" ]]; then
        BASE_CONFIG="/boot/config-${RUNNING_KVER}"
    elif [[ -f "/proc/config.gz" ]]; then
        BASE_CONFIG="/proc/config.gz"
    else
        BASE_CONFIG=""
    fi
fi

# =============================================================================
# BANNER
# =============================================================================
echo ""
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║   BOOKWORM Sky1 Kernel Builder                 ║${NC}"
echo -e "${BLUE}${BOLD}║   OrangePi 6 Plus — CIX CD8180 — Ubuntu ARM64  ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Board        : ${CYAN}${BOARD_NAME}${NC}"
echo -e "  Kernel track : ${CYAN}${KERNEL_TRACK}${NC}"
echo -e "  Version      : ${CYAN}${KERNEL_FULL_VERSION}${KERNEL_LOCALVERSION}${NC}"
echo -e "  Sky1 track   : ${CYAN}${SKY1_TRACK}${NC}"
echo -e "  Build dir    : ${CYAN}${BUILD_DIR}${NC}"
echo -e "  Jobs         : ${CYAN}${JOBS}${NC}"
echo -e "  Paquet -dbg  : ${CYAN}${KERNEL_DBG_PKG:-yes}${NC}"
echo -e "  Base config  : ${CYAN}${BASE_CONFIG:-Sky1 default}${NC}"
[[ "$STATUS" != "stable" ]] && \
    warn "Kernel track STATUS=${STATUS} — non testé !"
echo ""

$DRY_RUN && warn "MODE DRY-RUN — aucune modification effectuée"
echo "" | tee -a "$LOG_FILE"

# =============================================================================
# VÉRIFICATIONS PRÉLIMINAIRES
# =============================================================================
step "Vérifications préliminaires"

# Outils requis (commande:paquet apt)
REQUIRED_TOOLS="git:git wget:wget patch:patch python3:python3 make:make gcc:gcc bc:bc
flex:flex bison:bison gawk:gawk cpio:cpio rsync:rsync zstd:zstd kmod:kmod
dpkg-buildpackage:dpkg-dev dh:debhelper"
MISSING_PKGS=""
for entry in $REQUIRED_TOOLS; do
    command -v "${entry%%:*}" &>/dev/null || MISSING_PKGS="$MISSING_PKGS ${entry#*:}"
done
# En-têtes de développement (fichier:paquet apt)
for entry in /usr/include/openssl/opensslv.h:libssl-dev /usr/include/libelf.h:libelf-dev \
             /usr/include/elfutils/libdw.h:libdw-dev; do
    [[ -f "${entry%%:*}" ]] || MISSING_PKGS="$MISSING_PKGS ${entry#*:}"
done
[[ -n "$MISSING_PKGS" ]] && die "Paquets manquants — sudo apt install$MISSING_PKGS"
ok "Outils de build présents"

# Architecture
[[ "$(uname -m)" != "aarch64" ]] && \
    warn "Non ARM64 — cross-compilation non supportée pour l'instant"

# Espace disque (minimum 20GB)
AVAIL=$(df -BG "$BUILD_DIR" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo 99)
[[ "${AVAIL:-99}" -lt 20 ]] && \
    warn "Espace disque faible: ${AVAIL}GB disponible (20GB recommandé)"
ok "Espace disque: ${AVAIL}GB disponible"

mkdir -p "$BUILD_DIR"
ok "Répertoire build: $BUILD_DIR"

# =============================================================================
# ÉTAPE 1 — TÉLÉCHARGEMENT SOURCES
# =============================================================================
step "Étape 1/6 — Sources kernel + Sky1 patches"

if ! $SKIP_DOWNLOAD; then

    # Cloner/mettre à jour linux-sky1 (seulement si le track en a encore besoin :
    # 7.2.12-stable prend sa série et sa config Sky1 dans ce dépôt)
    if [[ -n "${SKY1_PATCHES_LOCAL:-}" && -n "${SKY1_CONFIG_LOCAL:-}" ]]; then
        ok "Série et config Sky1 locales (${SKY1_PATCHES_LOCAL}, ${SKY1_CONFIG_LOCAL}) : linux-sky1 inutile"
    elif [[ -d "$SKY1_DIR/.git" ]]; then
        info "Mise à jour linux-sky1..."
        $DRY_RUN || (cd "$SKY1_DIR" && git pull --quiet)
        ok "linux-sky1 mis à jour"
    else
        info "Clonage linux-sky1..."
        $DRY_RUN || git clone --quiet "$SKY1_REPO" "$SKY1_DIR"
        ok "linux-sky1 cloné"
    fi

    # Télécharger le tarball kernel
    if [[ ! -f "$TARBALL" ]]; then
        info "Téléchargement ${KERNEL_TARBALL}..."
        $DRY_RUN || wget -q --show-progress -O "$TARBALL" "$KERNEL_URL" || \
            die "Échec téléchargement: $KERNEL_URL"
        ok "Kernel téléchargé: $TARBALL"
    else
        ok "Kernel déjà présent: $TARBALL"
    fi

else
    ok "Download skippé (--skip-download)"
fi

# Extraire si nécessaire (aussi avec --skip-download : l'option évite seulement le réseau,
# et un arbre supprimé pour repartir de zéro doit être recréé depuis le tarball)
if [[ ! -d "$KERNEL_SRC_DIR" ]]; then
    [[ -f "$TARBALL" ]] || die "Tarball introuvable: $TARBALL (relancer sans --skip-download)"
    info "Extraction ${KERNEL_TARBALL}..."
    $DRY_RUN || tar xf "$TARBALL" -C "$BUILD_DIR"
    ok "Kernel extrait: $KERNEL_SRC_DIR"
else
    ok "Sources déjà extraites: $KERNEL_SRC_DIR"
fi

$DRY_RUN || [[ -d "$KERNEL_SRC_DIR" ]] || die "Sources kernel introuvables: $KERNEL_SRC_DIR"

# En --dry-run, l'extraction n'a pas eu lieu : on reste dans BUILD_DIR
if [[ -d "$KERNEL_SRC_DIR" ]]; then
    cd "$KERNEL_SRC_DIR"
else
    warn "Dry-run : sources non extraites, étapes suivantes simulées sans arbre"
    cd "$BUILD_DIR"
fi

FIXES_DIR="$SCRIPT_DIR/patches/fixes"
PATCHED_MARK="$KERNEL_SRC_DIR/.sky1-patched"

# Le marqueur n'est posé qu'après les étapes 2 à 4 réussies : s'il existe, les sources
# sont déjà entièrement patchées et rien ne doit être réappliqué (les patches ne sont
# pas idempotents). Pour repatcher : supprimer le dossier des sources et relancer.
if ! $SKIP_PATCHES && [[ -f "$PATCHED_MARK" ]]; then
    ok "Sources déjà patchées ($PATCHED_MARK) : étapes 2 à 4 sautées"
    SKIP_PATCHES=true
fi

# =============================================================================
# ÉTAPE 2 — SÉRIE SKY1 (mode strict)
# =============================================================================
step "Étape 2/6 — Série Sky1 (${SKY1_TRACK})"

if ! $SKIP_PATCHES; then
    PATCHES_SRC="$SKY1_DIR/${SKY1_PATCHES_DIR}"
    # Série portée maintenue dans ce dépôt (ex. patches/sky1-7.2 : linux-sky1 n'a pas de série 7.2)
    [[ -n "${SKY1_PATCHES_LOCAL:-}" ]] && PATCHES_SRC="$SCRIPT_DIR/${SKY1_PATCHES_LOCAL}"
    [[ -d "$PATCHES_SRC" ]] || die "Patches introuvables: $PATCHES_SRC"

    info "Application de $(ls "$PATCHES_SRC"/*.patch | wc -l) patches (strict)..."
    if ! $DRY_RUN; then
        bash "$SCRIPT_DIR/patches/apply-sky1-patches.sh" "$PATCHES_SRC" 2>&1 | tee -a "$LOG_FILE"
        [[ ${PIPESTATUS[0]} -eq 0 ]] || die "Échec application de la série — voir $LOG_FILE"
    fi
    ok "Série Sky1 appliquée"
else
    ok "Patches sautés"
fi

# =============================================================================
# ÉTAPE 3 — CORRECTIFS LOCAUX (patches/fixes/9xxx-*.patch)
# =============================================================================
step "Étape 3/6 — Correctifs locaux"

if ! $SKIP_PATCHES; then
    for patch_name in $PATCHES_EXTRA; do
        PATCH_FILE="$FIXES_DIR/${patch_name}.patch"
        [[ -f "$PATCH_FILE" ]] || die "Correctif introuvable: $PATCH_FILE"
        info "Correctif: $patch_name"
        if ! $DRY_RUN; then
            patch -p1 --forward --no-backup-if-mismatch < "$PATCH_FILE" 2>&1 | tee -a "$LOG_FILE"
            [[ ${PIPESTATUS[0]} -eq 0 ]] || die "Échec du correctif $patch_name — voir $LOG_FILE"
        fi
        ok "$patch_name appliqué"
    done
fi

# =============================================================================
# ÉTAPE 4 — FIXES DTS / PILOTES (patches/fixes/*.py)
# =============================================================================
step "Étape 4/6 — Fixes DTS + pilotes"

if ! $SKIP_PATCHES; then
    for fix_name in $FIXES; do
        FIX_FILE="$FIXES_DIR/${fix_name}.py"
        [[ -f "$FIX_FILE" ]] || die "Fix introuvable: $FIX_FILE"
        info "Fix: $fix_name"
        if ! $DRY_RUN; then
            python3 "$FIX_FILE" 2>&1 | tee -a "$LOG_FILE"
            [[ ${PIPESTATUS[0]} -eq 0 ]] || die "Échec du fix $fix_name — voir $LOG_FILE"
        fi
        ok "$fix_name appliqué"
    done
    $DRY_RUN || touch "$PATCHED_MARK"
fi

# =============================================================================
# ÉTAPE 5 — CONFIGURATION KERNEL
# =============================================================================
step "Étape 5/6 — Configuration kernel"

if ! $SKIP_CONFIG; then

    SKY1_CONFIG_FILE="$SKY1_DIR/${SKY1_CONFIG}"
    # Config Sky1 de référence copiée dans ce dépôt (config/sky1/)
    [[ -n "${SKY1_CONFIG_LOCAL:-}" ]] && SKY1_CONFIG_FILE="$SCRIPT_DIR/${SKY1_CONFIG_LOCAL}"
    [[ -f "$SKY1_CONFIG_FILE" ]] || die "Config Sky1 introuvable: $SKY1_CONFIG_FILE"
    INJECT_SCRIPT="$SCRIPT_DIR/config/inject-sky1-config.sh"

    if [[ -n "$BASE_CONFIG" && -f "$BASE_CONFIG" ]]; then
        # Config personnalisée (Ubuntu) + injection Sky1
        info "Config de base: $BASE_CONFIG"
        if [[ "$BASE_CONFIG" == *.gz ]]; then
            zcat "$BASE_CONFIG" > .config
        else
            cp "$BASE_CONFIG" .config
        fi

        info "Injection options Sky1..."
        $DRY_RUN || bash "$INJECT_SCRIPT" .config "$SKY1_CONFIG_FILE" \
            2>&1 | tee -a "$LOG_FILE"
    else
        # Config Sky1 pure
        info "Utilisation config Sky1 pure: $SKY1_CONFIG_FILE"
        cp "$SKY1_CONFIG_FILE" .config
        make ARCH=arm64 ${CC:+CC="$CC"} olddefconfig 2>&1 | tee -a "$LOG_FILE"
    fi

    # Forcer les options built-in critiques
    info "Application options built-in obligatoires..."
    for opt in $FORCE_BUILTIN; do
        $DRY_RUN || scripts/config --enable "$opt"
    done

    # Désactiver les options incompatibles
    info "Désactivation options incompatibles..."
    for opt in $FORCE_DISABLED; do
        $DRY_RUN || scripts/config --disable "$opt"
    done

    # Fix modules avec symboles manquants (ChromeOS privacy screen)
    info "Fix modules incompatibles..."
    $DRY_RUN || scripts/config --disable CHROMEOS_PRIVACY_SCREEN 2>/dev/null || true

    # Spécificités config Ubuntu
    info "Adaptation config Ubuntu (clés Canonical, LOCALVERSION, debug info)..."
    if ! $DRY_RUN; then
        # Les certificats Canonical (debian/canonical-*.pem) n'existent pas hors arbre Ubuntu
        scripts/config --set-str SYSTEM_TRUSTED_KEYS ""
        scripts/config --set-str SYSTEM_REVOCATION_KEYS ""
        # Nom du kernel prévisible : <version>-sky1-custom
        scripts/config --set-str LOCALVERSION "$KERNEL_LOCALVERSION"
        scripts/config --disable LOCALVERSION_AUTO
        # BTF : seulement utile aux outils BPF CO-RE ; demande pahole et rallonge le build
        scripts/config --disable DEBUG_INFO_BTF --disable DEBUG_INFO_BTF_MODULES
        if [[ "${KERNEL_DEBUG_INFO:-yes}" == "no" ]]; then
            # Sans debug info : build plus rapide, pas de paquet -dbg (~1 Go)
            scripts/config --disable DEBUG_INFO --disable DEBUG_INFO_DWARF5 \
                --disable DEBUG_INFO_DWARF4 --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
                --enable DEBUG_INFO_NONE
        fi
    fi

    # Valeurs imposées par le track (CONFIG_OVERRIDES : une ligne OPTION=valeur, valeur y/n/m,
    # nombre ou "chaîne" sans espace). Pour un choix (HZ, PREEMPT...), option voulue à y, les autres à n.
    if [[ -n "${CONFIG_OVERRIDES:-}" ]]; then
        info "Valeurs imposées par le track (CONFIG_OVERRIDES)..."
        while IFS='=' read -r opt val; do
            [[ -n "$opt" ]] || continue
            $DRY_RUN && continue
            case "$val" in
                y) scripts/config --enable "$opt" ;;
                n) scripts/config --disable "$opt" ;;
                m) scripts/config --module "$opt" ;;
                \"*\") scripts/config --set-str "$opt" "${val//\"/}" ;;
                *) scripts/config --set-val "$opt" "$val" ;;
            esac
        done <<< "$(echo "$CONFIG_OVERRIDES" | sed 's/#.*//; s/[[:space:]]//g' | grep '=')"
    fi

    # Résolution finale des dépendances
    # Même CC que la compilation (distcc) : sinon CONFIG_CC_VERSION_TEXT change entre les deux
    $DRY_RUN || make ARCH=arm64 ${CC:+CC="$CC"} olddefconfig 2>&1 | tee -a "$LOG_FILE"

    # Contrôle : olddefconfig peut réactiver une option via un "select"
    # (ex. PCIE_CADENCE_PLAT_EP=y de la config Ubuntu -> PCIE_CADENCE_PLAT=y)
    if ! $DRY_RUN; then
        CONFIG_KO=""
        for opt in $FORCE_DISABLED; do
            grep -qE "^CONFIG_${opt}=(y|m)$" .config && CONFIG_KO="$CONFIG_KO ${opt}(réactivée)"
        done
        for opt in $FORCE_BUILTIN; do
            grep -q "^CONFIG_${opt}=y$" .config || CONFIG_KO="$CONFIG_KO ${opt}(pas =y)"
        done
        while IFS='=' read -r opt val; do
            [[ -n "$opt" ]] || continue
            if [[ "$val" == n ]]; then
                grep -qE "^CONFIG_${opt}=(y|m)$" .config && CONFIG_KO="$CONFIG_KO ${opt}(pas =n)"
            else
                grep -qxF "CONFIG_${opt}=${val}" .config || CONFIG_KO="$CONFIG_KO ${opt}(pas =${val})"
            fi
        done <<< "$(echo "${CONFIG_OVERRIDES:-}" | sed 's/#.*//; s/[[:space:]]//g' | grep '=')"
        [[ -n "$CONFIG_KO" ]] && die "Config incohérente après olddefconfig :$CONFIG_KO — chercher qui la sélectionne (make menuconfig, touche /)"
    fi
    ok "Configuration kernel finalisée"

else
    ok "Config skippée (--skip-config)"
fi

# =============================================================================
# ÉTAPE 6 — COMPILATION
# =============================================================================
step "Étape 6/6 — Compilation (j${JOBS})"

if ! $SKIP_BUILD; then

    START_TIME=$(date +%s)
    info "Démarrage compilation — $(date)"
    info "Logs: $LOG_FILE"

    if ! $DRY_RUN; then
        # bindeb-pkg : Image + modules + dtbs empaquetés en .deb dans $BUILD_DIR
        # (linux-image-<kver>, linux-headers-<kver>, linux-libc-dev — ce dernier ne doit
        # PAS être installé : il remplacerait celui d'Ubuntu)
        # Paquet -dbg sauté par le profil de build Debian du noyau (Build-Profiles du control) ;
        # la debug info reste dans le vmlinux de l'arbre de build
        DBG_PROFILE=""
        [[ "${KERNEL_DBG_PKG:-yes}" == "no" ]] && DBG_PROFILE="pkg.linux-upstream.nokerneldbg"
        # Révision du paquet : une de plus que la plus haute déjà construite ou installée.
        # Le compteur du noyau (.version) vit dans l'arbre : un arbre neuf repartirait à 1,
        # et dpkg ferait un « downgrade » d'un paquet plus récent par son numéro.
        # kver lu dans .config : sur un arbre neuf, include/config/auto.conf n'existe pas
        # encore ici (créé par bindeb-pkg), et « make kernelrelease » donne alors la version
        # sans LOCALVERSION (aucun paquet trouvé, révision repartie à 1 : vu le 2026-10-24).
        KVER="$(make -s kernelversion 2>/dev/null)$(sed -n 's/^CONFIG_LOCALVERSION="\(.*\)"$/\1/p' .config)"
        PKG_REV=0
        for v in $(dpkg-query -W -f='${Version}\n' "linux-image-${KVER}" 2>/dev/null) \
                 $(for f in "$BUILD_DIR"/linux-image-"${KVER}"_*_arm64.deb; do
                       [[ -f "$f" ]] && dpkg-deb -f "$f" Version; done); do
            r=${v##*-}
            [[ "$r" =~ ^[0-9]+$ ]] && (( r > PKG_REV )) && PKG_REV=$r
        done
        export KDEB_PKGVERSION="${KERNEL_FULL_VERSION}-$((PKG_REV + 1))"
        info "Version des paquets : $KDEB_PKGVERSION"
        DEB_BUILD_PROFILES="$DBG_PROFILE" \
            make ARCH=arm64 -j${JOBS} ${CC:+CC="$CC"} ${CXX:+CXX="$CXX"} bindeb-pkg 2>&1 | tee -a "$LOG_FILE"
        BUILD_EXIT=${PIPESTATUS[0]}
        [[ $BUILD_EXIT -ne 0 ]] && die "Compilation échouée (code $BUILD_EXIT) — voir $LOG_FILE"
    fi

    END_TIME=$(date +%s)
    DURATION=$(( (END_TIME - START_TIME) / 60 ))
    ok "Compilation terminée en ${DURATION} minutes"

    # Vérifier les artefacts
    [[ -f "arch/arm64/boot/Image" ]] && \
        ok "Kernel: arch/arm64/boot/Image ($(du -h arch/arm64/boot/Image | cut -f1))"
    [[ -f "arch/arm64/boot/dts/cix/${DTB_NAME}" ]] && \
        ok "DTB: arch/arm64/boot/dts/cix/${DTB_NAME}"
    KVER=$(make -s kernelrelease 2>/dev/null) || true   # pas d'arbre en --dry-run
    for deb in "$BUILD_DIR"/linux-image-"${KVER}"_*.deb "$BUILD_DIR"/linux-headers-"${KVER}"_*.deb; do
        [[ -f "$deb" ]] && ok "Paquet: $deb"
    done

else
    ok "Build skippé (--skip-build)"
fi

# =============================================================================
# INSTALLATION (optionnelle)
# =============================================================================
if $DO_INSTALL && ! $DRY_RUN; then
    step "Installation"
    KERNEL_FULL_VERSION="$KERNEL_FULL_VERSION" KERNEL_VERSION="$KERNEL_VERSION" SKY1_TRACK="$SKY1_TRACK" \
        bash "$SCRIPT_DIR/install/install.sh" --kernel "$KERNEL_TRACK" --kernel-dir "$KERNEL_SRC_DIR" --deb-dir "$BUILD_DIR"
fi

# =============================================================================
# RÉSUMÉ FINAL
# =============================================================================
echo ""
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║   Build terminé !                              ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Kernel  : ${GREEN}${KERNEL_SRC_DIR}/arch/arm64/boot/Image${NC}"
echo -e "  DTB     : ${GREEN}${KERNEL_SRC_DIR}/arch/arm64/boot/dts/cix/${DTB_NAME}${NC}"
echo -e "  Paquets : ${GREEN}${BUILD_DIR}/linux-{image,headers}-${KVER:-<kver>}_*.deb${NC}"
echo -e "  Log     : ${CYAN}${LOG_FILE}${NC}"
echo ""

if ! $DO_INSTALL; then
    echo -e "${YELLOW}Prochaine étape — Installation:${NC}"
    echo "  sudo ./install/install.sh --kernel ${KERNEL_TRACK} --kernel-dir ${KERNEL_SRC_DIR} --deb-dir ${BUILD_DIR}"
    echo ""
    echo -e "${YELLOW}Ou tout en une fois:${NC}"
    echo "  ./bookworm-sky1-build.sh --kernel ${KERNEL_TRACK} --skip-download --skip-patches --skip-config --install"
fi

echo -e "${YELLOW}Post-boot:${NC}"
echo "  ./diagnostics/check-system.sh"
echo ""
echo -e "${CYAN}BOOKWORM — Kernel Sky1 OrangePi 6 Plus${NC} 🚀"
