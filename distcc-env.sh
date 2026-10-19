#!/bin/bash
# =============================================================================
# distcc-env.sh — Configuration distcc pour BOOKWORM Sky1 Kernel Builder
# Usage: source distcc-env.sh && ./bookworm-sky1-build.sh --kernel 7.2.11-stable
#
# Compilation sur un serveur x86_64 avec un compilateur croisé aarch64 :
#   serveur : distccd (--allow <réseau local>) + gcc-<même version>-aarch64-linux-gnu
#   Orange Pi : sudo ./install-deps.sh --with-distcc
# CC = nom complet aarch64-linux-gnu-gcc : distcc envoie ce nom au serveur, qui lance son
# compilateur croisé (avec « gcc » seul, il lancerait son gcc x86_64).
# Le préprocesseur, l'édition de liens et l'empaquetage restent sur l'Orange Pi.
# =============================================================================

# Réglages propres à chaque installation : distcc-env.local (non versionné), par exemple
#   DISTCC_HOST="192.168.1.50"    # adresse du serveur
#   DISTCC_HOST_JOBS=16           # un job par cœur du serveur (threads si SMT)
#   DISTCC_LOCAL_JOBS=4           # Orange Pi : marge pour le préprocesseur, les liens et modpost
_distcc_local="$(dirname "${BASH_SOURCE[0]}")/distcc-env.local"
[[ -f "$_distcc_local" ]] && source "$_distcc_local"
unset _distcc_local
if [[ -z "${DISTCC_HOST:-}" ]]; then
    echo "✗ DISTCC_HOST non défini : créer distcc-env.local (voir l'en-tête de distcc-env.sh)"
    return 1 2>/dev/null || exit 1
fi
DISTCC_HOST_JOBS=${DISTCC_HOST_JOBS:-16}
DISTCC_LOCAL_JOBS=${DISTCC_LOCAL_JOBS:-4}

# lzo : compresse les fichiers préprocessés envoyés au serveur
export DISTCC_HOSTS="${DISTCC_HOST}/${DISTCC_HOST_JOBS},lzo localhost/${DISTCC_LOCAL_JOBS}"
export CC="distcc aarch64-linux-gnu-gcc"
export CXX="distcc aarch64-linux-gnu-g++"
# Lu par bookworm-sky1-build.sh (make -j) ; --jobs reste prioritaire
export SKY1_JOBS=$((DISTCC_HOST_JOBS + DISTCC_LOCAL_JOBS + 4))

# Contrôle : le compilateur du serveur doit être exactement celui de l'Orange Pi
# (le noyau mélangerait sinon des objets de deux versions de gcc)
_distcc_check() {
    local tmp local_v remote_v
    tmp=$(mktemp -d) || return
    echo 'int f(int a) { return a * 3; }' > "$tmp/t.c"
    local_v=$(aarch64-linux-gnu-gcc --version | head -1)
    if DISTCC_HOSTS="$DISTCC_HOST" DISTCC_FALLBACK=0 timeout 30 \
            distcc aarch64-linux-gnu-gcc -c "$tmp/t.c" -o "$tmp/t.o" 2>/dev/null; then
        remote_v=$(readelf -p .comment "$tmp/t.o" | sed -n 's/.*GCC: //p')
        local_v=${local_v#aarch64-linux-gnu-gcc }
        if [[ "$remote_v" == "$local_v" ]]; then
            echo "✓ serveur $DISTCC_HOST : $remote_v (identique)"
        else
            echo "⚠ serveur $DISTCC_HOST : $remote_v — Orange Pi : $local_v"
            echo "  Versions différentes : installer la même version sur le serveur avant de compiler."
        fi
    else
        echo "⚠ serveur $DISTCC_HOST injoignable ou sans aarch64-linux-gnu-gcc (port 3632, --allow)"
    fi
    rm -rf "$tmp"
}
_distcc_check
unset -f _distcc_check

echo "✓ distcc configuré:"
echo "  Hosts : $DISTCC_HOSTS"
echo "  Jobs  : $SKY1_JOBS"
echo ""
echo "Lance maintenant:"
echo "  ./bookworm-sky1-build.sh --kernel 7.2.11-stable --skip-download --install"
