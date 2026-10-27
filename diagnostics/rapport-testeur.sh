#!/bin/bash
# =============================================================================
# rapport-testeur.sh — Rapport de test Ubuntu Sky1 (Orange Pi 6 Plus)
# BOOKWORM Sky1 Kernel Builder
#
# Rassemble en une seule archive ce qu'il faut pour analyser un problème :
# système, versions, matériel, journaux du démarrage courant et du précédent,
# plantages, journaux de l'installateur. Fonctionne en live et sur un système
# installé. Rien n'est envoyé : l'archive est écrite dans le dossier personnel.
#
# Données personnelles retirées : nom de la machine, noms d'utilisateur,
# adresses MAC, IP et e-mail, numéros de série, empreintes de mots de passe,
# lignes réseau (Wi-Fi, DHCP). Le fichier de l'installateur qui contient le
# compte créé (autoinstall-user-data) n'est jamais lu. Le contenu des fichiers
# reste lisible en clair : chacun peut le relire avant de l'envoyer.
#
# Usage : sudo ./rapport-testeur.sh [-m "description du problème"]
# =============================================================================

set -u

VERSION="1.0"
NOTE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m) NOTE="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Option inconnue : $1 (voir --help)"; exit 1 ;;
    esac
done

if [[ ${EUID} -ne 0 ]]; then
    echo "Lancez ce script avec sudo : sudo $0"
    exit 1
fi

# Utilisateur de la session (dossier de sortie, son)
OWNER="${SUDO_USER:-root}"
OWNER_HOME=$(getent passwd "${OWNER}" | cut -d: -f6)
OWNER_UID=$(id -u "${OWNER}" 2>/dev/null || echo 0)
[[ -d "${OWNER_HOME}" ]] || OWNER_HOME=/root

STAMP=$(date +%Y%m%d-%H%M)
NAME="rapport-sky1-${STAMP}"
WORK=$(mktemp -d)
DIR="${WORK}/${NAME}"
mkdir -p "${DIR}"
trap 'rm -rf "${WORK}"' EXIT

