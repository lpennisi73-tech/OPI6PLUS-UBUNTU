# BOOKWORM Sky1 Kernel Builder

🇫🇷 Français | 🇬🇧 [English](README.en.md)

### OrangePi 6 Plus — CIX CD8180 — Ubuntu 26.10 ARM64

[![Kernel](https://img.shields.io/badge/Kernel-7.2.11--sky1-blue)](https://www.kernel.org)
[![GPU](https://img.shields.io/badge/GPU-Mali--G720%20Panthor-green)](https://github.com/visorcraft/orange-pi-6-plus-gpu)
[![Board](https://img.shields.io/badge/Board-OrangePi%206%20Plus-orange)](http://www.orangepi.org)
[![OS](https://img.shields.io/badge/OS-Ubuntu%2026.10%20%7C%2026.04.1%20LTS-E95420)](https://ubuntu.com)
[![Status](https://img.shields.io/badge/Status-Valid%C3%A9%20✓-brightgreen)]()

> Compilez et installez un noyau Linux 7.2.11 complet pour l'OrangePi 6 Plus sous Ubuntu 26.10 :
> GPU Mali-G720, double écran DP + HDMI avec son, USB-C 10 Gb/s, NPU, VPU, boost CPU 2,6 GHz.
> Né sous Gentoo (avril 2026), porté sur Ubuntu et sur Linux 7.2 par BOOKWORM/Kenny en octobre 2026.

---

## 🎯 Résultat

```
panthor 15000000.gpu: [drm] Using ACE-Lite bus coherency (Sky1)
[drm] Initialized panthor 1.8.0 for 15000000.gpu on minor 1
trilin-dptx-cix 141b4000.dp: main link training done! rate:540000 lanes:4
usb 16-1: new SuperSpeed Plus Gen 2x1 USB device number 2 using xhci-hcd
```

| Fonction | État sur 7.2.11 |
|---|---|
| Démarrage NVMe (PCIe Gen4), devicetree | ✅ |
| GPU Mali-G720 (panthor 1.8.0, Vulkan, cohérence ACE-Lite) | ✅ |
| HDMI 3840×2160 + DP 2560×1440 10 bits, en même temps | ✅ |
| Son sur HDMI et DP (PipeWire, profil Pro Audio) | ✅ |
| USB-C données 10 Gb/s (Type-C rts5453, orientation gérée), USB-A | ✅ |
| CPU 12 cœurs, cpufreq SCMI, boost 2,6 GHz | ✅ |
| 2× Ethernet RTL8126 (5 GbE) | ✅ |
| 2 emplacements M.2 NVMe (SSD1, SSD2) + M.2 Wi-Fi | ✅ |
| NPU (`/dev/aipu`, 3 cœurs), VPU (`/dev/video0-1`, décodage/encodage) | ✅ |
| RTC (rx8900), capteurs de température SCMI | ✅ |
| Extinction / rallumage des écrans (son HDMI conservé) | ✅ |
| Vidage mémoire après un plantage du noyau (kdump) | ✅ |
| **Veille système (suspend)** | ❌ pas de réveil, désactivée (voir Limitations) |

---

## 📋 Prérequis

| Composant | Détail |
|-----------|--------|
| Carte | Orange Pi 6 Plus |
| SoC | CIX CD8180 (Sky1) : 4× Cortex-A520 + 8× Cortex-A720 |
| RAM | 32 Go LPDDR5 |
| GPU | Mali-G720 Immortalis MC10 |
| Stockage | SSD NVMe |
| Firmware | **BIOS CIX 1.4** (la seule version testée, conseillée), **Secure Boot désactivé** (noyau non signé) |
| Système | Ubuntu 26.10 arm64 installé et démarré (noyau Ubuntu stock `-generic`) |

Version du BIOS (lisible avec le noyau Ubuntu comme avec le noyau Sky1) :
```bash
cat /sys/class/dmi/id/bios_version     # 1.4
```
Avec une autre version, le projet n'a pas été testé : mieux vaut passer d'abord le BIOS en 1.4. Le BIOS se
trouve sur la [page de support officielle de l'Orange Pi 6 Plus](http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/service-and-support/Orange-Pi-6-Plus.html)
(fichiers hébergés par Orange Pi sur Google Drive).

Le noyau stock d'Ubuntu démarre la carte en ACPI, sans GPU, sans cpufreq et sans le DP/HDMI : il sert
de base de configuration et de noyau de secours. Le noyau Sky1 démarre, lui, en devicetree.

```bash
# Dépendances de compilation (apt) — à faire une fois
sudo ./install-deps.sh            # --check pour seulement lister ce qui manque
sudo ./install-deps.sh --with-diag   # facultatif : glxinfo, vulkaninfo, v4l2-ctl, nvme-cli…
```

Conseillé : rendre le menu GRUB visible (dans `/etc/default/grub`, `GRUB_TIMEOUT_STYLE=menu` et
`GRUB_TIMEOUT=15`, puis `sudo update-grub`) pour pouvoir choisir un autre noyau en cas de problème.
Les scripts ne modifient jamais `/etc/default/grub`.

---

## 🚀 Utilisation rapide

```bash
git clone https://github.com/lpennisi73-tech/OPI6PLUS-UBUNTU.git bookworm-sky1-kernel-ubuntu
cd bookworm-sky1-kernel-ubuntu
sudo ./install-deps.sh                      # dépendances, une seule fois
sudo ./bookworm-sky1-build.sh --install     # compilation + installation (~1 h 20)
sudo reboot
./diagnostics/check-system.sh               # après le redémarrage
```

La procédure détaillée suit. Pour installer Ubuntu directement avec le noyau Sky1, des ISO prêtes à
l'emploi seront sur [www.bookworm-mon0.org/downloads.php](https://www.bookworm-mon0.org/downloads.php)
**à partir du lundi 2 novembre 2026** (voir [ISO d'installation](#-iso-dinstallation)).

---

## 📖 Procédure détaillée : compiler et installer le noyau

### 1. Avant de commencer

- Ubuntu 26.10 arm64 installé et démarré sur la carte, avec le noyau Ubuntu `-generic` (il sert de base
  de configuration et de secours) ; **BIOS CIX 1.4** (`cat /sys/class/dmi/id/bios_version`) et
  **Secure Boot désactivé** dans le BIOS (le noyau n'est pas signé).
- **Place disque** : ~25 Go libres sous `/usr/src/build` (sources, objets, paquets).
- **Durée** (Orange Pi 6 Plus, 12 cœurs) : ~1 h 20 en local, ~1 h avec distcc ; `--no-dbg` retire ~16 min.
- Lancer le build dans une session qui survit à une déconnexion ou à un plantage de GNOME (sinon le
  build meurt avec le terminal) : `screen` (installé avec Ubuntu), `tmux`, une connexion SSH, ou un
  service systemd, qui ne dépend d'aucune session :
  ```bash
  sudo systemd-run --unit=sky1-build --working-directory="$PWD" bash -c './bookworm-sky1-build.sh --install --no-dbg'
  journalctl -fu sky1-build        # suivre le build (Ctrl+C n'arrête que l'affichage)
  ```
  Avec distcc : `bash -c 'source ./distcc-env.sh && ./bookworm-sky1-build.sh --install --no-dbg'`.
  À la fin, `systemctl status sky1-build` indique le code de sortie.
- Conseillé : menu GRUB visible, pour pouvoir revenir au noyau Ubuntu si besoin. Dans
  `/etc/default/grub` : `GRUB_TIMEOUT_STYLE=menu` et `GRUB_TIMEOUT=15`, puis `sudo update-grub`.
  Les scripts ne modifient jamais ce fichier.

### 2. Récupérer le dépôt et les dépendances

```bash
git clone https://github.com/lpennisi73-tech/OPI6PLUS-UBUNTU.git bookworm-sky1-kernel-ubuntu
cd bookworm-sky1-kernel-ubuntu
./install-deps.sh --check          # liste ce qui manque, n'installe rien
sudo ./install-deps.sh             # installe ce qui manque (demande confirmation ; --yes pour s'en passer)
```

| Option d'`install-deps.sh` | Ajoute |
|---|---|
| (aucune) | compilation du noyau et des paquets, sources, installation |
| `--with-diag` | outils de diagnostic : glxinfo, vulkaninfo, glmark2, v4l2-ctl, nvme-cli |
| `--with-distcc` | distcc (compilation distribuée, étape 3) |
| `--with-iso` | xorriso, squashfs-tools, mtools, dosfstools (ISO d'installation) |

### 3. Facultatif : compilation distribuée (distcc)

Un PC x86_64 du réseau compile à la place de la carte (la compilation passe de ~60 à ~30 min ;
l'édition de liens et l'empaquetage restent sur la carte).

- **Sur le serveur** : `distccd` autorisé pour le réseau local, et le compilateur croisé
  `gcc-<même version>-aarch64-linux-gnu`. La version de gcc doit être **exactement** celle de la carte
  (`aarch64-linux-gnu-gcc --version`) : sinon le noyau mélange des objets de deux compilateurs.
- **Sur la carte** : `sudo ./install-deps.sh --with-distcc`, puis créer `distcc-env.local` (non versionné)
  avec l'adresse du serveur et le nombre de jobs :
  ```bash
  cat > distcc-env.local << 'EOF'
  DISTCC_HOST="192.168.1.50"   # adresse du serveur
  DISTCC_HOST_JOBS=16          # un job par cœur du serveur
  DISTCC_LOCAL_JOBS=4
  EOF
  ```
- Avant le build, dans le même terminal :
  ```bash
  source distcc-env.sh      # contrôle la version de gcc du serveur et affiche « identique »
  ```
  Comme le build tourne en root, garder l'environnement : `sudo -E ./bookworm-sky1-build.sh …`
  (ou tout lancer depuis un shell root : `sudo -i`, `cd`, `source distcc-env.sh`, build).

### 4. Lancer le build

```bash
screen                                      # facultatif mais conseillé (ou systemd-run, étape 1)
sudo ./bookworm-sky1-build.sh --install     # ou --install --no-dbg
```

Sans `--install`, le build s'arrête après les paquets ; l'installation se fait alors à l'étape 5.

| Option de `bookworm-sky1-build.sh` | Effet |
|---|---|
| `--kernel <track>` | track à compiler, `config/kernels/<track>.conf` (défaut : `7.2.11-stable`) |
| `--install` | lance `install/install.sh` après la compilation |
| `--no-dbg` | ne construit pas le paquet `-dbg` (~16 min et 1,7 Go de moins ; le `vmlinux` avec symboles reste dans l'arbre de build pour décoder un Oops). Permanent : `KERNEL_DBG_PKG="no"` dans `config/board.conf` |
| `--jobs <n>` | nombre de compilations en parallèle (défaut : nombre de cœurs, ou `SKY1_JOBS` de distcc-env.sh) |
| `--base-config <fichier>` | config de départ (défaut : `/boot/config-*-generic` la plus récente) |
| `--build-dir <dossier>` | dossier de build (défaut : `/usr/src/build/sky1-kernel`) |
| `--skip-download` | pas d'accès réseau : le tarball doit être présent ; l'arbre est recréé depuis le tarball s'il a été supprimé |
| `--skip-patches` | ne pas appliquer les patches (sources déjà patchées) |
| `--skip-config` | garder la `.config` existante |
| `--skip-build` | ne pas compiler (ex. : seulement installer avec `--install`) |
| `--dry-run` | afficher les étapes sans rien exécuter |

Le build affiche 6 étapes (détail plus bas) et écrit tout dans `logs/build-<date>_<heure>.log` (dans le
dépôt). À la fin, il liste les paquets produits dans `/usr/src/build/sky1-kernel/` :
`linux-image-7.2.11-sky1-custom_7.2.11-<n>_arm64.deb`, `linux-headers-…`, `linux-image-…-dbg` (sauf
`--no-dbg`) et `linux-libc-dev` (**à ne pas installer** : il remplacerait celui d'Ubuntu). Le numéro
`<n>` augmente à chaque build dans le même arbre et repart à 1 sur un arbre neuf.

### 5. Installer (si le build a été lancé sans `--install`)

```bash
sudo install/install.sh --kernel 7.2.11-stable
```

| Option d'`install.sh` | Effet |
|---|---|
| `--kernel <track>` | track installé (obligatoire si `--kernel-dir` n'est pas donné) |
| `--kernel-dir <dossier>` | arbre de build (défaut : `/usr/src/build/sky1-kernel/linux-<version>`) |
| `--deb-dir <dossier>` | dossier des `.deb` (défaut : parent de l'arbre de build) |
| `--with-dbg` | installe aussi le paquet `-dbg` du même build (symboles pour crash/kdump) |
| `--no-firmware` | ne pas installer les firmwares VPU de CIX (`cix-vpu-firmware`) |

**Avant de redémarrer**, contrôler que l'entrée Sky1 existe et vient en premier :
```bash
grep -n "^menuentry" /boot/grub/grub.cfg | head -3     # 1re ligne : « Sky1 Orange Pi 6 Plus - 7.2.11-sky1-custom (GPU+NPU) »
ls /boot/vmlinuz-7.2.11-sky1-custom /boot/initrd.img-7.2.11-sky1-custom /boot/dtb/
```

### 6. Redémarrer et vérifier

```bash
sudo reboot
```
Le menu GRUB démarre par défaut sur « Sky1 Orange Pi 6 Plus - … (GPU+NPU) ». Si ce noyau ne démarre
pas : redémarrer et choisir l'entrée **Ubuntu** (noyau stock, toujours installé) ; les messages du noyau
Sky1 sont aussi envoyés sur la console série `ttyAMA2` (115200 bauds).

Une fois sur le bureau :
```bash
uname -r                                # 7.2.11-sky1-custom
./diagnostics/check-system.sh           # GPU, CPU, PCIe/NVMe, températures…
journalctl -k -b -p warning             # avertissements du noyau
```
Les réglages de session (`/usr/lib/environment.d`) ne sont lus qu'au démarrage du gestionnaire de
session utilisateur : après un premier passage d'install.sh, il faut un **redémarrage**, une
déconnexion ne suffit pas.

### 7. Relancer, recompiler, repartir de zéro

| Situation | Commande |
|---|---|
| La compilation a échoué (erreur corrigée depuis) | `sudo ./bookworm-sky1-build.sh --skip-download --skip-patches --skip-config --install` |
| Changer une option de config et recompiler | modifier le track ou `board.conf`, puis `sudo ./bookworm-sky1-build.sh --skip-download --install` |
| Repartir de zéro (nouvelle série de patches, arbre douteux) | `sudo rm -rf /usr/src/build/sky1-kernel/linux-7.2.11` puis `sudo ./bookworm-sky1-build.sh --skip-download --install` |
| Réinstaller le même noyau / mettre à jour les réglages seuls | `sudo install/install.sh --kernel 7.2.11-stable` |

Les sources patchées portent le marqueur `.sky1-patched` : une relance ne réapplique jamais les
patches sur un arbre déjà patché (ils ne sont pas réappliquables) ; pour repatcher, supprimer l'arbre.

### 8. Désinstaller

```bash
sudo apt remove linux-image-7.2.11-sky1-custom     # le noyau (DTB et entrée GRUB partent avec lui)
sudo apt remove linux-headers-7.2.11-sky1-custom   # seulement après un build : absent d'un système installé depuis l'ISO
sudo apt purge bookworm-sky1-settings              # tous les réglages Sky1
```
Avant de retirer le dernier noyau Sky1, démarrer sur le noyau Ubuntu.

### Pour comprendre : ce que fait le build (`bookworm-sky1-build.sh`)
1. télécharge `linux-7.2.11.tar.xz` depuis kernel.org et l'extrait ;
2. applique la **série Sky1** du dépôt (`patches/sky1-7.2/`, 48 patches) en **mode strict** (aucun fuzz) ;
3. applique les **correctifs locaux** `patches/fixes/9xxx-*.patch` ;
4. applique les **fixes DTS / pilotes** `patches/fixes/*.py` (slot PCIe vide, zones thermiques…) ;
5. prend la config du noyau Ubuntu `-generic` la plus récente, y injecte la config Sky1
   (`config/sky1/config.sky1-next`), force les options indispensables (`FORCE_BUILTIN`, `FORCE_DISABLED`
   du track) et vérifie qu'`olddefconfig` ne les a pas défaites ;
6. compile et crée les paquets, puis lance `install/install.sh` avec `--install`.

Les sources patchées sont marquées `.sky1-patched` : une relance ne repatche pas. Pour repartir de zéro,
supprimer `/usr/src/build/sky1-kernel/linux-7.2.11`.

### Pour comprendre : ce que fait l'installation (`install/install.sh`)
1. construit et installe le paquet de réglages **`bookworm-sky1-settings`**
   (`packaging/build-settings-deb.sh`, voir ci-dessous) ;
2. installe les paquets du noyau : le hook dracut génère l'initramfs, le hook du paquet de réglages copie
   le DTB (`/boot/dtb/sky1-orangepi-6-plus-<version>.dtb`) et `update-grub` ajoute l'entrée Sky1 ;
3. firmwares du VPU : paquet officiel de CIX `cix-vpu-firmware`, téléchargé une fois depuis le dépôt
   de CIX et vérifié par son empreinte (`packaging/fetch-cix-firmware.sh`) ; firmware du GPU Mali fourni par
   Ubuntu (`linux-firmware`), seulement contrôlé ; liens ALSA → PipeWire vérifiés.

Les anciennes versions d'install.sh copiaient les réglages dans `/etc` : au premier passage, les copies
identiques au dépôt sont retirées (le paquet fournit la même chose), une copie modifiée est gardée.

### Pour comprendre : le paquet `bookworm-sky1-settings`
Tous les réglages Sky1 du système, installés comme un paquet Ubuntu (même principe que les paquets
`ubuntu-x1e-settings` des portables Snapdragon). Les valeurs par défaut vont sous `/usr` ; un fichier du
même nom dans `/etc` reste prioritaire. Contenu :
- `/etc/grub.d/07_sky1` : une entrée par noyau Sky1 (devicetree + `acpi=off`, plus une Recovery),
  **la plus récente démarre par défaut** ; le disque est détecté par `update-grub`, rien n'est écrit en dur ;
- `/etc/default/bookworm-sky1` : paramètres du noyau Sky1 (repris de `KERNEL_CMDLINE`, `config/board.conf`) ;
- hook `/etc/kernel/post{inst,rm}.d/zz-bookworm-sky1-dtb` : un DTB par noyau, ajouté ou retiré avec lui ;
- config dracut, modules chargés au boot et options (`MODULES_AUTOLOAD`, `MODPROBE_OPTIONS`) ;
- udev USB-C et GPU, blocage de la veille, environnement de session, PipeWire/WirePlumber ;
- gouverneur CPU réglé pour le bureau (`sky1-cpufreq-tune.service`, réglages dans `/etc/default/sky1-cpufreq`,
  lancé seulement sur l'entrée Sky1) ;
- VLC en sortie ALSA (service utilisateur, une fois par utilisateur) ;
- noyau de secours kdump adapté à la carte (si `kdump-tools` est installé, voir GRUB plus bas).

Version : `1.1.<n>`, où `<n>` compte les commits qui touchent les fichiers du paquet (liste `PKG_SOURCES`
de `packaging/build-settings-deb.sh`) : un commit de documentation ne change pas la version. Les
versions `1.0.x` (jusqu'au 21 octobre 2026) comptaient tous les commits ; `1.1.x` leur succède
normalement à la mise à jour.

Où trouver les fichiers (liste complète : `dpkg -L bookworm-sky1-settings`) :

| Réglage | Fichiers du paquet | Pour le changer |
|---|---|---|
| Session (GNOME, GTK, GStreamer) | `/usr/lib/environment.d/90-sky1-*.conf` | même nom dans `/etc/environment.d/` (ou `~/.config/environment.d/`) |
| udev (GPU, USB-C) | `/usr/lib/udev/rules.d/90-sky1-*.rules` | même nom dans `/etc/udev/rules.d/` |
| Veille | `/usr/lib/systemd/sleep.conf.d/90-sky1-no-suspend.conf` | `/etc/systemd/sleep.conf.d/` |
| Son | `/usr/share/wireplumber/wireplumber.conf.d/5*-sky1-*.conf`, `/usr/share/pipewire/pipewire-pulse.conf.d/`, `/usr/share/alsa-card-profile/mixer/profile-sets/sky1-hdmi-dp.conf` | `/etc/wireplumber/wireplumber.conf.d/` |
| Modules, dracut | `/usr/lib/modules-load.d/`, `/usr/lib/modprobe.d/`, `/usr/lib/dracut/dracut.conf.d/` (`bookworm-sky1*`) | même nom dans `/etc/…` |
| VLC (sortie ALSA) | `/usr/libexec/bookworm-sky1/sky1-vlc-aout`, service utilisateur `bookworm-sky1-vlc-aout` | dans VLC (*Préférences → Audio*) : le choix n'est plus jamais touché |
| kdump (noyau de secours) | `/usr/lib/systemd/system/kdump-tools.service.d/90-bookworm-sky1.conf` | `KDUMP_CMDLINE_APPEND` dans `/etc/default/kdump-tools` |
| geoclue (sans libproxy) | `/usr/lib/systemd/system/geoclue.service.d/90-bookworm-sky1.conf` | même nom dans `/etc/systemd/system/geoclue.service.d/` |
| GRUB, cpufreq, DTB | `/etc/grub.d/07_sky1`, `/etc/default/bookworm-sky1`, `/etc/default/sky1-cpufreq`, `/etc/kernel/post*.d/zz-bookworm-sky1-dtb` | ces fichiers directement (gardés lors des mises à jour) |

`/etc/environment.d/` est donc normalement vide de réglages Sky1. Pour vérifier qu'ils sont actifs :
`systemctl --user show-environment | grep -E 'COGL|GDK_DISABLE|GST_PLUGIN'`.

Tout retirer : `sudo apt purge bookworm-sky1-settings`.

Le noyau Ubuntu stock reste installé et garde son entrée GRUB : c'est le secours.

---

## 🖥️ Track noyau

| Track | Base | Statut |
|-------|------|--------|
| `7.2.11-stable` | Linux 7.2.11 (stable maintenue kernel.org) | ✅ **Par défaut, validé le 16 octobre 2026** |

Le projet [Sky1-Linux/linux-sky1](https://github.com/Sky1-Linux/linux-sky1), d'où vient la série de
patches, est à l'arrêt depuis le 28 février 2026 (série pour Linux 7.0). La série a été **portée sur
Linux 7.2** dans ce dépôt (`patches/sky1-7.2/`, décisions patch par patch dans son `README.md`) :

- 43 patches Sky1-Linux, dont 11 adaptés aux changements de Linux 7.2 ;
- `0044` (BOOKWORM) : pilotes du constructeur adaptés aux API de Linux 7.2 ;
- `0045` (BOOKWORM) : écran fantôme, cache firmware du VPU, deux avertissements noyau ;
- `0046` (BOOKWORM) : VPU bloqué quand un lecteur se déplace dans la vidéo pendant sa mise en route ;
- `0047` (BOOKWORM) : HDR masqué (son activation plantait le noyau et GNOME) ;
- `0048` (BOOKWORM) : son HDMI perdu au réveil de l'écran (réinitialisation complète du contrôleur DP).

La config Sky1 de référence est copiée dans `config/sky1/` : le build ne dépend plus de linux-sky1.
Pour porter la série sur une version suivante (7.3…), voir `tools/portage-sky1/README.md`.
`./check-sky1-updates.sh` surveille linux-sky1 et kernel.org.

Les tracks Gentoo `6.18.14-lts`, `6.19-latest` et `7.0-next` ont été retirés en octobre 2026 (voir
l'historique git).

---

## 🔧 Problèmes résolus pour Ubuntu et Linux 7.2

| Problème | Cause | Correction |
|---|---|---|
| NVMe introuvable au boot (`sky1-pcie … -110`) | fournisseurs SCMI/régulateurs en module dans la config Ubuntu, absents de l'initramfs | forcés `=y` (`FORCE_BUILTIN`) |
| Erreur de compilation `pcie-cadence-plat.c` | `PCIE_CADENCE_PLAT_EP=y` (Ubuntu) réactive `PCIE_CADENCE_PLAT` | `FORCE_DISABLED` |
| Ports USB-C sans USB, pas de RTC | `I2C_CADENCE` absent de la config Ubuntu : aucun bus I2C, donc ni rts5453 ni rx8900 | `FORCE_BUILTIN` + `rtc-rv8803` chargé au boot |
| Disque USB-C jamais détecté | le contrôleur USB-C et son xHCI passent en veille avant l'énumération et ne se réveillent pas | `config/udev/90-sky1-typec-usb-pm.rules` |
| Port USB-C 0 mort au démarrage (`timeout waiting for xhci_ready`, rafale de `arm-scmi … timed out`) | le contrôleur démarre dans l'initramfs et passe en veille avant que la règle udev ne s'applique | règles `90-sky1-*.rules` aussi dans l'initramfs (dracut `install_items`, hook initramfs-tools) |
| Rapport de plantage de l'installateur au clic « Redémarrer » | `zpool export -a` échoue : pas de module ZFS dans le noyau Sky1 | enveloppe `zpool` dans le système live de l'ISO (`/usr/local/sbin/zpool`) |
| Bureau figé, session impossible à arrêter (`Failed to stop MCU`, processus en état D) | la mise en veille runtime du GPU échoue et panthor s'interbloque entre veille et reset | `config/udev/90-sky1-gpu-pm.rules` (GPU maintenu éveillé) |
| Pilote d'affichage disputé au boot | Linux 7.2 : `komeda` reconnaît aussi l'affichage Sky1 | `DRM_KOMEDA` désactivé |
| 2ᵉ écran « Inconnu » dans GNOME | le framebuffer du firmware (simpledrm) n'était jamais retiré | patch `0045` (linlon-dp) |
| Trace noyau à la lecture vidéo | firmwares VPU absents + bug du pilote sur ce cas (mémoire libérée réutilisée) | paquet `cix-vpu-firmware` + patch `0045` |
| Lecteur vidéo GNOME : image verte figée | affichage des images du VPU dans GTK4 | décodage CPU pour le bureau (`config/environment.d/`) |
| Showtime se ferme au passage en plein écran (`drmPrimeHandleToFD() failed`, `Error 9`) | l'offload graphique de GTK4 exporte un buffer GPU privé, que panthor refuse | `GDK_DISABLE=offload` (`config/environment.d/90-sky1-gtk-offload.conf`) |
| Vidéo qui saccade à l'ouverture des notifications ou du menu système | en OpenGL bureau, gnome-shell envoie ses images BGRA en RGBA8 et Mesa convertit chaque pixel sur le processeur | gnome-shell en OpenGL ES : `COGL_DRIVER=gles2` (`config/environment.d/90-sky1-mutter-gles.conf`) |
| Son haché dans VLC | sorties DP/HDMI à 85 ms par bloc, tampons des clients Pulse trop petits | `config/pipewire/pipewire-pulse.conf.d/` (+ VLC en sortie ALSA, voir plus bas) |
| Entrée GRUB du 7.0 avant celle du 7.2 | tri alphabétique de `/etc/grub.d` | `/etc/grub.d/07_sky1` trie les noyaux Sky1 par version |
| Image en 6 bits par couleur après un rebond de l'écran au réveil (`info_format=0, force support RGB444`) | le modeset forcé après le rebond partait avant la relecture de l'EDID, que GNOME avait effacée pendant les 2 s « débranché » | `9007` relit l'EDID avant le modeset (« HPD bounce: EDID re-read, bpc=… ») |
| `geoclue` en échec au démarrage (`start operation timed out`, 90 s) | interblocage dans GIO au démarrage de geoclue : le module libproxy, chargé sous le verrou des modules, attend l'initialisation que le fil principal ne peut pas finir | résolveur de proxy « dummy » pour geoclue : `/usr/lib/systemd/system/geoclue.service.d/90-bookworm-sky1.conf` |
| `cros-ec-i2c 6-0076: Cannot identify the EC: error -71` à chaque démarrage | nœud EC repris de la carte de référence CIX (un portable : batterie, capot, clavier) ; aucun EC de ce type sur l'Orange Pi 6 Plus | nœud désactivé (`dts-disable-cros-ec.py`) |

Correctifs repris de l'époque Gentoo, toujours appliqués : SError sur slot PCIe vide
(`pci-sky1-link-down-guard.py`), boost SCMI dès le démarrage (`9004`), écran noir au réveil HDMI
(`9007`), son DP/HDMI (`9001`, `9009`), VPU (`9002`, `9003`), USB Cadence (`9005`, `9008`).

Tous les emplacements PCIe de la carte sont actifs : les deux M.2 pour SSD NVMe (« SSD1 » `a070000`,
« SSD2 » `a010000`), le M.2 Wi-Fi (`a0d0000`) et les deux Ethernet 5G. Un emplacement vide est signalé au
démarrage par `PCIe link down, slot may be empty`, sans erreur. L'ancien correctif Gentoo qui
désactivait SSD1 et Wi-Fi dans le DTS a été retiré (2026-10-21) : il rendait un 2e SSD ou une carte Wi-Fi
M.2 invisibles.

---

## ⚠️ Limitations connues

### Écran noir au démarrage (BIOS et HDMI)
Bug connu du BIOS CIX : au démarrage, il arrive que **rien ne s'affiche sur l'écran HDMI** (pas de logo, pas
de menu). La carte n'est pas en panne : appuyer sur **Ctrl+Alt+Suppr** pour la redémarrer, l'image revient
en général au démarrage suivant. Recommencer si besoin.

### Veille système : désactivée
Ni `deep` ni `s2idle` ne se réveillent sur cette carte (clavier, souris, bouton d'alimentation, alarme
RTC) : il faut couper le courant. `config/systemd/sleep.conf.d/90-sky1-no-suspend.conf` bloque donc la
mise en veille (GNOME masque « Mettre en veille »). L'**extinction des écrans fonctionne** normalement.
Diagnostic prévu avec la console série (`ttyAMA2`, 115200 bauds).

### HDR : désactivé
Activer le HDR dans *Paramètres → Écrans* faisait planter le noyau et la session GNOME. Depuis le patch
0047, le pilote du DP n'annonce plus les propriétés HDR (`Colorspace`, `HDR_OUTPUT_METADATA`) : GNOME
n'affiche plus l'option. Le 10 bits reste disponible. Pour tester le HDR malgré tout (à vos risques) :
paramètre noyau `trilin_dpsub.hdr=1`.

### Son HDMI qui disparaît jusqu'au redémarrage
De temps en temps, la file audio du contrôleur DP qui alimente le HDMI se bloque, dans la seconde qui
suit le démarrage d'un son (environ une fois toutes les 5 à 25 ouvertures de la sortie, mesuré avec
`diagnostics/audio-stress-test.sh`). Le son reste alors coupé ; seul un redémarrage le rétablit
(rebranchement du câble, rechargement de la carte son ou de l'I2S : sans effet). Pour l'éviter, les
sorties DP et HDMI restent ouvertes en permanence (elles envoient du silence) : la file ne démarre plus
qu'une fois par session au lieu d'à chaque son.

Même avec les sorties ouvertes, le blocage se produisait au réveil de l'écran (extinction puis
rallumage, souvent suivi d'une déconnexion/reconnexion de l'écran) : le lien DP repart alors que le son
tourne déjà. Depuis le patch 0048, le pilote fait dans ce cas la réinitialisation complète du contrôleur
DP, comme au démarrage, et le son revient. Réglable à chaud : `trilin_dpsub.audio_reset=0` pour la
couper. Si le son disparaît malgré tout : redémarrer.

### Vidéo dans le bureau : décodage par le CPU
Le VPU décode correctement (environ 200 images/s en 1080p H.264) et ses images s'affichent dans GTK4,
mais le lecteur GNOME (Showtime) reste sur un écran noir : il reprend la vidéo à la dernière position,
et ce déplacement juste après le démarrage bloque le VPU. Un premier défaut du pilote est corrigé
(patch `0046`) ; le second vient du firmware de CIX, qui perd son contexte quand la file de sortie est
réallouée en cours de décodage (l'affichage GTK garde la dernière image) et refuse l'autre façon de
faire ; l'affichage du VPU dans le bureau clignote aussi (image du framebuffer en surimpression,
saccades). `config/environment.d/90-sky1-gst-v4l2-rank.conf` retire donc les décodeurs V4L2 du choix
automatique de GStreamer : les lecteurs décodent par le CPU, sans difficulté (un film 1080p H.264 passe
sans saccade). Le décodeur CPU vient de `gstreamer1.0-libav`, que l'installateur pose seulement avec la
case **« Installer les logiciels tiers / codecs »** : cochez-la, ou installez-le ensuite
(`sudo apt install gstreamer1.0-libav`). Sans lui (session live, installation sans codecs tiers), les
lecteurs GStreamer ne lisent pas le H.264, comme sur Ubuntu d'origine (VLC, qui a ses propres codecs,
fonctionne). Le VPU reste utilisable explicitement :
```bash
gst-launch-1.0 filesrc location=video.mp4 ! qtdemux ! h264parse ! v4l2h264dec ! fakesink
```

### Showtime sur Ubuntu 26.04.1 : vidéo saccadée
Sur la 26.04.1 seulement, le lecteur vidéo de GNOME (Showtime) saccade, quel que soit le rendu de GTK
(`GSK_RENDERER=gl` et `cairo` sans effet, `vulkan` en erreur) : le défaut est dans Showtime de la 26.04.1. Le système et les autres lecteurs sont fluides :
**utilisez VLC** (Ubuntu Software / App Center). Sur la 26.10, Showtime fonctionne parfaitement.

### VLC : sortie ALSA par défaut
Même avec des tampons corrects, le module de sortie PulseAudio de VLC 3 hache le son par moments sur
les sorties DP/HDMI. Avec la sortie ALSA (qui passe aussi par PipeWire), le son est propre, y compris en
AC-3 5.1. Le paquet de réglages le fait pour chaque utilisateur, **une seule fois**, à l'ouverture de
session (service utilisateur `bookworm-sky1-vlc-aout`) : `aout=alsa` est ajouté à
`~/.config/vlc/vlcrc` si aucune sortie n'y est choisie ou si elle est sur « Automatique » (`aout=any`)
(fichier créé s'il n'existe pas ; VLC peut être installé avant ou après). Un choix fait ensuite dans
*Outils → Préférences → Audio → Module de sortie*, « Automatique » compris, est gardé. Pour que le service repasse : supprimer `~/.local/state/bookworm-sky1/vlc-aout.done`.
VLC en snap (dossier `~/snap/vlc/`) n'est pas concerné : régler la sortie à la main.

### Blocage rare du GPU
Le GPU (pilote panthor) peut se bloquer d'un coup (`CSG … update request timedout`, `Failed to stop MCU`
dans `journalctl -k`) : gnome-shell redémarre en rendu logiciel, la session est perdue, et seul un
redémarrage rend le GPU. Devenu rare depuis que le GPU n'a plus de veille runtime (règle udev du paquet),
mais vu deux fois le 21 octobre 2026 (dont une fois pendant une compilation du noyau, qui est morte avec le
terminal : d'où le conseil de lancer le build hors de la session). Cause non trouvée ; si ça arrive,
notez l'heure et ce que vous faisiez.

### Autres
- **Températures** : le firmware refuse d'activer les capteurs SCMI (`Error enabling sensor … err=-2`) :
  lecture possible (`sensors`), mais pas de zones thermiques ni de limitation par le noyau.
- Bruit de démarrage sans conséquence : fautes SMMU de `141d0000.disp-controller` (scanout du firmware),
  `sky1_timer … -2`, `SCMI protocol 129 not implemented`, `bpf-restrict-fs` (BTF désactivé).
- **KVM sur le bus USB 10** (`9290000`) : après une bascule, clavier et souris peuvent disparaître ;
  `sudo scripts-addons/usb-rebind-bus10` réinitialise ce contrôleur.
- Le firmware du DSP audio (paquet `cix-audio-dsp` de CIX) n'est pas installé : rien ne s'en sert. Le son
  passe directement par l'I2S et le HDA ; le DSP (`remoteproc0`, `cix-dsp-rproc`) ne démarre pas tout seul
  et le device tree ne déclare pas de carte son SOF qui l'utiliserait.
- Encodage VPU (`scripts-addons/bookworm-vpu-encode`) : écrit pour le `ffmpeg-sky1` de Gentoo, pas
  encore adapté à Ubuntu.

---

## 🔊 Audio DP / HDMI

Carte ALSA `cix_sky1` : périphérique 0 = DisplayPort, 1 = HDMI (convertisseur DP→HDMI Parade PS185HDM
sur `dp4`). Le paquet `bookworm-sky1-settings` installe :
- `config/wireplumber/` : profil **Pro Audio** par défaut (sans lui, seul le DP est exposé), sorties
  nommées « DisplayPort » et « HDMI », **HDMI par défaut**, quantum forcé à 4096 (le son hache à 1024) ;
- `config/alsa-card-profile/` : profils de la carte réduits à « Éteint » et « Pro Audio » (le profil
  générique proposait une « Sortie analogique » inexistante qui faisait disparaître DP et HDMI) ;
- `config/pipewire/pipewire-pulse.conf.d/` : tampons des applications PulseAudio alignés sur ce quantum ;
- sorties DP et HDMI **jamais mises en veille ni en pause** (`session.suspend-timeout-seconds = 0`,
  `node.pause-on-idle = false`) : voir « Son HDMI qui disparaît » dans les limitations, plus haut.

Un profil audio déjà mémorisé par WirePlumber pour un utilisateur (`~/.local/state/wireplumber/`) reste
prioritaire. Le bouton « Tester » de GNOME ne fonctionne pas avec le profil Pro Audio.

---

## 🖥️ GRUB, console, Recovery

- Une entrée par noyau Sky1, créée par `/etc/grub.d/07_sky1` à chaque `update-grub` : devicetree du
  noyau, `acpi=off`, paramètres de `/etc/default/bookworm-sky1`. La plus récente est la première =
  entrée par défaut avec `GRUB_DEFAULT=0`. L'entrée automatique d'Ubuntu (`10_linux`) pour le même
  noyau démarre en ACPI, sans devicetree : ne pas l'utiliser.
- **Logo Ubuntu au démarrage (Plymouth)** : l'entrée normale reprend `GRUB_CMDLINE_LINUX_DEFAULT` de
  `/etc/default/grub` (`quiet splash` sur Ubuntu), comme `10_linux`. Pour voir les messages du noyau à
  la place, retirez `quiet splash` de cette ligne puis `sudo update-grub`.
- Entrée **Recovery** : `systemd.unit=rescue.target`, sans `quiet splash` (messages du noyau à l'écran).
- **`crashkernel=…`** : ajouté à `GRUB_CMDLINE_LINUX_DEFAULT` par `kdump-tools`, que l'installateur
  d'Ubuntu active quand la machine a au moins 6 Go de RAM et assez de place dans `/var` (5 × la RAM).
  Il réserve de la mémoire pour un noyau de secours qui enregistre un vidage dans `/var/crash` si le
  noyau plante : environ 640 Mo sur une carte de 16 Go, 1,1 Go sur 32 Go. Le premier démarrage après
  l'installation d'un noyau prépare son initrd de secours (environ 45 s de plus, une seule fois). Pour
  le retirer : `sudo apt purge kdump-tools linux-crashdump && sudo update-grub`. Le live de l'ISO n'est
  pas concerné. Le paquet de réglages adapte le noyau de secours à la carte
  (`/usr/lib/systemd/system/kdump-tools.service.d/90-bookworm-sky1.conf`) : `cma=0` et pilotes GPU,
  NPU, VPU, affichage et DSP exclus, sans quoi il manque de mémoire et n'écrit rien. Une valeur de
  `KDUMP_CMDLINE_APPEND` posée dans `/etc/default/kdump-tools` passe devant.
- `console=ttyAMA2,115200 console=tty0` : messages sur la console série et à l'écran ; consoles texte
  (Ctrl+Alt+F3) disponibles.
- Désinstaller un noyau : `sudo apt remove linux-image-<version>` (et `linux-headers-<version>` s'il est
  installé, après un build) ; son DTB et son entrée GRUB partent avec lui.

---

## 🌍 Langue, clavier, fuseau (facultatif)

`scripts-addons/set-locale.sh` règle la langue du système, le clavier (écran de connexion, console) et
le fuseau horaire avec `localectl` / `timedatectl` :
```bash
sudo ./scripts-addons/set-locale.sh --lang fr_CH --tz Europe/Zurich --dry-run   # simulation
sudo ./scripts-addons/set-locale.sh --lang fr_CH --tz Europe/Zurich
sudo ./scripts-addons/set-locale.sh --lang en_US --kbd ch:fr                    # anglais, clavier suisse
```
Les sessions GNOME existantes gardent leurs propres réglages (Paramètres → Région et langue, Clavier).

---

## 💿 ISO d'installation

> **Non officielle** : ce n'est pas une ISO Ubuntu officielle, ne pas la présenter comme telle
> (licences des firmwares : voir `firmware/README.md`).

**ISO prêtes à l'emploi : [www.bookworm-mon0.org/downloads.php](https://www.bookworm-mon0.org/downloads.php)**,
avec leur fichier `.sha256`, **disponibles à partir du lundi 2 novembre 2026** (avant cette date, elles
ne sont pas encore en ligne). Après le téléchargement, vérifier l'ISO avant de l'écrire sur une clé :
```bash
sha256sum -c ubuntu-*-bookworm-sky1-orangepi6plus-arm64-*.iso.sha256    # doit afficher « OK »
```
puis passer directement à l'étape 4 (écrire l'ISO sur une clé). Les étapes 1 à 3 servent à construire
l'ISO soi-même.

`iso/build-iso.sh` part d'une ISO officielle d'Ubuntu (jamais modifiée) et y
ajoute le noyau Sky1 et `bookworm-sky1-settings`, à la fois dans le **système live** et dans le système
que l'**installateur Ubuntu** copie sur le disque. Le menu de l'ISO démarre par défaut sur le noyau Sky1
(devicetree + `acpi=off`) ; l'entrée Ubuntu d'origine reste disponible. Après installation, le disque a
les mêmes entrées GRUB qu'avec install.sh (Sky1 par défaut, noyau Ubuntu en secours).

### Choisir la version d'Ubuntu (`--distro`)

Comme les *tracks* du noyau, chaque version d'Ubuntu a son fichier `config/distros/<distro>.conf` : ISO
officielle, adresse de téléchargement, empreinte SHA256 figée, nom de l'ISO produite.
`sudo iso/build-iso.sh --list-distros` les affiche.

| `--distro` | Base | Mises à jour d'Ubuntu | État |
|---|---|---|---|
| `ubuntu-26.10` (défaut) | Ubuntu 26.10 | 9 mois (jusqu'en juillet 2027) | validée (live + installation) |
| `ubuntu-26.04.1` | Ubuntu 26.04.1 LTS | 5 ans (jusqu'en avril 2031) | validée (live + installation), voir « Showtime sur 26.04.1 » |

Le **noyau Sky1, ses réglages et les firmwares VPU sont les mêmes** quelle que soit la version : ils ne
viennent pas d'Ubuntu, et leurs mises à jour viennent de ce projet. Avec une LTS, Ubuntu met à jour tout le
reste du système pendant 5 ans.

Ajouter une version : copier un fichier de `config/distros/`, y mettre le nom de l'ISO, son adresse et son
empreinte (prise dans le `SHA256SUMS` signé d'Ubuntu), puis tester le live et l'installation avant de
passer `STATUS="stable"`.

### 1. Prérequis

- Un noyau Sky1 **déjà compilé** : paquet `linux-image-*-sky1-custom_*.deb` dans `/usr/src/build/sky1-kernel/`
  (procédure ci-dessus ; `--no-dbg` suffit, le paquet `-dbg` n'entre pas dans l'ISO).
- Les outils : `sudo ./install-deps.sh --with-iso`.
- **~35 Go libres** sous `/usr/src/build/sky1-iso` (le script vérifie et s'arrête sinon), plus ~5 Go pour l'ISO produite.
- Durée : ~20 à 40 min, surtout la recompression des couches squashfs.

### 2. L'ISO officielle

Rien à faire : si elle manque dans `/usr/src/build/sky1-iso/`, le script la télécharge. Il vérifie d'abord la
**signature d'Ubuntu** sur la liste `SHA256SUMS` (clé `ubuntu-cdimage-keyring`), puis que l'empreinte figée
dans `config/distros/` y figure, puis l'empreinte de l'ISO téléchargée. À chaque construction, l'empreinte de
l'ISO présente est contrôlée : une ISO abîmée ou différente arrête le script (la supprimer pour la
retélécharger).

### 3. Construire l'ISO

```bash
cd ~/bookworm-sky1-kernel-ubuntu                   # le dépôt
sudo iso/build-iso.sh                              # Ubuntu 26.10
sudo iso/build-iso.sh --distro ubuntu-26.04.1      # Ubuntu 26.04.1 LTS
```

| Option de `build-iso.sh` | Effet |
|---|---|
| `--distro <distro>` | version d'Ubuntu, fichier `config/distros/<distro>.conf` (défaut : `ubuntu-26.10`) |
| `--list-distros` | lister les versions disponibles |
| `--iso <fichier>` | utiliser cette ISO officielle telle quelle (défaut : celle de la distribution, téléchargée si absente ; une empreinte différente donne un avertissement) |
| `--kernel-deb <fichier>` | paquet noyau (défaut : le `linux-image-*-sky1-custom` le plus récent de `/usr/src/build/sky1-kernel`) |
| `--out <fichier>` | ISO produite (défaut : `…/sky1-iso/ubuntu-<version>-bookworm-sky1-orangepi6plus-arm64-<date>.iso`) |
| `--work <dossier>` | dossier de travail (défaut : `/usr/src/build/sky1-iso/work`, effacé au départ) |
| `--keep-work` | garder le dossier de travail à la fin |
| `--resume` | reprendre à l'étape 7 après un échec en fin de script (étapes 1 à 6 déjà faites, même `--distro`) |

Ce que fait chaque étape :
1. extrait l'ISO officielle dans le dossier de travail ;
2. construit `bookworm-sky1-settings` et prend le paquet noyau ;
3. installe les deux paquets dans la couche squashfs `minimal` (chroot) : c'est la base du système live
   **et** du système installé ; le noyau, son initramfs, son DTB et l'entrée GRUB `07_sky1` y sont vérifiés ;
4. ajoute nos deux paquets à la base dpkg des autres couches (chacune a sa propre copie, qui masquerait
   celle de `minimal`) et les recompresse ;
5. génère l'initrd du système live (casper) pour le noyau Sky1 ;
6. recompresse les couches `minimal`, `standard` et `live` (xz, l'étape la plus longue, sans affichage) ;
7. met à jour les métadonnées : tailles, manifestes, menu GRUB, `md5sum.txt`, et écrit
   `.disk/bookworm-sky1-info` (noyau, réglages, date). `.disk/info` reste **celui de l'ISO officielle** :
   l'installateur Ubuntu en lit le nom de code entre guillemets et se bloque sans message si la ligne change ;
8. crée l'ISO avec la même structure de démarrage (partition EFI) que l'ISO officielle, et son `.sha256`.

Messages **normaux** pendant l'étape 5 (le chroot n'a pas de vrai disque racine) :
`cryptsetup: ERROR: Couldn't resolve device overlay`, `grep: /etc/fstab: No such file or directory`,
`Warning: root device does not exist`, `mount: /sys/firmware/efi/efivars: mount() failed`. Seule compte la
ligne `OK casper/initrd-sky1 (…), uuid …`. À l'étape 8, `xorriso : WARNING : -volid text …` est sans effet
(le nom du volume contient des espaces, comme l'ISO officielle).

Si le script s'arrête aux étapes 7 ou 8, corriger puis `sudo iso/build-iso.sh --resume` (quelques
minutes). Une erreur plus tôt : relancer sans `--resume`, le dossier de travail est refait.
Tous les montages (chroot, overlay) sont démontés à la sortie, même en cas d'erreur.

La fin affiche le chemin, la taille (~4,5 Go pour la 26.04.1, ~4,9 Go pour la 26.10) et le SHA256 de l'ISO. Vérification :
```bash
cd /usr/src/build/sky1-iso && sha256sum -c ubuntu-*-bookworm-sky1-orangepi6plus-arm64-*.iso.sha256
```

### 4. Écrire l'ISO sur une clé USB (≥ 8 Go)

> ⚠️ `dd` efface **tout** le périphérique visé, sans confirmation. Ne jamais viser `nvme0n1` (le disque
> système). Une seule commande `dd` à la fois, et toujours sur la **clé entière** (`/dev/sdX`), jamais sur
> une partition (`/dev/sdX1`) : deux `dd` en même temps sur la même clé donnent une clé corrompue.

Dans les commandes ci-dessous, **`sdX` est à remplacer** par le nom de la clé (souvent `sda` ou `sdb`), et
`ISO=` par le chemin de votre ISO : celle construite à l'étape 3 (dans `/usr/src/build/sky1-iso/`) ou
celle téléchargée (par exemple dans `~/Téléchargements/`).

1. Brancher la clé et l'identifier (colonne `TRAN` = `usb`, taille et modèle de la clé) :
   ```bash
   lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
   ```
2. Démonter ses partitions si le bureau les a montées :
   ```bash
   sudo umount /dev/sdX?*
   ```
3. Écrire l'ISO, puis vider les tampons :
   ```bash
   ISO=/usr/src/build/sky1-iso/ubuntu-26.10-bookworm-sky1-orangepi6plus-arm64-20261023.iso
   sudo dd if="$ISO" of=/dev/sdX bs=4M conv=fsync status=progress
   sync
   ```
   Le débit affiché au début (plusieurs Go/s) est celui de la mémoire vive : la commande ne rend la main
   qu'une fois tout écrit sur la clé, ce qui prend plusieurs minutes.
4. Vérifier que la clé contient exactement l'ISO :
   ```bash
   sudo cmp -n "$(stat -c %s "$ISO")" "$ISO" /dev/sdX && echo "clé identique à l'ISO"
   ```

**Avec Ventoy** : copier simplement le fichier `.iso` sur la partition Ventoy (pas de `dd`). Au démarrage,
choisir l'ISO dans le menu Ventoy ; si le démarrage échoue en mode normal, essayer le mode GRUB2 de Ventoy.
En cas d'échec avec Ventoy, tester une clé écrite avec `dd` pour savoir si le problème vient de Ventoy.

### 5. Démarrer sur la clé

1. Brancher la clé sur l'Orange Pi 6 Plus et choisir la clé dans le menu de démarrage du firmware
   (**BIOS CIX 1.4** conseillé, Secure Boot désactivé). Écran HDMI noir dès l'allumage : bug connu du
   BIOS, **Ctrl+Alt+Suppr** pour redémarrer (voir Limitations).
2. Menu GRUB de l'ISO :
   - **« Essayer ou installer Ubuntu - Orange Pi 6 Plus (noyau Sky1 …) »** : entrée par défaut, à utiliser ;
   - « Try or Install Ubuntu (noyau Ubuntu generique, ACPI, sans acceleration graphique) » : noyau
     d'origine de l'ISO, affichage de base seulement (secours).
3. Les messages du démarrage s'affichent à l'écran et sur la console série `ttyAMA2` (115200 bauds), utile
   en cas de blocage. Au premier démarrage, le système live vérifie les fichiers de l'ISO (`md5sum.txt`).
4. Dans le système live : `uname -r` doit afficher `…-sky1-custom` ; bureau GNOME, son DP/HDMI, réseau
   fonctionnent comme sur un système installé. L'installateur Ubuntu se lance depuis le bureau.

### 6. Installer (sur un disque sauvegardé)

> L'installation efface le disque choisi : faire d'abord une sauvegarde (clone) du disque de la carte.

**Avec deux SSD**, choisir le disque dans l'installateur par son **modèle et sa taille**, jamais par son nom :
`nvme0n1` et `nvme1n1` peuvent s'inverser d'un démarrage à l'autre (constaté sur cette carte : le même SSD
s'appelait `nvme1n1` à un démarrage, `nvme0n1` au suivant). Pour les repérer depuis le live :
`lsblk -o NAME,SIZE,MODEL,SERIAL`.

L'installateur est celui d'Ubuntu. À la fin, le disque contient le noyau Sky1, `bookworm-sky1-settings`
et le noyau Ubuntu de secours ; GRUB démarre par défaut sur l'entrée Sky1 (créée par `/etc/grub.d/07_sky1`,
qui trouve le disque tout seul). Ensuite, les mises à jour du noyau se font avec la procédure ci-dessus
(`bookworm-sky1-build.sh --install`).

---

## 💾 Cloner et restaurer un disque (`scripts-addons/bookworm-clone.sh`)

Pas à pas en conditions réelles (préparation, clonage, vérification, restauration, messages) :
**[docs/guide-clonage.md](docs/guide-clonage.md)**.

Sauvegarde complète d'un disque (dd + zstd) avant une installation ou un test risqué, **avec contrôles** :
empreinte SHA256 du disque prise pendant la lecture, image vérifiée par décompression complète, image
revérifiée avant toute restauration, disque relu et comparé après restauration.

Un disque système ne se clone pas à chaud : **démarrer sur une clé live** (ISO Ubuntu ou BOOKWORM Sky1),
copier le script sur le disque externe de sauvegarde, puis :

```bash
sudo ./bookworm-clone.sh list                                # disques ; repérer le NVMe et le disque externe
sudo ./bookworm-clone.sh save /dev/nvme0n1 /media/ubuntu/SAUVEGARDE
#    → /media/ubuntu/SAUVEGARDE/clone-nvme0n1-<date>/  (disk.img.zst, clone.info, partitions, journal)
sudo ./bookworm-clone.sh verify /media/ubuntu/SAUVEGARDE/clone-nvme0n1-<date>   # revérifier plus tard
sudo ./bookworm-clone.sh restore /media/ubuntu/SAUVEGARDE/clone-nvme0n1-<date> /dev/nvme0n1
```

| Garde-fou | `save` | `restore` |
|---|---|---|
| Disque entier seulement (pas une partition) | ✅ | ✅ |
| Aucune partition montée (sinon : clé live) | ✅ | ✅ (contrôlé deux fois) |
| Destination / image sur un autre disque que celui traité | ✅ | ✅ |
| Refus du disque du système en cours | — | ✅ |
| Cible assez grande | — | ✅ |
| Image vérifiée (empreinte + taille) | après écriture | **avant** d'écrire |
| Confirmation en tapant le nom du disque | — | ✅ |
| Cible ≠ disque cloné (n° de série différent) : avertissement, confirmation par le n° de série | — | ✅ |
| Disque relu et comparé à l'image | — | ✅ |

L'image est écrite en `disk.img.zst.partial` et renommée seulement si la copie est complète. Taille de
l'image : l'espace vide déjà effacé se compresse presque à rien, les anciennes données jamais effacées non
(prévoir large). Restauration sur un disque plus grand : le script indique la commande qui replace la table
GPT de secours à la fin du disque.

---

## ⚙️ Options avancées

Toutes les options : `./bookworm-sky1-build.sh --help`, `install/install.sh --help`,
`iso/build-iso.sh --help`, `./install-deps.sh --help` (détail dans les procédures ci-dessus).

`config/board.conf` : ligne de commande du noyau (`KERNEL_CMDLINE`, reprise dans
`/etc/default/bookworm-sky1`), modules à charger, `KERNEL_DEBUG_INFO` (`yes` par défaut, pour décoder
un Oops ; `no` accélère la compilation et réduit les paquets), `KERNEL_DBG_PKG`.
Le track (`config/kernels/7.2.11-stable.conf`) : version, options forcées (`FORCE_BUILTIN`,
`FORCE_DISABLED`, `CONFIG_OVERRIDES`), correctifs appliqués.

---

## 🔍 Diagnostic

```bash
./diagnostics/check-system.sh          # tout
./diagnostics/check-system.sh --gpu    # GPU
./diagnostics/check-system.sh --cpu    # grappes CPU, fréquences, boost
./diagnostics/check-system.sh --pcie   # PCIe / NVMe / Ethernet
./diagnostics/check-system.sh --temp   # températures
```

Topologie CPU : cpu0 et cpu11 = A720 jusqu'à 2,6 GHz (boost) ; cpu1-4 = A520 1,8 GHz ;
cpu5-6, 7-8, 9-10 = A720 2,2 à 2,5 GHz.

---

## 📁 Structure du projet

```
bookworm-sky1-kernel-ubuntu/
├── bookworm-sky1-build.sh        # point d'entrée : téléchargement, patches, config, compilation
├── install-deps.sh               # dépendances apt
├── check-sky1-updates.sh         # surveillance linux-sky1 / kernel.org
├── distcc-env.sh                 # compilation distribuée (facultatif)
├── config/
│   ├── board.conf                # carte : cmdline, modules, debug info
│   ├── inject-sky1-config.sh     # injection de la config Sky1 dans la config Ubuntu
│   ├── kernels/7.2.11-stable.conf  # track : version, FORCE_BUILTIN/DISABLED, correctifs
│   ├── distros/                  # versions d'Ubuntu pour l'ISO (26.10, 26.04.1)
│   ├── sky1/config.sky1-next     # config Sky1 de référence (copie linux-sky1)
│   ├── udev/                     # USB-C et GPU : pas de veille runtime
│   ├── systemd/sleep.conf.d/     # veille système bloquée
│   ├── systemd/system/ cpufreq/  # gouverneur CPU (sky1-cpufreq-tune.service), kdump, geoclue (*.service.d)
│   ├── systemd/user/ vlc/        # VLC en sortie ALSA (service utilisateur)
│   ├── environment.d/            # décodeurs V4L2 hors autoplug GStreamer, GTK sans offload, mutter en GLES
│   ├── pipewire/ wireplumber/ alsa-card-profile/  # audio DP/HDMI
│   ├── grub/07_sky1              # entrées GRUB Sky1 (disque détecté par update-grub)
│   ├── kernel/                   # hook : DTB par noyau dans /boot/dtb
│   ├── initramfs-tools/          # hook : règles udev dans l'initrd du live (ISO)
├── patches/
│   ├── sky1-7.2/                 # série Sky1 portée sur 7.2 (+ README des décisions)
│   ├── apply-sky1-patches.sh     # application stricte de la série
│   └── fixes/                    # correctifs locaux 9xxx et fixes DTS/pilotes (.py)
├── firmware/                     # README.md seul : origine et licences des firmwares (aucun binaire)
├── dracut/sky1.conf              # initramfs
├── install/install.sh            # installation : paquet de réglages + paquets du noyau
├── packaging/build-settings-deb.sh  # paquet bookworm-sky1-settings (tous les réglages système)
├── iso/build-iso.sh              # ISO d'installation : ISO Ubuntu officielle + noyau Sky1
├── diagnostics/                  # check-system.sh (vérification après boot), video-diag.sh, audio-*.sh (son HDMI),
│                                 # vpu-seek-test.py, reset-watch.py, blackbox.sh
├── scripts-addons/               # bookworm-clone.sh (clonage contrôlé), set-locale.sh, usb-rebind-bus10, bookworm-vpu-encode
├── tools/portage-sky1/           # outils pour porter la série sur un nouveau noyau
├── docs/                         # notes matériel, astuces, guide de clonage
└── LICENSE                       # GPL-2.0
```

---

## 📊 Performances GPU

Avec les réglages actuels (track `7.2.11-stable`, gouverneur réglé), **glmark2-es2-wayland ≈ 2880** en
HDMI seul (détail dans les deux tableaux suivants). Mesures de départ, avec la config d'Ubuntu d'origine :
Ubuntu 26.10, noyau 7.2.11-sky1-custom, Mesa 26.2.4 (panfrost GLES 3.1 / panvk Vulkan 1.4),
session GNOME Wayland (HDMI 4K + DP 1440p), le 2026-10-16 :

| Test | Résultat |
|------|----------|
| glmark2-es2-wayland (800×600, défaut) | 1743 |
| glmark2-es2-wayland (1920×1080) | 1434 |
| vkmark (Wayland) | 2641 |

Pour comparaison, sous Gentoo (6.18/6.19, Mesa 25.x/26.1) : glmark2-es2-drm ~3079,
glmark2-es2-wayland 2982, Vulkan Buffer Fill/Copy (256 Mo) 37,4 / 21,4 Go/s, kmscube ~60 fps (vsync).

### Config du noyau : horloge et préemption

Le 1743 ci-dessus venait du double écran ; en HDMI seul, la config Ubuntu donne ~2140. Une bisection
(2026-10-17, glmark2-es2-wayland 800×600, HDMI seul) a montré que l'essentiel de l'écart venait de
l'horloge et de la préemption du noyau Ubuntu (1000 Hz, `NO_HZ_FULL`, préemption dynamique « lazy ») :

| Config | glmark2 |
|---|---|
| Ubuntu | ~2140 |
| + horloge 250 Hz et préemption classique (Gentoo) | ~2508 (**+17 %**) |
| + UBSAN coupé | ~2514 |
| + `init_on_alloc=0 hardened_usercopy=off` (au boot) | ~2561 |
| tous les durcissements Ubuntu coupés (config Gentoo) | ~2645 |

Le track `7.2.11-stable` prend l'horloge et la préemption Gentoo et coupe UBSAN (sans coût, outil de
détection de bugs). **Les autres durcissements Ubuntu sont gardés** : ils coûtent ~5 % au total.
Qui préfère ~2 % de plus contre un peu de sécurité peut ajouter `init_on_alloc=0 hardened_usercopy=off`
à la ligne `linux` de l'entrée GRUB (`randomize_kstack_offset=off` n'apporte rien).

### Gouverneur CPU

Le pilote GPU envoie son travail par rafales courtes. Avec son seuil d'origine (95 % de charge),
`ondemand` ne monte jamais en fréquence et freine le GPU. Le paquet de réglages installe
`sky1-cpufreq-tune.service`, qui garde `ondemand` mais le règle pour suivre ces rafales :

| Gouverneur | glmark2 |
|---|---|
| `ondemand` d'origine (seuil 95 %) | ~2510 |
| **`ondemand` réglé 30 / 50 (défaut installé)** | **~2881** |
| `performance` (CPU toujours au maximum) | ~2942 |
| Gentoo, en `performance` (référence) | 2982 |

Le CPU redescend environ 0,4 s après la dernière rafale : l'économie au repos est gardée.
Pour passer en `performance` (ou changer les seuils), modifier `/etc/default/sky1-cpufreq` puis
`sudo systemctl restart sky1-cpufreq-tune`. `cpupower` ne fonctionne pas sous Ubuntu avec ce noyau
(il demande un paquet `linux-tools-<version>` qui n'existe pas pour un noyau maison) :
le service écrit directement dans `/sys/devices/system/cpu/cpufreq/`.
Détails : `docs/notes-materiel.md` §14.

---

## 🙏 Crédits

| Projet | Contribution |
|--------|-------------|
| [Sky1-Linux](https://github.com/Sky1-Linux/) | Patches noyau CIX CD8180, config |
| [visorcraft/orange-pi-6-plus-gpu](https://github.com/visorcraft/orange-pi-6-plus-gpu) | Rétro-ingénierie de l'alimentation GPU |
| [ARM Ltd](https://developer.arm.com) | Firmware Mali CSF |
| [CIX Technology](https://www.cixtech.com) | SoC CD8180, firmwares VPU (`cix-vpu-firmware`, [dépôt APT](https://archive.cixtech.com/debian)) |

## Remerciements

Ce projet a été développé en collaboration avec Claude (Anthropic), qui a participé au pipeline, aux
corrections de patches noyau, aux fixes DTS et pilotes, au portage vers Ubuntu 26.10 et 26.04.1 LTS, au
portage de la série Sky1 sur Linux 7.2 et aux ISO d'installation.

Un grand merci à l'équipe Sky1-Linux pour son travail de portage vers le noyau mainline !

## 📜 Licence

Les scripts, la configuration et la documentation de ce dépôt sont distribués sous la
**GNU General Public License, version 2** (GPL-2.0-only), texte complet dans [`LICENSE`](LICENSE).

- Les patches noyau (`patches/`) gardent la licence indiquée dans chaque fichier qu'ils ajoutent ou
  modifient (GPL-2.0 pour l'essentiel, parfois double licence GPL-2.0 / BSD), comme le noyau Linux.
- Le dépôt ne contient aucun firmware binaire : chacun vient du paquet de son auteur, avec sa propre
  licence (voir [`firmware/README.md`](firmware/README.md)).

## 📺 BOOKWORM

Ce projet fait partie de la chaîne **BOOKWORM** : rendre les technologies open-source complexes
accessibles à tous.

- 🎬 YouTube : [@kennyTech73](https://www.youtube.com/@kennyTech73)

---

*Premier boot Gentoo 6.19 Sky1 sur OrangePi 6 Plus — 13 avril 2026* 🚀
*Premier boot Gentoo 7.0 Sky1 sur OrangePi 6 Plus — 19 avril 2026* 🚀
*Premier boot Ubuntu 26.10 sur noyau Sky1 7.0 — 16 octobre 2026* 🚀
*Série Sky1 portée sur Linux 7.2.11, premier boot du premier coup — 16 octobre 2026* 🚀