# --- Anonymisation -----------------------------------------------------------
# Mots retirés : nom de la machine et comptes humains (uid >= 1000), sauf les
# noms génériques du live (ubuntu…), qui ne disent rien de la personne et dont
# le remplacement rendrait les journaux illisibles.
GENERIC="ubuntu|root|live|user|gdm|localhost|orangepi|orangepi6plus|admin|test|bookworm|sky1|linux"
SECRETS=()
add_secret() {
    local w="$1"
    [[ ${#w} -ge 3 ]] || return 0
    [[ "${w,,}" =~ ^(${GENERIC})$ ]] && return 0
    SECRETS+=("${w}")
}
add_secret "$(hostname 2>/dev/null)"
add_secret "$(hostname -s 2>/dev/null)"
while IFS=: read -r user _ uid _ gecos _; do
    [[ ${uid} -ge 1000 && ${uid} -lt 60000 ]] || continue
    add_secret "${user}"
    gecos="${gecos%%,*}"
    for part in ${gecos}; do add_secret "${part}"; done
done < /etc/passwd
# Numéros de série des disques (journaux de l'installateur, chemins /dev/disk/by-id)
while read -r sn; do
    add_secret "${sn}"
done < <(lsblk -dno SERIAL 2>/dev/null; cat /sys/class/nvme/*/serial 2>/dev/null)

SED_ARGS=()
for w in "${SECRETS[@]}"; do
    esc=$(printf '%s' "${w}" | sed 's/[][\.*^$/|]/\\&/g')
    SED_ARGS+=(-e "s/${esc}/[masqué]/gI")
done
SED_ARGS+=(
    -e 's/\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b/xx:xx:xx:xx:xx:xx/g'
    -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/x.x.x.x/g'
    -e 's/\b(fe80|f[cd][0-9a-f]{2}|[23][0-9a-f]{3})(:[0-9A-Fa-f]{0,4}){2,7}\b/[ipv6]/g'
    -e 's/\b(eui|wwn|nvme-eui)[.-](0x)?[0-9A-Fa-f]{8,}/\1-[masqué]/g'
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[e-mail]/g'
    -e 's/(SerialNumber|[Ss]erial [Nn]umber)([:=] *)[^ ,]+/\1\2[masqué]/g'
    -e 's/\$(1|2[aby]|5|6|7|y|gy)\$[^ "'"'"',]+/[empreinte]/g'
    -e 's/SSID([ =:"'"'"']+)[^ "'"'"',]+/SSID\1[masqué]/g'
)
# Lignes réseau retirées : elles contiennent des noms de réseaux et d'appareils
NET_FILTER='NetworkManager|wpa_supplicant|avahi|dhclient|dhcp|wsdd|systemd-resolved|cups-browsed|iwd\['

clean() { sed -E "${SED_ARGS[@]}"; }

# Écrit la sortie d'une commande, anonymisée, dans un fichier du rapport
run() {
    local file="$1"; shift
    {
        echo "\$ $*"
        "$@" 2>&1
        echo
    } | clean >> "${DIR}/${file}"
}
have() { command -v "$1" &>/dev/null; }

echo "Rapport de test Sky1 v${VERSION} — collecte en cours…"

# --- Description du problème ------------------------------------------------
if [[ -z "${NOTE}" && -t 0 ]]; then
    echo
    echo "Décrivez en quelques mots ce qui s'est passé et vers quelle heure"
    echo "(par exemple « écran figé vers 21h30 en lisant deux vidéos »)."
    read -r -p "Description (Entrée pour passer) : " NOTE
fi
{
    echo "Description du testeur : ${NOTE:-(aucune)}"
    echo "Rapport créé le : $(date '+%Y-%m-%d %H:%M:%S %Z')"
} | clean > "${DIR}/00-description.txt"

# --- Système ------------------------------------------------------------------
LIVE="non"
grep -qw 'boot=casper' /proc/cmdline && LIVE="oui"
{
    echo "Session live      : ${LIVE}"
    echo "Noyau             : $(uname -r) ($(uname -v))"
    echo "Carte (DT)        : $(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo 'inconnue')"
    for f in sys_vendor board_name bios_vendor bios_version bios_date; do
        printf '%-17s : %s\n' "${f}" "$(cat /sys/class/dmi/id/${f} 2>/dev/null || echo '?')"
    done
    echo "Mémoire           : $(awk '/MemTotal/ {printf "%.1f Go", $2/1048576}' /proc/meminfo)"
    echo "Cœurs             : $(nproc)"
    echo "Durée de marche   : $(uptime -p)"
    echo
    grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
    for f in /cdrom/.disk/info /cdrom/.disk/bookworm-sky1-info; do
        [[ -f "${f}" ]] && { echo "--- ${f}"; cat "${f}"; echo; }
    done
    echo
    echo "--- Ligne de commande du noyau"
    cat /proc/cmdline
} | clean > "${DIR}/01-systeme.txt"

run 01-systeme.txt dpkg-query -W -f '${db:Status-Abbrev} ${Package} ${Version}\n' \
    'linux-image-*sky1*' linux-image-sky1 bookworm-sky1-settings cix-vpu-firmware \
    gnome-shell mutter-common libgtk-4-1 libgl1-mesa-dri mesa-vulkan-drivers \
    pipewire wireplumber gstreamer1.0-libav vlc-bin kdump-tools grub-efi-arm64
run 01-systeme.txt ls -l /boot

# --- Matériel -----------------------------------------------------------------
have lspci && run 02-materiel.txt lspci -nn
have lsusb && run 02-materiel.txt lsusb
have lsusb && run 02-materiel.txt lsusb -t
run 02-materiel.txt lsblk -o NAME,MODEL,SIZE,TYPE,FSTYPE,MOUNTPOINTS
run 02-materiel.txt df -h -x tmpfs -x devtmpfs -x squashfs -x overlay
{
    echo "\$ ip -br link (sans adresses)"
    ip -br link | awk '{print $1, $2}'
    echo
    echo "--- Écrans (connecteurs DRM)"
    for c in /sys/class/drm/card*-*; do
        [[ -f "${c}/status" ]] || continue
        echo "$(basename "${c}") : $(cat "${c}/status") $(head -1 "${c}/modes" 2>/dev/null)"
    done
    echo
    echo "--- Cartes son"
    cat /proc/asound/cards 2>/dev/null
} | clean >> "${DIR}/02-materiel.txt"

# --- État des réglages Sky1 -----------------------------------------------------
{
    echo "--- GPU"
    for d in /sys/class/devfreq/*.gpu; do
        [[ -d "${d}" ]] || continue
        echo "$(basename "${d}") : gouverneur $(cat "${d}/governor"), $(($(cat "${d}/cur_freq")/1000000)) MHz" \
             "(min $(($(cat "${d}/min_freq")/1000000)), max $(($(cat "${d}/max_freq")/1000000)))"
        echo "power/control : $(cat "${d}/device/power/control" 2>/dev/null)"
    done
    for p in /sys/module/panthor/parameters/*; do
        [[ -f "${p}" ]] && echo "panthor.$(basename "${p}") = $(cat "${p}")"
    done
    ls /dev/dri 2>/dev/null | tr '\n' ' '; echo
    echo
    echo "--- Processeur"
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        echo "$(basename "${p}") : $(cat "${p}/scaling_governor"), $(($(cat "${p}/scaling_cur_freq")/1000)) MHz (max $(($(cat "${p}/scaling_max_freq")/1000)))"
    done
    echo "boost : $(cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || echo '?')"
    echo
    echo "--- Températures"
    for h in /sys/class/hwmon/hwmon*; do
        for t in "${h}"/temp*_input; do
            [[ -f "${t}" ]] || continue
            label=$(cat "${t%_input}_label" 2>/dev/null || basename "${t}")
            echo "$(cat "${h}/name") ${label} : $(($(cat "${t}")/1000)) °C"
        done
    done
    echo
    echo "--- Modules Sky1"
    lsmod | grep -E '^(panthor|linlon|trilin|armchina|amvx|snd_soc_cix|cix|i2c_cadence|rtc_rv8803|scmi)' || true
    echo
    echo "--- kdump"
    have kdump-config && kdump-config show 2>&1 | grep -E 'current state|crashkernel|kdump initrd|kexec command' || echo "kdump-tools absent"
} | clean > "${DIR}/03-reglages.txt"

if [[ ${OWNER_UID} -ge 1000 && -d /run/user/${OWNER_UID} ]] && have wpctl; then
    {
        echo "\$ wpctl status"
        sudo -u "${OWNER}" XDG_RUNTIME_DIR="/run/user/${OWNER_UID}" timeout 5 wpctl status 2>&1
    } | clean >> "${DIR}/03-reglages.txt"
fi

# --- Journaux -----------------------------------------------------------------
J="journalctl --no-pager --no-hostname -o short-precise"
run 10-demarrages.txt journalctl --no-pager --list-boots
${J} -b 0 -k 2>&1 | clean > "${DIR}/11-noyau-demarrage-actuel.txt"
${J} -b 0 -p warning 2>&1 | grep -vE "${NET_FILTER}" | clean > "${DIR}/12-avertissements-demarrage-actuel.txt"
if journalctl --no-pager -b -1 -n 1 &>/dev/null; then
    ${J} -b -1 -k 2>&1 | clean > "${DIR}/13-noyau-demarrage-precedent.txt"
    ${J} -b -1 -p warning 2>&1 | grep -vE "${NET_FILTER}" | clean > "${DIR}/14-avertissements-demarrage-precedent.txt"
    # Fin du démarrage précédent : arrêt propre ou coupure ?
    ${J} -b -1 -n 25 2>&1 | grep -vE "${NET_FILTER}" | clean > "${DIR}/15-fin-demarrage-precedent.txt"
fi
run 16-unites-en-echec.txt systemctl --failed --no-pager

# --- Plantages ----------------------------------------------------------------
{
    echo "--- /var/crash"
    ls -la /var/crash 2>/dev/null
    for d in /var/crash/*/; do
        [[ -d "${d}" ]] && ls -la "${d}"
    done
    echo
    echo "--- pstore"
    ls -la /sys/fs/pstore 2>/dev/null
} | clean > "${DIR}/20-plantages.txt"
# Traces noyau des paniques capturées par kdump et pstore (texte du noyau seulement ;
# les rapports .crash des applications ne sont pas copiés : ils contiennent l'environnement)
for f in /var/crash/*/dmesg.* /sys/fs/pstore/dmesg-*; do
    [[ -f "${f}" ]] || continue
    clean < "${f}" > "${DIR}/21-$(basename "$(dirname "${f}")")-$(basename "${f}").txt"
done

# --- Installateur ---------------------------------------------------------------
INST=/var/log/installer
if [[ -d "${INST}" ]]; then
    mkdir -p "${DIR}/30-installateur"
    for f in curtin-install.log subiquity-server-info.log ubuntu_bootstrap.log media-info casper-md5check.json; do
        [[ -f "${INST}/${f}" ]] && clean < "${INST}/${f}" > "${DIR}/30-installateur/${f}"
    done
    if [[ -f "${INST}/subiquity-server-debug.log" ]]; then
        grep -E 'ERROR|Traceback|FAIL|Exception' "${INST}/subiquity-server-debug.log" | \
            clean > "${DIR}/30-installateur/subiquity-server-erreurs.log"
    fi
fi

# --- Résumé -----------------------------------------------------------------------
count() { grep -cE "$1" "$2" 2>/dev/null || true; }
{
    echo "Résumé (rapport-testeur v${VERSION})"
    echo "Live : ${LIVE} | noyau $(uname -r) | $(grep -m1 PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo "Réglages : $(dpkg-query -W -f '${Version}' bookworm-sky1-settings 2>/dev/null || echo absent)"
    echo
    for f in 11-noyau-demarrage-actuel.txt 13-noyau-demarrage-precedent.txt; do
        [[ -f "${DIR}/${f}" ]] || continue
        echo "${f} :"
        echo "  WARNING/BUG/Oops/panique : $(count 'WARNING:|BUG:|Oops|Kernel panic|SError' "${DIR}/${f}")"
        echo "  blocages GPU (CSG/MCU)   : $(count 'CSG [0-9]+ update request timedout|Failed to stop MCU' "${DIR}/${f}")"
        echo "  récupérations GPU        : $(count 'Sky1: GPU recovered' "${DIR}/${f}")"
    done
    if [[ -f "${DIR}/15-fin-demarrage-precedent.txt" ]]; then
        if grep -qE 'Journal stopped|systemd-shutdown|Reached target.*(Power-Off|Reboot)' "${DIR}/15-fin-demarrage-precedent.txt"; then
            echo "Démarrage précédent : arrêt propre"
        else
            echo "Démarrage précédent : fin brutale (coupure, blocage ou panique)"
        fi
    fi
    echo "Unités en échec : $(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
} | clean > "${DIR}/00-resume.txt"

# --- Archive ---------------------------------------------------------------------
OUT="${OWNER_HOME}/${NAME}.tar.gz"
tar -czf "${OUT}" -C "${WORK}" "${NAME}"
chown "${OWNER}:" "${OUT}" 2>/dev/null || true

echo
cat "${DIR}/00-resume.txt"
echo
echo "Rapport écrit : ${OUT} ($(du -h "${OUT}" | cut -f1))"
if [[ "${LIVE}" == "oui" ]]; then
    echo "Session live : ce fichier disparaîtra au redémarrage, copiez-le sur une clé USB."
fi
echo "Vous pouvez l'ouvrir et le relire avant de l'envoyer (texte en clair)."
