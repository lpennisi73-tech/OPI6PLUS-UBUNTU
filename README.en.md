# BOOKWORM Sky1 Kernel Builder

🇫🇷 [Français](README.md) | 🇬🇧 English

### OrangePi 6 Plus — CIX CD8180 — Ubuntu 26.10 ARM64

[![Kernel](https://img.shields.io/badge/Kernel-7.2.12--sky1-blue)](https://www.kernel.org)
[![GPU](https://img.shields.io/badge/GPU-Mali--G720%20Panthor-green)](https://github.com/visorcraft/orange-pi-6-plus-gpu)
[![Board](https://img.shields.io/badge/Board-OrangePi%206%20Plus-orange)](http://www.orangepi.org)
[![OS](https://img.shields.io/badge/OS-Ubuntu%2026.10%20%7C%2026.04.1%20LTS-E95420)](https://ubuntu.com)
[![Status](https://img.shields.io/badge/Status-Validated%20✓-brightgreen)]()

> This is a translation of the French [README.md](README.md), which is the reference: if the two differ,
> the French version is right. The project's other documents (`docs/`, script messages) are in French.

> Build and install a complete Linux 7.2.12 kernel for the OrangePi 6 Plus on Ubuntu 26.10:
> Mali-G720 GPU, dual DP + HDMI displays with sound, 10 Gb/s USB-C, NPU, VPU, 2.6 GHz CPU boost.
> Born on Gentoo (April 2026), ported to Ubuntu and to Linux 7.2 by BOOKWORM/Kenny in October 2026.

---

## 🎯 Result

```
panthor 15000000.gpu: [drm] Using ACE-Lite bus coherency (Sky1)
[drm] Initialized panthor 1.8.0 for 15000000.gpu on minor 1
trilin-dptx-cix 141b4000.dp: main link training done! rate:540000 lanes:4
usb 16-1: new SuperSpeed Plus Gen 2x1 USB device number 2 using xhci-hcd
```

| Feature | Status on 7.2.12 |
|---|---|
| NVMe boot (PCIe Gen4), devicetree | ✅ |
| Mali-G720 GPU (panthor 1.8.0, Vulkan, ACE-Lite coherency) | ✅ |
| HDMI 3840×2160 + DP 2560×1440 10-bit, at the same time | ✅ |
| Sound over HDMI and DP (PipeWire, Pro Audio profile) | ✅ |
| USB-C data 10 Gb/s (Type-C rts5453, orientation handled), USB-A | ✅ |
| 12-core CPU, SCMI cpufreq, 2.6 GHz boost | ✅ |
| 2× Ethernet RTL8126 (5 GbE) | ✅ |
| 2 M.2 NVMe slots (SSD1, SSD2) + M.2 Wi-Fi | ✅ |
| NPU (`/dev/aipu`, 3 cores), VPU (`/dev/video0-1`, decode/encode) | ✅ |
| RTC (rx8900), SCMI temperature sensors | ✅ |
| Displays off / back on (HDMI sound kept) | ✅ |
| Memory dump after a kernel crash (kdump) | ✅ |
| **System sleep (suspend)** | ❌ no wake-up, disabled (see Limitations) |

---

## 📋 Requirements

| Component | Details |
|-----------|--------|
| Board | Orange Pi 6 Plus |
| SoC | CIX CD8180 (Sky1): 4× Cortex-A520 + 8× Cortex-A720 |
| RAM | 32 GB LPDDR5 |
| GPU | Mali-G720 Immortalis MC10 |
| Storage | NVMe SSD |
| Firmware | **CIX BIOS 1.4** (the only tested version, recommended), **Secure Boot disabled** (unsigned kernel) |
| System | Ubuntu 26.10 arm64 installed and booted (stock Ubuntu `-generic` kernel) |

BIOS version (readable with the Ubuntu kernel as well as with the Sky1 kernel):
```bash
cat /sys/class/dmi/id/bios_version     # 1.4
```
The project has not been tested with any other version: better update the BIOS to 1.4 first. The BIOS is
on the [official Orange Pi 6 Plus support page](http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/service-and-support/Orange-Pi-6-Plus.html)
(files hosted by Orange Pi on Google Drive).

The stock Ubuntu kernel boots the board in ACPI mode, without GPU, cpufreq or DP/HDMI: it serves as the
configuration base and as the fallback kernel. The Sky1 kernel boots in devicetree mode.

```bash
# Build dependencies (apt) — once
sudo ./install-deps.sh            # --check to only list what is missing
sudo ./install-deps.sh --with-diag   # optional: glxinfo, vulkaninfo, v4l2-ctl, nvme-cli…
```

Recommended: make the GRUB menu visible (in `/etc/default/grub`, `GRUB_TIMEOUT_STYLE=menu` and
`GRUB_TIMEOUT=15`, then `sudo update-grub`) so that you can pick another kernel if something goes wrong.
The scripts never modify `/etc/default/grub`.

---

## 🚀 Quick start

```bash
git clone https://github.com/lpennisi73-tech/OPI6PLUS-UBUNTU.git bookworm-sky1-kernel-ubuntu
cd bookworm-sky1-kernel-ubuntu
sudo ./install-deps.sh                      # dependencies, once
sudo ./bookworm-sky1-build.sh --install     # build + install (~1 h 20)
sudo reboot
./diagnostics/check-system.sh               # after the reboot
```

The detailed procedure follows. To install Ubuntu directly with the Sky1 kernel, ready-to-use ISOs will be
on [www.bookworm-mon0.org/downloads.php](https://www.bookworm-mon0.org/downloads.php)
**from Monday 2 November 2026** (see [Installation ISO](#-installation-iso)).

---

## 📖 Detailed procedure: build and install the kernel

### 1. Before you start

- Ubuntu 26.10 arm64 installed and booted on the board, with the Ubuntu `-generic` kernel (used as the
  configuration base and as the fallback); **CIX BIOS 1.4** (`cat /sys/class/dmi/id/bios_version`) and
  **Secure Boot disabled** in the BIOS (the kernel is not signed).
- **Disk space**: ~25 GB free under `/usr/src/build` (sources, objects, packages).
- **Duration** (Orange Pi 6 Plus, 12 cores): ~1 h 20 locally, ~1 h with distcc; `--no-dbg` saves ~16 min.
- Run the build in a session that survives a logout or a GNOME crash (otherwise the build dies with the
  terminal): `screen` (installed with Ubuntu), `tmux`, an SSH connection, or a systemd service, which
  depends on no session at all:
  ```bash
  sudo systemd-run --unit=sky1-build --working-directory="$PWD" bash -c './bookworm-sky1-build.sh --install --no-dbg'
  journalctl -fu sky1-build        # follow the build (Ctrl+C only stops the display)
  ```
  With distcc: `bash -c 'source ./distcc-env.sh && ./bookworm-sky1-build.sh --install --no-dbg'`.
  At the end, `systemctl status sky1-build` shows the exit code.
- Recommended: visible GRUB menu, so you can go back to the Ubuntu kernel if needed. In
  `/etc/default/grub`: `GRUB_TIMEOUT_STYLE=menu` and `GRUB_TIMEOUT=15`, then `sudo update-grub`.
  The scripts never modify this file.

### 2. Get the repository and the dependencies

```bash
git clone https://github.com/lpennisi73-tech/OPI6PLUS-UBUNTU.git bookworm-sky1-kernel-ubuntu
cd bookworm-sky1-kernel-ubuntu
./install-deps.sh --check          # lists what is missing, installs nothing
sudo ./install-deps.sh             # installs what is missing (asks for confirmation; --yes to skip it)
```

| `install-deps.sh` option | Adds |
|---|---|
| (none) | kernel and package building, sources, installation |
| `--with-diag` | diagnostic tools: glxinfo, vulkaninfo, glmark2, v4l2-ctl, nvme-cli |
| `--with-distcc` | distcc (distributed compilation, step 3) |
| `--with-iso` | xorriso, squashfs-tools, mtools, dosfstools (installation ISO) |

### 3. Optional: distributed compilation (distcc)

An x86_64 PC on the network compiles instead of the board (compilation goes from ~60 to ~30 min;
linking and packaging stay on the board).

- **On the server**: `distccd` allowed for the local network, and the cross compiler
  `gcc-<same version>-aarch64-linux-gnu`. The gcc version must be **exactly** the board's
  (`aarch64-linux-gnu-gcc --version`): otherwise the kernel mixes objects from two compilers.
- **On the board**: `sudo ./install-deps.sh --with-distcc`, then create `distcc-env.local` (not versioned)
  with the server address and the number of jobs:
  ```bash
  cat > distcc-env.local << 'EOF'
  DISTCC_HOST="192.168.1.50"   # server address
  DISTCC_HOST_JOBS=16          # one job per server core
  DISTCC_LOCAL_JOBS=4
  EOF
  ```
- Before the build, in the same terminal:
  ```bash
  source distcc-env.sh      # checks the server's gcc version and prints « identique » (identical)
  ```
  As the build runs as root, keep the environment: `sudo -E ./bookworm-sky1-build.sh …`
  (or run everything from a root shell: `sudo -i`, `cd`, `source distcc-env.sh`, build).

### 4. Run the build

```bash
screen                                      # optional but recommended (or systemd-run, step 1)
sudo ./bookworm-sky1-build.sh --install     # or --install --no-dbg
```

Without `--install`, the build stops after the packages; installation is then done in step 5.

| `bookworm-sky1-build.sh` option | Effect |
|---|---|
| `--kernel <track>` | track to build, `config/kernels/<track>.conf` (default: `7.2.12-stable`) |
| `--install` | runs `install/install.sh` after the build |
| `--no-dbg` | does not build the `-dbg` package (~16 min and 1.7 GB less; the `vmlinux` with symbols stays in the build tree to decode an Oops). Permanent: `KERNEL_DBG_PKG="no"` in `config/board.conf` |
| `--jobs <n>` | number of parallel compile jobs (default: number of cores, or `SKY1_JOBS` from distcc-env.sh) |
| `--base-config <file>` | starting config (default: the most recent `/boot/config-*-generic`) |
| `--build-dir <dir>` | build directory (default: `/usr/src/build/sky1-kernel`) |
| `--skip-download` | no network access: the tarball must be present; the tree is recreated from the tarball if it was deleted |
| `--skip-patches` | do not apply the patches (sources already patched) |
| `--skip-config` | keep the existing `.config` |
| `--skip-build` | do not compile (e.g. only install with `--install`) |
| `--dry-run` | show the steps without running anything |

The build shows 6 steps (details below) and logs everything to `logs/build-<date>_<time>.log` (in the
repository). At the end, it lists the packages produced in `/usr/src/build/sky1-kernel/`:
`linux-image-7.2.12-sky1-custom_7.2.12-<n>_arm64.deb`, `linux-headers-…`, `linux-image-…-dbg` (unless
`--no-dbg`) and `linux-libc-dev` (**do not install it**: it would replace Ubuntu's). The number
`<n>` increases with each build in the same tree and goes back to 1 in a fresh tree.

### 5. Install (if the build ran without `--install`)

```bash
sudo install/install.sh --kernel 7.2.12-stable
```

| `install.sh` option | Effect |
|---|---|
| `--kernel <track>` | installed track (required unless `--kernel-dir` is given) |
| `--kernel-dir <dir>` | build tree (default: `/usr/src/build/sky1-kernel/linux-<version>`) |
| `--deb-dir <dir>` | directory of the `.deb` files (default: parent of the build tree) |
| `--with-dbg` | also installs the `-dbg` package from the same build (symbols for crash/kdump) |
| `--no-firmware` | do not install CIX's VPU firmware (`cix-vpu-firmware`) |

**Before rebooting**, check that the Sky1 entry exists and comes first:
```bash
grep -n "^menuentry" /boot/grub/grub.cfg | head -3     # 1st line: "Sky1 Orange Pi 6 Plus - 7.2.12-sky1-custom (GPU+NPU)"
ls /boot/vmlinuz-7.2.12-sky1-custom /boot/initrd.img-7.2.12-sky1-custom /boot/dtb/
```

### 6. Reboot and check

```bash
sudo reboot
```
The GRUB menu boots "Sky1 Orange Pi 6 Plus - … (GPU+NPU)" by default. If this kernel does not boot:
reboot and pick the **Ubuntu** entry (stock kernel, always installed); the Sky1 kernel messages are also
sent to the `ttyAMA2` serial console (115200 baud).

Once on the desktop:
```bash
uname -r                                # 7.2.12-sky1-custom
./diagnostics/check-system.sh           # GPU, CPU, PCIe/NVMe, temperatures…
journalctl -k -b -p warning             # kernel warnings
```
Session settings (`/usr/lib/environment.d`) are only read when the user session manager starts: after a
first run of install.sh, a **reboot** is needed, logging out is not enough.

### 7. Resume, rebuild, start from scratch

| Situation | Command |
|---|---|
| The build failed (error fixed since) | `sudo ./bookworm-sky1-build.sh --skip-download --skip-patches --skip-config --install` |
| Change a config option and rebuild | edit the track or `board.conf`, then `sudo ./bookworm-sky1-build.sh --skip-download --install` |
| Start from scratch (new patch series, doubtful tree) | `sudo rm -rf /usr/src/build/sky1-kernel/linux-7.2.12` then `sudo ./bookworm-sky1-build.sh --skip-download --install` |
| Reinstall the same kernel / update the settings only | `sudo install/install.sh --kernel 7.2.12-stable` |

Patched sources carry the `.sky1-patched` marker: a re-run never re-applies the patches to an already
patched tree (they cannot be applied twice); to re-patch, delete the tree.

### 8. Uninstall

```bash
sudo apt remove linux-image-7.2.12-sky1-custom     # the kernel (its DTB and GRUB entry go with it)
sudo apt remove linux-headers-7.2.12-sky1-custom   # only after a build: not present on a system installed from the ISO
sudo apt purge bookworm-sky1-settings              # all Sky1 settings
```
Before removing the last Sky1 kernel, boot the Ubuntu kernel. Removing the latest kernel also removes the
`linux-image-sky1` meta-package that depends on it (see [staying up to date](#-after-installation-staying-up-to-date)).

### Under the hood: what the build does (`bookworm-sky1-build.sh`)
1. downloads `linux-7.2.12.tar.xz` from kernel.org and extracts it;
2. applies the repository's **Sky1 series** (`patches/sky1-7.2/`, 49 patches) in **strict mode** (no fuzz);
3. applies the **local fixes** `patches/fixes/9xxx-*.patch`;
4. applies the **DTS / driver fixes** `patches/fixes/*.py` (empty PCIe slot, thermal zones…);
5. takes the most recent Ubuntu `-generic` kernel config, injects the Sky1 config
   (`config/sky1/config.sky1-next`), forces the required options (`FORCE_BUILTIN`, `FORCE_DISABLED`
   of the track) and checks that `olddefconfig` did not undo them;
6. compiles and builds the packages, then runs `install/install.sh` with `--install`.

Patched sources are marked `.sky1-patched`: a re-run does not re-patch. To start from scratch,
delete `/usr/src/build/sky1-kernel/linux-7.2.12`.

### Under the hood: what the installation does (`install/install.sh`)
1. builds and installs the **`bookworm-sky1-settings`** package
   (`packaging/build-settings-deb.sh`, see below);
2. installs the kernel packages: the dracut hook generates the initramfs, the settings package hook
   copies the DTB (`/boot/dtb/sky1-orangepi-6-plus-<version>.dtb`) and `update-grub` adds the Sky1 entry;
   along with them, the **`linux-image-sky1`** meta-package (and `linux-headers-sky1`), built by
   `packaging/build-meta-deb.sh` in the same folder: it always depends on the latest Sky1 kernel;
3. VPU firmware: CIX's official `cix-vpu-firmware` package, downloaded once from CIX's repository and
   checked against its hash (`packaging/fetch-cix-firmware.sh`); the Mali GPU firmware comes from
   Ubuntu (`linux-firmware`) and is only checked; ALSA → PipeWire links checked.

Older versions of install.sh copied the settings into `/etc`: on the first run, copies identical to the
repository are removed (the package provides the same thing), a modified copy is kept.

### Under the hood: the `bookworm-sky1-settings` package
All Sky1 system settings, installed as an Ubuntu package (same idea as the `ubuntu-x1e-settings`
packages of Snapdragon laptops). Defaults go under `/usr`; a file with the same name in `/etc` takes
precedence. Contents:
- `/etc/grub.d/07_sky1`: one entry per Sky1 kernel (devicetree + `acpi=off`, plus a Recovery entry),
  **the most recent one boots by default**; the disk is detected by `update-grub`, nothing is hard-coded;
- `/etc/default/bookworm-sky1`: Sky1 kernel parameters (taken from `KERNEL_CMDLINE`, `config/board.conf`);
- hook `/etc/kernel/post{inst,rm}.d/zz-bookworm-sky1-dtb`: one DTB per kernel, added or removed with it;
- dracut config, modules loaded at boot and options (`MODULES_AUTOLOAD`, `MODPROBE_OPTIONS`);
- USB-C and GPU udev rules, suspend blocking, session environment, PipeWire/WirePlumber;
- CPU governor tuned for the desktop (`sky1-cpufreq-tune.service`, settings in `/etc/default/sky1-cpufreq`,
  only started on the Sky1 entry);
- VLC on ALSA output (user service, once per user);
- kdump crash kernel adapted to the board (if `kdump-tools` is installed, see GRUB below).

Version: `1.1.<n>`, where `<n>` counts the commits touching the package's files (`PKG_SOURCES` list in
`packaging/build-settings-deb.sh`): a documentation commit does not change the version. Versions
`1.0.x` (until 21 October 2026) counted all commits; `1.1.x` replaces them normally on upgrade.

Where to find the files (full list: `dpkg -L bookworm-sky1-settings`):

| Setting | Package files | To change it |
|---|---|---|
| Session (GNOME, GTK, GStreamer) | `/usr/lib/environment.d/90-sky1-*.conf` | same name in `/etc/environment.d/` (or `~/.config/environment.d/`) |
| udev (GPU, USB-C) | `/usr/lib/udev/rules.d/90-sky1-*.rules` | same name in `/etc/udev/rules.d/` |
| Suspend | `/usr/lib/systemd/sleep.conf.d/90-sky1-no-suspend.conf` | `/etc/systemd/sleep.conf.d/` |
| Sound | `/usr/share/wireplumber/wireplumber.conf.d/5*-sky1-*.conf`, `/usr/share/pipewire/pipewire-pulse.conf.d/`, `/usr/share/alsa-card-profile/mixer/profile-sets/sky1-hdmi-dp.conf` | `/etc/wireplumber/wireplumber.conf.d/` |
| Modules, dracut | `/usr/lib/modules-load.d/`, `/usr/lib/modprobe.d/`, `/usr/lib/dracut/dracut.conf.d/` (`bookworm-sky1*`) | same name in `/etc/…` |
| VLC (ALSA output) | `/usr/libexec/bookworm-sky1/sky1-vlc-aout`, user service `bookworm-sky1-vlc-aout` | in VLC (*Preferences → Audio*): your choice is never touched again |
| kdump (crash kernel) | `/usr/lib/systemd/system/kdump-tools.service.d/90-bookworm-sky1.conf` | `KDUMP_CMDLINE_APPEND` in `/etc/default/kdump-tools` |
| geoclue (without libproxy) | `/usr/lib/systemd/system/geoclue.service.d/90-bookworm-sky1.conf` | same name in `/etc/systemd/system/geoclue.service.d/` |
| GRUB, cpufreq, DTB | `/etc/grub.d/07_sky1`, `/etc/default/bookworm-sky1`, `/etc/default/sky1-cpufreq`, `/etc/kernel/post*.d/zz-bookworm-sky1-dtb` | these files directly (kept on upgrades) |

`/etc/environment.d/` therefore normally contains no Sky1 settings. To check that they are active:
`systemctl --user show-environment | grep -E 'COGL|GDK_DISABLE|GST_PLUGIN'`.

Remove everything: `sudo apt purge bookworm-sky1-settings`.

The stock Ubuntu kernel stays installed and keeps its GRUB entry: it is the fallback.

---

## 🖥️ Kernel track

| Track | Base | Status |
|-------|------|--------|
| `7.2.12-stable` | Linux 7.2.12 (kernel.org maintained stable) | ✅ **Default, validated on 23 October 2026** |

kernel.org stable updates are followed: 7.2.12 came out on 21 October 2026, its track was validated on
23 October (Sky1 series unchanged: no file in common with the 7.2.12 fixes) and published on the BOOKWORM
APT repository ([staying up to date](#-after-installation-staying-up-to-date)).
First Ubuntu version: 7.2.11, validated on 16 October 2026.

The [Sky1-Linux/linux-sky1](https://github.com/Sky1-Linux/linux-sky1) project, where the patch series
comes from, has been inactive since 28 February 2026 (series for Linux 7.0). The series was **ported to
Linux 7.2** in this repository (`patches/sky1-7.2/`, patch-by-patch decisions in its `README.md`):

- 43 Sky1-Linux patches, 11 of them adapted to Linux 7.2 changes;
- `0044` (BOOKWORM): vendor drivers adapted to the Linux 7.2 APIs;
- `0045` (BOOKWORM): ghost display, VPU firmware cache, two kernel warnings;
- `0046` (BOOKWORM): VPU stuck when a player seeks in the video while it is starting;
- `0047` (BOOKWORM): HDR hidden (enabling it crashed the kernel and GNOME);
- `0048` (BOOKWORM): HDMI sound lost when the display wakes up (full reset of the DP controller);
- `0049` (BOOKWORM): a hung GPU is recovered through its reset line instead of being lost until reboot.

The reference Sky1 config is copied into `config/sky1/`: the build no longer depends on linux-sky1.
To port the series to a later version (7.3…), see `tools/portage-sky1/README.md`.
`./check-sky1-updates.sh` watches linux-sky1 and kernel.org.

The Gentoo tracks `6.18.14-lts`, `6.19-latest` and `7.0-next` were removed in October 2026 (see the
git history).

---

## 🔧 Problems solved for Ubuntu and Linux 7.2

| Problem | Cause | Fix |
|---|---|---|
| NVMe not found at boot (`sky1-pcie … -110`) | SCMI/regulator providers built as modules in the Ubuntu config, missing from the initramfs | forced `=y` (`FORCE_BUILTIN`) |
| Build error in `pcie-cadence-plat.c` | `PCIE_CADENCE_PLAT_EP=y` (Ubuntu) re-enables `PCIE_CADENCE_PLAT` | `FORCE_DISABLED` |
| USB-C ports without USB, no RTC | `I2C_CADENCE` missing from the Ubuntu config: no I2C bus, so neither rts5453 nor rx8900 | `FORCE_BUILTIN` + `rtc-rv8803` loaded at boot |
| USB-C disk never detected | the USB-C controller and its xHCI go to sleep before enumeration and never wake up | `config/udev/90-sky1-typec-usb-pm.rules` |
| USB-C port 0 dead at boot (`timeout waiting for xhci_ready`, burst of `arm-scmi … timed out`) | the controller starts in the initramfs and goes to sleep before the udev rule applies | `90-sky1-*.rules` rules in the initramfs too (dracut `install_items`, initramfs-tools hook) |
| Installer crash report when clicking "Restart" | `zpool export -a` fails: no ZFS module in the Sky1 kernel | `zpool` wrapper in the ISO live system (`/usr/local/sbin/zpool`) |
| Frozen desktop, session impossible to stop (`Failed to stop MCU`, processes in D state) | GPU runtime suspend fails and panthor deadlocks between suspend and reset | `config/udev/90-sky1-gpu-pm.rules` (GPU kept awake) |
| GPU lost under load, session restarted without acceleration (`job timeout`, `CSG … update request timedout`) | the GPU drops out when going through the 72 / 216 MHz frequencies added by the firmware (outside the CIX levels) | `config/udev/90-sky1-gpu-pm.rules` (350 MHz minimum) |
| After a GPU hang, "Failed to boot MCU after reset, making device unusable": desktop in software rendering until reboot | the soft reset does not restart the GPU microcontroller (MCU) | patch `0049`: reset through the GPU reset line, then firmware restart (`panthor.sky1_hard_reset`, on by default) |
| Display driver contended at boot | Linux 7.2: `komeda` also matches the Sky1 display | `DRM_KOMEDA` disabled |
| 2nd "Unknown" display in GNOME | the firmware framebuffer (simpledrm) was never removed | patch `0045` (linlon-dp) |
| Kernel trace when playing a video | missing VPU firmware + driver bug in that case (use after free) | `cix-vpu-firmware` package + patch `0045` |
| GNOME video player: frozen green picture | display of VPU frames in GTK4 | CPU decoding for the desktop (`config/environment.d/`) |
| Showtime closes when going fullscreen (`drmPrimeHandleToFD() failed`, `Error 9`) | GTK4 graphics offload exports a private GPU buffer, which panthor refuses | `GDK_DISABLE=offload` (`config/environment.d/90-sky1-gtk-offload.conf`) |
| Video stutters when opening notifications or the system menu | in desktop OpenGL, gnome-shell uploads its BGRA images as RGBA8 and Mesa converts every pixel on the CPU | gnome-shell on OpenGL ES: `COGL_DRIVER=gles2` (`config/environment.d/90-sky1-mutter-gles.conf`) |
| Choppy sound in VLC | DP/HDMI outputs at 85 ms per block, Pulse client buffers too small | `config/pipewire/pipewire-pulse.conf.d/` (+ VLC on ALSA output, see below) |
| 7.0 GRUB entry before the 7.2 one | alphabetical order of `/etc/grub.d` | `/etc/grub.d/07_sky1` sorts Sky1 kernels by version |
| 6 bits per colour after the display bounces on wake-up (`info_format=0, force support RGB444`) | the modeset forced after the bounce ran before the EDID was read again, while GNOME had cleared it during the 2 s "unplugged" | `9007` re-reads the EDID before the modeset ("HPD bounce: EDID re-read, bpc=…") |
| `geoclue` failing at boot (`start operation timed out`, 90 s) | deadlock in GIO when geoclue starts: the libproxy module, loaded under the modules lock, waits for an initialisation the main thread cannot finish | "dummy" proxy resolver for geoclue: `/usr/lib/systemd/system/geoclue.service.d/90-bookworm-sky1.conf` |
| `cros-ec-i2c 6-0076: Cannot identify the EC: error -71` at every boot | EC node inherited from the CIX reference board (a laptop: battery, lid, keyboard); no such EC on the Orange Pi 6 Plus | node disabled (`dts-disable-cros-ec.py`) |

Fixes from the Gentoo days, still applied: SError on empty PCIe slot (`pci-sky1-link-down-guard.py`),
SCMI boost from boot (`9004`), black screen on HDMI wake-up (`9007`), DP/HDMI sound (`9001`, `9009`),
VPU (`9002`, `9003`), Cadence USB (`9005`, `9008`).

All PCIe slots of the board are active: both M.2 slots for NVMe SSDs ("SSD1" `a070000`, "SSD2"
`a010000`), the M.2 Wi-Fi slot (`a0d0000`) and both 5G Ethernet ports. An empty slot is reported at boot
with `PCIe link down, slot may be empty`, without error. The old Gentoo fix that disabled SSD1 and Wi-Fi
in the DTS was removed (2026-10-21): it made a 2nd SSD or an M.2 Wi-Fi card invisible.

---

## ⚠️ Known limitations

### Black screen at boot (BIOS and HDMI)
Known CIX BIOS bug: at boot, sometimes **nothing shows up on the HDMI display** (no logo, no menu). The
board is not broken: press **Ctrl+Alt+Del** to restart it, the picture usually comes back on the next
boot. Repeat if needed.

### System sleep: disabled
Neither `deep` nor `s2idle` wakes up on this board (keyboard, mouse, power button, RTC alarm): the power
has to be cut. `config/systemd/sleep.conf.d/90-sky1-no-suspend.conf` therefore blocks suspend (GNOME
hides "Suspend"). **Turning the displays off works** normally. Diagnosis planned with the serial console
(`ttyAMA2`, 115200 baud).

### HDR: disabled
Enabling HDR in *Settings → Displays* crashed the kernel and the GNOME session. Since patch 0047, the DP
driver no longer exposes the HDR properties (`Colorspace`, `HDR_OUTPUT_METADATA`): GNOME no longer shows
the option. 10-bit output stays available. To test HDR anyway (at your own risk): kernel parameter
`trilin_dpsub.hdr=1`.

### HDMI sound that disappears until reboot
Now and then, the audio FIFO of the DP controller that drives the HDMI output gets stuck, within the
second after a sound starts (about once every 5 to 25 openings of the output, measured with
`diagnostics/audio-stress-test.sh`). Sound then stays off; only a reboot brings it back (re-plugging the
cable, reloading the sound card or the I2S: no effect). To avoid it, the DP and HDMI outputs stay open
permanently (they send silence): the FIFO only starts once per session instead of with every sound.

Even with the outputs open, it still happened when the display woke up (off then on, often followed by a
display disconnect/reconnect): the DP link restarts while sound is already playing. Since patch 0048,
the driver then does a full reset of the DP controller, as at boot, and sound comes back. Can be changed
at runtime: `trilin_dpsub.audio_reset=0` turns it off. If sound disappears anyway: reboot.

### Video on the desktop: CPU decoding
The VPU decodes correctly (about 200 frames/s in 1080p H.264) and its frames display in GTK4, but the
GNOME player (Showtime) stays on a black screen: it resumes the video at the last position, and that
seek right after starting blocks the VPU. A first driver defect is fixed (patch `0046`); the second one
comes from CIX's firmware, which loses its context when the output queue is reallocated during decoding
(the GTK display keeps the last frame) and refuses the other way of doing it; VPU display on the desktop
also flickers (framebuffer image overlaid, stutters). `config/environment.d/90-sky1-gst-v4l2-rank.conf`
therefore removes the V4L2 decoders from GStreamer's automatic choice: players decode on the CPU,
without any trouble (a 1080p H.264 film plays without stutter). The CPU decoder comes from
`gstreamer1.0-libav`, which the installer only adds with the **"Install third-party software / codecs"**
box: tick it, or install it afterwards (`sudo apt install gstreamer1.0-libav`). Without it (live
session, installation without third-party codecs), GStreamer players cannot play H.264, as on stock
Ubuntu (VLC, which has its own codecs, works). The VPU can still be used explicitly:
```bash
gst-launch-1.0 filesrc location=video.mp4 ! qtdemux ! h264parse ! v4l2h264dec ! fakesink
```

### Showtime on Ubuntu 26.04.1: choppy video
On 26.04.1 only, the GNOME video player (Showtime) stutters, whatever the GTK renderer
(`GSK_RENDERER=gl` and `cairo` make no difference, `vulkan` fails): the defect is in 26.04.1's Showtime.
The system and the other players are smooth: **use VLC** (Ubuntu Software / App Center). On 26.10,
Showtime works perfectly.

### VLC: ALSA output by default
Even with correct buffers, VLC 3's PulseAudio output module makes the sound choppy at times on the DP/HDMI
outputs. With the ALSA output (which also goes through PipeWire), sound is clean, including AC-3 5.1.
The settings package sets it for each user, **only once**, at login (user service
`bookworm-sky1-vlc-aout`): `aout=alsa` is added to `~/.config/vlc/vlcrc` if no output is chosen there or
if it is set to "Automatic" (`aout=any`) (the file is created if it does not exist; VLC can be installed
before or after). A choice made later in *Tools → Preferences → Audio → Output module*, "Automatic"
included, is kept. To make the service run again: delete `~/.local/state/bookworm-sky1/vlc-aout.done`.
VLC as a snap (`~/snap/vlc/` folder) is not affected: set the output by hand.

### GPU hang: rare, recovered without rebooting
The GPU (panthor driver) could hang suddenly (`job timeout`, `CSG … update request timedout`,
`Failed to stop MCU` in `journalctl -k`): gnome-shell restarted with software rendering and only a reboot
brought the GPU back. **Cause found on 23 October 2026**: the firmware adds two frequencies (72 and
216 MHz) to the levels planned by CIX (350 to 1000 MHz), and the GPU drops out when going through them
under load. Reproduced on demand (`diagnostics/gpu-dvfs-stress.sh`): hang after 246 frequency changes with
all levels, none over 10,629 changes from 350 MHz up. Since `bookworm-sky1-settings` 1.1.38, the GPU udev
rule sets its minimum to 350 MHz (slightly higher idle power).

A rarer hang is still possible under very heavy load (seen once on 24 October with 4 videos played at the
same time; not reproduced on demand). Since kernel **7.2.12-2** (patch 0049), the GPU is no longer lost:
the driver resets it through its reset line and restarts its firmware (`Sky1: GPU recovered after a reset
through its reset line` in `journalctl -k`). gnome-shell does not survive losing its graphics context: the
session is restarted (back to the login screen, open applications closed), but with hardware
acceleration, without rebooting. If it happens to you, note the time and what you were doing.

### Other
- **Temperatures**: the firmware refuses to enable the SCMI sensors (`Error enabling sensor … err=-2`):
  they can be read (`sensors`), but there are no thermal zones and no kernel throttling.
- Harmless boot noise: SMMU faults of `141d0000.disp-controller` (firmware scanout),
  `sky1_timer … -2`, `SCMI protocol 129 not implemented`, `bpf-restrict-fs` (BTF disabled).
- **KVM on USB bus 10** (`9290000`): after switching, keyboard and mouse may disappear;
  `sudo scripts-addons/usb-rebind-bus10` resets this controller.
- The audio DSP firmware (CIX's `cix-audio-dsp` package) is not installed: nothing uses it. Sound goes
  straight through I2S and HDA; the DSP (`remoteproc0`, `cix-dsp-rproc`) does not start by itself and the
  device tree declares no SOF sound card that would use it.
- VPU encoding (`scripts-addons/bookworm-vpu-encode`): written for Gentoo's `ffmpeg-sky1`, not yet
  adapted to Ubuntu.

---

## 🔊 DP / HDMI audio

ALSA card `cix_sky1`: device 0 = DisplayPort, 1 = HDMI (Parade PS185HDM DP→HDMI converter on `dp4`).
The `bookworm-sky1-settings` package installs:
- `config/wireplumber/`: **Pro Audio** profile by default (without it, only DP is exposed), outputs named
  "DisplayPort" and "HDMI", **HDMI by default**, quantum forced to 4096 (sound is choppy at 1024);
- `config/alsa-card-profile/`: card profiles reduced to "Off" and "Pro Audio" (the generic profile
  offered a non-existent "Analog output" that made DP and HDMI disappear);
- `config/pipewire/pipewire-pulse.conf.d/`: PulseAudio application buffers aligned on that quantum;
- DP and HDMI outputs **never suspended or paused** (`session.suspend-timeout-seconds = 0`,
  `node.pause-on-idle = false`): see "HDMI sound that disappears" in the limitations above.

An audio profile already remembered by WirePlumber for a user (`~/.local/state/wireplumber/`) takes
precedence. GNOME's "Test" button does not work with the Pro Audio profile.

---

## 🖥️ GRUB, console, Recovery

- One entry per Sky1 kernel, created by `/etc/grub.d/07_sky1` on every `update-grub`: the kernel's
  devicetree, `acpi=off`, parameters from `/etc/default/bookworm-sky1`. The most recent one comes first =
  default entry with `GRUB_DEFAULT=0`. Ubuntu's automatic entry (`10_linux`) for the same kernel boots in
  ACPI mode, without devicetree: do not use it.
- **Ubuntu logo at boot (Plymouth)**: the normal entry takes `GRUB_CMDLINE_LINUX_DEFAULT` from
  `/etc/default/grub` (`quiet splash` on Ubuntu), like `10_linux`. To see the kernel messages instead,
  remove `quiet splash` from that line, then `sudo update-grub`.
- **Recovery** entry: `systemd.unit=rescue.target`, without `quiet splash` (kernel messages on screen).
- **`crashkernel=…`**: added to `GRUB_CMDLINE_LINUX_DEFAULT` by `kdump-tools`, which Ubuntu's installer
  enables when the machine has at least 6 GB of RAM and enough space in `/var` (5 × the RAM). It reserves
  memory for a crash kernel that saves a dump to `/var/crash` if the kernel crashes: about 640 MB on a
  16 GB board, 1.1 GB on 32 GB. The first boot after installing a kernel prepares its crash initrd (about
  45 s more, once). To remove it: `sudo apt purge kdump-tools linux-crashdump && sudo update-grub`. The
  ISO live system is not affected. The settings package adapts the crash kernel to the board
  (`/usr/lib/systemd/system/kdump-tools.service.d/90-bookworm-sky1.conf`): `cma=0` and GPU, NPU, VPU,
  display and DSP drivers excluded, without which it runs out of memory and writes nothing. A
  `KDUMP_CMDLINE_APPEND` value set in `/etc/default/kdump-tools` takes precedence.
- `console=ttyAMA2,115200 console=tty0`: messages on the serial console and on screen; text consoles
  (Ctrl+Alt+F3) available.
- Uninstall a kernel: `sudo apt remove linux-image-<version>` (and `linux-headers-<version>` if it is
  installed, after a build); its DTB and its GRUB entry go with it.

---

## 🌍 Language, keyboard, time zone (optional)

`scripts-addons/set-locale.sh` sets the system language, the keyboard (login screen, console) and the
time zone with `localectl` / `timedatectl`:
```bash
sudo ./scripts-addons/set-locale.sh --lang fr_CH --tz Europe/Zurich --dry-run   # simulation
sudo ./scripts-addons/set-locale.sh --lang fr_CH --tz Europe/Zurich
sudo ./scripts-addons/set-locale.sh --lang en_US --kbd ch:fr                    # English, Swiss keyboard
```
Existing GNOME sessions keep their own settings (Settings → Region & Language, Keyboard).

---

## 💿 Installation ISO

> **Unofficial**: this is not an official Ubuntu ISO, do not present it as such
> (firmware licences: see `firmware/README.md`).

**Ready-to-use ISOs: [www.bookworm-mon0.org/downloads.php](https://www.bookworm-mon0.org/downloads.php)**,
with their `.sha256` file, **available from Monday 2 November 2026** (they are not online before that
date). After downloading, check the ISO before writing it to a USB stick:
```bash
sha256sum -c ubuntu-*-bookworm-sky1-orangepi6plus-arm64-*.iso.sha256    # must print "OK"
```
then go straight to step 4 (write the ISO to a USB stick). Steps 1 to 3 are for building the ISO
yourself.

`iso/build-iso.sh` starts from an official Ubuntu ISO (never modified) and adds the Sky1 kernel and
`bookworm-sky1-settings`, both to the **live system** and to the system that the **Ubuntu installer**
copies to the disk. The ISO menu boots the Sky1 kernel by default (devicetree + `acpi=off`); the
original Ubuntu entry stays available. After installation, the disk has the same GRUB entries as with
install.sh (Sky1 by default, Ubuntu kernel as fallback).

### Choosing the Ubuntu version (`--distro`)

Like the kernel *tracks*, each Ubuntu version has its own `config/distros/<distro>.conf` file: official
ISO, download address, pinned SHA256 hash, name of the produced ISO.
`sudo iso/build-iso.sh --list-distros` lists them.

| `--distro` | Base | Ubuntu updates | Status |
|---|---|---|---|
| `ubuntu-26.10` (default) | Ubuntu 26.10 | 9 months (until July 2027) | validated (live + installation) |
| `ubuntu-26.04.1` | Ubuntu 26.04.1 LTS | 5 years (until April 2031) | validated (live + installation), see "Showtime on 26.04.1" |

The **Sky1 kernel, its settings and the VPU firmware are the same** whatever the version: they do not
come from Ubuntu, and their updates come from this project. With an LTS, Ubuntu updates the rest of the
system for 5 years.

Adding a version: copy a file from `config/distros/`, put in the ISO name, its address and its hash
(taken from Ubuntu's signed `SHA256SUMS`), then test the live system and the installation before
setting `STATUS="stable"`.

### 1. Requirements

- A Sky1 kernel **already built**: `linux-image-*-sky1-custom_*.deb` package in `/usr/src/build/sky1-kernel/`
  (procedure above; `--no-dbg` is enough, the `-dbg` package does not go into the ISO).
- The tools: `sudo ./install-deps.sh --with-iso`.
- **~35 GB free** under `/usr/src/build/sky1-iso` (the script checks and stops otherwise), plus ~5 GB for the produced ISO.
- Duration: ~20 to 40 min, mostly recompressing the squashfs layers.

### 2. The official ISO

Nothing to do: if it is missing from `/usr/src/build/sky1-iso/`, the script downloads it. It first checks
**Ubuntu's signature** on the `SHA256SUMS` list (`ubuntu-cdimage-keyring` key), then that the hash pinned
in `config/distros/` is in it, then the hash of the downloaded ISO. On every build, the hash of the
present ISO is checked: a damaged or different ISO stops the script (delete it to download it again).

### 3. Build the ISO

```bash
cd ~/bookworm-sky1-kernel-ubuntu                   # the repository
sudo iso/build-iso.sh                              # Ubuntu 26.10
sudo iso/build-iso.sh --distro ubuntu-26.04.1      # Ubuntu 26.04.1 LTS
```

| `build-iso.sh` option | Effect |
|---|---|
| `--distro <distro>` | Ubuntu version, file `config/distros/<distro>.conf` (default: `ubuntu-26.10`) |
| `--list-distros` | list the available versions |
| `--iso <file>` | use this official ISO as is (default: the distribution's, downloaded if missing; a different hash gives a warning) |
| `--kernel-deb <file>` | kernel package (default: the most recent `linux-image-*-sky1-custom` in `/usr/src/build/sky1-kernel`) |
| `--out <file>` | produced ISO (default: `…/sky1-iso/ubuntu-<version>-bookworm-sky1-orangepi6plus-arm64-<date>.iso`) |
| `--work <dir>` | work directory (default: `/usr/src/build/sky1-iso/work`, wiped at start) |
| `--keep-work` | keep the work directory at the end |
| `--resume` | resume at step 7 after a failure at the end of the script (steps 1 to 6 already done, same `--distro`) |

What each step does:
1. extracts the official ISO into the work directory;
2. builds `bookworm-sky1-settings` and takes the kernel package;
3. installs both packages into the `minimal` squashfs layer (chroot): it is the base of the live system
   **and** of the installed system; the kernel, its initramfs, its DTB and the `07_sky1` GRUB entry are
   checked there;
4. adds our two packages to the dpkg database of the other layers (each has its own copy, which would
   hide the `minimal` one) and recompresses them;
5. generates the live system initrd (casper) for the Sky1 kernel;
6. recompresses the `minimal`, `standard` and `live` layers (xz, the longest step, no output);
7. updates the metadata: sizes, manifests, GRUB menu, `md5sum.txt`, and writes
   `.disk/bookworm-sky1-info` (kernel, settings, date). `.disk/info` stays **the official ISO's one**:
   the Ubuntu installer reads the quoted code name from it and hangs silently if the line changes;
8. creates the ISO with the same boot structure (EFI partition) as the official ISO, and its `.sha256`.

**Normal** messages during step 5 (the chroot has no real root disk):
`cryptsetup: ERROR: Couldn't resolve device overlay`, `grep: /etc/fstab: No such file or directory`,
`Warning: root device does not exist`, `mount: /sys/firmware/efi/efivars: mount() failed`. Only the
`OK casper/initrd-sky1 (…), uuid …` line matters. In step 8, `xorriso : WARNING : -volid text …` is
harmless (the volume name contains spaces, like the official ISO).

If the script stops in step 7 or 8, fix the problem then run `sudo iso/build-iso.sh --resume` (a few
minutes). An earlier error: run again without `--resume`, the work directory is rebuilt.
All mounts (chroot, overlay) are unmounted on exit, even after an error.

The end shows the path, the size (~4.5 GB for 26.04.1, ~4.9 GB for 26.10) and the SHA256 of the ISO. Check:
```bash
cd /usr/src/build/sky1-iso && sha256sum -c ubuntu-*-bookworm-sky1-orangepi6plus-arm64-*.iso.sha256
```

### 4. Write the ISO to a USB stick (≥ 8 GB)

> ⚠️ `dd` erases **everything** on the target device, without confirmation. Never target `nvme0n1` (the
> system disk). One `dd` command at a time, and always on the **whole stick** (`/dev/sdX`), never on a
> partition (`/dev/sdX1`): two `dd` at the same time on the same stick give a corrupted stick.

In the commands below, **replace `sdX`** with the stick's name (often `sda` or `sdb`), and `ISO=` with the
path to your ISO: the one built in step 3 (in `/usr/src/build/sky1-iso/`) or the downloaded one (for
example in `~/Downloads/`).

1. Plug in the stick and identify it (`TRAN` column = `usb`, size and model of the stick):
   ```bash
   lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
   ```
2. Unmount its partitions if the desktop mounted them:
   ```bash
   sudo umount /dev/sdX?*
   ```
3. Write the ISO, then flush the buffers:
   ```bash
   ISO=/usr/src/build/sky1-iso/ubuntu-26.10-bookworm-sky1-orangepi6plus-arm64-20261023.iso
   sudo dd if="$ISO" of=/dev/sdX bs=4M conv=fsync status=progress
   sync
   ```
   The speed shown at the start (several GB/s) is RAM speed: the command only returns once everything
   is written to the stick, which takes several minutes.
4. Check that the stick contains exactly the ISO:
   ```bash
   sudo cmp -n "$(stat -c %s "$ISO")" "$ISO" /dev/sdX && echo "stick identical to the ISO"
   ```

**With Ventoy**: just copy the `.iso` file to the Ventoy partition (no `dd`). At boot, pick the ISO in
the Ventoy menu; if booting fails in normal mode, try Ventoy's GRUB2 mode. If it fails with Ventoy, try a
stick written with `dd` to find out whether the problem comes from Ventoy.

### 5. Boot from the stick

1. Plug the stick into the Orange Pi 6 Plus and pick it in the firmware boot menu (**CIX BIOS 1.4**
   recommended, Secure Boot disabled). Black HDMI screen right from power-on: known BIOS bug,
   **Ctrl+Alt+Del** to restart (see Limitations).
2. ISO GRUB menu (entry names are in French):
   - **"Essayer ou installer Ubuntu - Orange Pi 6 Plus (noyau Sky1 …)"** (*Try or install Ubuntu, Sky1
     kernel*): default entry, the one to use;
   - "Try or Install Ubuntu (noyau Ubuntu generique, ACPI, sans acceleration graphique)" (*generic Ubuntu
     kernel, ACPI, no graphics acceleration*): the ISO's original kernel, basic display only (fallback).
3. Boot messages are shown on screen and on the `ttyAMA2` serial console (115200 baud), useful if it
   hangs. On first boot, the live system checks the ISO files (`md5sum.txt`).
4. In the live system: `uname -r` must show `…-sky1-custom`; GNOME desktop, DP/HDMI sound and network
   work as on an installed system. The Ubuntu installer is started from the desktop.

### 6. Install (on a backed-up disk)

> Installation erases the chosen disk: first make a backup (clone) of the board's disk.

**With two SSDs**, choose the disk in the installer by its **model and size**, never by its name:
`nvme0n1` and `nvme1n1` can swap from one boot to the next (seen on this board: the same SSD was
`nvme1n1` on one boot and `nvme0n1` on the next). To identify them from the live system:
`lsblk -o NAME,SIZE,MODEL,SERIAL`.

The installer is Ubuntu's. At the end, the disk contains the Sky1 kernel, `bookworm-sky1-settings` and
the fallback Ubuntu kernel; GRUB boots the Sky1 entry by default (created by `/etc/grub.d/07_sky1`, which
finds the disk by itself). To receive updates afterwards, see
[After installation: staying up to date](#-after-installation-staying-up-to-date).

---

## 🔄 After installation: staying up to date

The Sky1 kernel and `bookworm-sky1-settings` do not come from Ubuntu's repositories: left as is,
`apt upgrade` never updates them. The BOOKWORM APT repository provides them (Ubuntu 26.04 LTS and 26.10, arm64).

**Add the repository** (once, after installation):

```bash
curl -fsSL https://www.bookworm-mon0.org/apt/setup.sh | sudo bash
```

The script checks that it runs on Ubuntu 26.04 or 26.10 on arm64, downloads the repository key and checks its
fingerprint (`24783F1C16CA14F42FC5FF4D5575688BDA477913`), then creates
`/etc/apt/sources.list.d/bookworm.sources` (key in `/usr/share/keyrings/bookworm-archive-keyring.gpg`)
and runs `apt update`. Updates then arrive along with the others:

```bash
sudo apt update && sudo apt upgrade
```

New kernels arrive through the **`linux-image-sky1`** meta-package (like `linux-image-generic` on
Ubuntu): each kernel's name contains its version (`linux-image-7.2.12-sky1-custom`), so every version is a
new package, which the meta-package pulls in. The ISO and `install.sh` install it; on a system installed
before it existed, the `bookworm-sky1-settings` update pulls it in. Use `apt upgrade` (or Software
Updater), not `apt-get upgrade`, which holds back a new kernel (as with Ubuntu's own kernels).

The new kernel becomes GRUB's default Sky1 entry; the old one stays installed, just below it, as a
fallback. Once the new one is validated, remove the old one by hand:
`sudo apt remove linux-image-7.2.11-sky1-custom` (example).

**Remove the repository** (deletes the sources file and the key; packages already installed stay in place):

```bash
curl -fsSL https://www.bookworm-mon0.org/apt/setup.sh | sudo bash -s -- --remove
```

To read the script before running it: `curl -fsSL https://www.bookworm-mon0.org/apt/setup.sh | less`.
Building it yourself is still possible (procedure above, `bookworm-sky1-build.sh --install`).

---

## 💾 Clone and restore a disk (`scripts-addons/bookworm-clone.sh`)

Step by step in real conditions (preparation, cloning, checking, restoring, messages), in French:
**[docs/guide-clonage.md](docs/guide-clonage.md)**.

Full backup of a disk (dd + zstd) before an installation or a risky test, **with checks**: SHA256 hash of
the disk taken while reading, image checked by a full decompression, image checked again before any
restore, disk read back and compared after restoring.

A system disk cannot be cloned while running: **boot from a live USB stick** (Ubuntu or BOOKWORM Sky1
ISO), copy the script to the external backup disk, then:

```bash
sudo ./bookworm-clone.sh list                                # disks; find the NVMe and the external disk
sudo ./bookworm-clone.sh save /dev/nvme0n1 /media/ubuntu/BACKUP
#    → /media/ubuntu/BACKUP/clone-nvme0n1-<date>/  (disk.img.zst, clone.info, partitions, log)
sudo ./bookworm-clone.sh verify /media/ubuntu/BACKUP/clone-nvme0n1-<date>   # check again later
sudo ./bookworm-clone.sh restore /media/ubuntu/BACKUP/clone-nvme0n1-<date> /dev/nvme0n1
```

| Safeguard | `save` | `restore` |
|---|---|---|
| Whole disk only (not a partition) | ✅ | ✅ |
| No mounted partition (otherwise: live stick) | ✅ | ✅ (checked twice) |
| Destination / image on another disk than the one processed | ✅ | ✅ |
| Refuses the disk of the running system | — | ✅ |
| Target large enough | — | ✅ |
| Image checked (hash + size) | after writing | **before** writing |
| Confirmation by typing the disk name | — | ✅ |
| Target ≠ cloned disk (different serial number): warning, confirmation by the serial number | — | ✅ |
| Disk read back and compared with the image | — | ✅ |

The image is written as `disk.img.zst.partial` and renamed only if the copy is complete. Image size:
empty space that was already erased compresses to almost nothing, old data that was never erased does not
(plan generously). Restoring to a larger disk: the script shows the command that moves the backup GPT
table to the end of the disk.

---

## ⚙️ Advanced options

All options: `./bookworm-sky1-build.sh --help`, `install/install.sh --help`,
`iso/build-iso.sh --help`, `./install-deps.sh --help` (details in the procedures above).

`config/board.conf`: kernel command line (`KERNEL_CMDLINE`, copied to `/etc/default/bookworm-sky1`),
modules to load, `KERNEL_DEBUG_INFO` (`yes` by default, to decode an Oops; `no` speeds up the build and
shrinks the packages), `KERNEL_DBG_PKG`.
The track (`config/kernels/7.2.12-stable.conf`): version, forced options (`FORCE_BUILTIN`,
`FORCE_DISABLED`, `CONFIG_OVERRIDES`), applied fixes.

---

## 🔍 Diagnostics

```bash
./diagnostics/check-system.sh          # everything
./diagnostics/check-system.sh --gpu    # GPU
./diagnostics/check-system.sh --cpu    # CPU clusters, frequencies, boost
./diagnostics/check-system.sh --pcie   # PCIe / NVMe / Ethernet
./diagnostics/check-system.sh --temp   # temperatures
```

CPU topology: cpu0 and cpu11 = A720 up to 2.6 GHz (boost); cpu1-4 = A520 1.8 GHz;
cpu5-6, 7-8, 9-10 = A720 2.2 to 2.5 GHz.

---

## 📁 Project layout

```
bookworm-sky1-kernel-ubuntu/
├── bookworm-sky1-build.sh        # entry point: download, patches, config, build
├── install-deps.sh               # apt dependencies
├── check-sky1-updates.sh         # watches linux-sky1 / kernel.org
├── distcc-env.sh                 # distributed compilation (optional)
├── config/
│   ├── board.conf                # board: cmdline, modules, debug info
│   ├── inject-sky1-config.sh     # injects the Sky1 config into the Ubuntu config
│   ├── kernels/7.2.12-stable.conf  # track: version, FORCE_BUILTIN/DISABLED, fixes
│   ├── distros/                  # Ubuntu versions for the ISO (26.10, 26.04.1)
│   ├── sky1/config.sky1-next     # reference Sky1 config (copy of linux-sky1)
│   ├── udev/                     # USB-C and GPU: no runtime suspend
│   ├── systemd/sleep.conf.d/     # system suspend blocked
│   ├── systemd/system/ cpufreq/  # CPU governor (sky1-cpufreq-tune.service), kdump, geoclue (*.service.d)
│   ├── systemd/user/ vlc/        # VLC on ALSA output (user service)
│   ├── environment.d/            # V4L2 decoders out of GStreamer autoplug, GTK without offload, mutter on GLES
│   ├── pipewire/ wireplumber/ alsa-card-profile/  # DP/HDMI audio
│   ├── grub/07_sky1              # Sky1 GRUB entries (disk detected by update-grub)
│   ├── kernel/                   # hook: one DTB per kernel in /boot/dtb
│   ├── initramfs-tools/          # hook: udev rules in the live initrd (ISO)
├── patches/
│   ├── sky1-7.2/                 # Sky1 series ported to 7.2 (+ README of the decisions)
│   ├── apply-sky1-patches.sh     # strict application of the series
│   └── fixes/                    # local 9xxx fixes and DTS/driver fixes (.py)
├── firmware/                     # README.md only: origin and licences of the firmware (no binaries)
├── dracut/sky1.conf              # initramfs
├── install/install.sh            # installation: settings package + kernel packages
├── packaging/build-settings-deb.sh  # bookworm-sky1-settings package (all system settings)
├── packaging/build-meta-deb.sh      # linux-image-sky1 / linux-headers-sky1 meta-packages (latest kernel)
├── iso/build-iso.sh              # installation ISO: official Ubuntu ISO + Sky1 kernel
├── diagnostics/                  # check-system.sh (post-boot check), video-diag.sh, audio-*.sh (HDMI sound),
│                                 # gpu-dvfs-stress.sh (GPU hang), vpu-seek-test.py, reset-watch.py, blackbox.sh
├── scripts-addons/               # bookworm-clone.sh (checked cloning), set-locale.sh, usb-rebind-bus10, bookworm-vpu-encode
├── tools/portage-sky1/           # tools to port the series to a new kernel
├── docs/                         # hardware notes, tips, cloning guide (in French)
└── LICENSE                       # GPL-2.0
```

---

## 📊 GPU performance

With the current settings (track `7.2.12-stable`, tuned governor), **glmark2-es2-wayland ≈ 2880** on
HDMI only (2916 on 7.2.12) (details in the next two tables). Starting measurements, with Ubuntu's original config:
Ubuntu 26.10, kernel 7.2.11-sky1-custom, Mesa 26.2.4 (panfrost GLES 3.1 / panvk Vulkan 1.4),
GNOME Wayland session (HDMI 4K + DP 1440p), on 2026-10-16:

| Test | Result |
|------|----------|
| glmark2-es2-wayland (800×600, default) | 1743 |
| glmark2-es2-wayland (1920×1080) | 1434 |
| vkmark (Wayland) | 2641 |

For comparison, on Gentoo (6.18/6.19, Mesa 25.x/26.1): glmark2-es2-drm ~3079,
glmark2-es2-wayland 2982, Vulkan Buffer Fill/Copy (256 MB) 37.4 / 21.4 GB/s, kmscube ~60 fps (vsync).

### Kernel config: timer and preemption

The 1743 above came from the dual display; on HDMI only, the Ubuntu config gives ~2140. A bisection
(2026-10-17, glmark2-es2-wayland 800×600, HDMI only) showed that most of the gap came from the Ubuntu
kernel's timer and preemption (1000 Hz, `NO_HZ_FULL`, dynamic "lazy" preemption):

| Config | glmark2 |
|---|---|
| Ubuntu | ~2140 |
| + 250 Hz timer and classic preemption (Gentoo) | ~2508 (**+17 %**) |
| + UBSAN off | ~2514 |
| + `init_on_alloc=0 hardened_usercopy=off` (at boot) | ~2561 |
| all Ubuntu hardening off (Gentoo config) | ~2645 |

The `7.2.12-stable` track takes Gentoo's timer and preemption and turns UBSAN off (no cost, a bug
detection tool). **The other Ubuntu hardening options are kept**: they cost ~5 % in total.
If you prefer ~2 % more in exchange for a little security, add `init_on_alloc=0 hardened_usercopy=off`
to the `linux` line of the GRUB entry (`randomize_kstack_offset=off` brings nothing).

### CPU governor

The GPU driver sends its work in short bursts. With its original threshold (95 % load), `ondemand`
never raises the frequency and slows the GPU down. The settings package installs
`sky1-cpufreq-tune.service`, which keeps `ondemand` but tunes it to follow these bursts:

| Governor | glmark2 |
|---|---|
| original `ondemand` (95 % threshold) | ~2510 |
| **`ondemand` tuned 30 / 50 (installed default)** | **~2881** |
| `performance` (CPU always at maximum) | ~2942 |
| Gentoo, in `performance` (reference) | 2982 |

The CPU goes back down about 0.4 s after the last burst: idle power saving is kept.
To switch to `performance` (or change the thresholds), edit `/etc/default/sky1-cpufreq` then
`sudo systemctl restart sky1-cpufreq-tune`. `cpupower` does not work on Ubuntu with this kernel
(it requires a `linux-tools-<version>` package that does not exist for a custom kernel):
the service writes directly to `/sys/devices/system/cpu/cpufreq/`.
Details (in French): `docs/notes-materiel.md` §14.

---

## 🙏 Credits

| Project | Contribution |
|--------|-------------|
| [Sky1-Linux](https://github.com/Sky1-Linux/) | CIX CD8180 kernel patches, config |
| [visorcraft/orange-pi-6-plus-gpu](https://github.com/visorcraft/orange-pi-6-plus-gpu) | Reverse engineering of the GPU power-up |
| [ARM Ltd](https://developer.arm.com) | Mali CSF firmware |
| [CIX Technology](https://www.cixtech.com) | CD8180 SoC, VPU firmware (`cix-vpu-firmware`, [APT repository](https://archive.cixtech.com/debian)) |

## Acknowledgements

This project was developed in collaboration with Claude (Anthropic), who took part in the pipeline, the
kernel patch fixes, the DTS and driver fixes, the port to Ubuntu 26.10 and 26.04.1 LTS, the port of the
Sky1 series to Linux 7.2 and the installation ISOs.

Many thanks to the Sky1-Linux team for their work porting to the mainline kernel!

## 📜 Licence

The scripts, configuration and documentation of this repository are distributed under the
**GNU General Public License, version 2** (GPL-2.0-only), full text in [`LICENSE`](LICENSE).

- The kernel patches (`patches/`) keep the licence stated in each file they add or modify (GPL-2.0 for
  the most part, sometimes dual GPL-2.0 / BSD licence), like the Linux kernel.
- The repository contains no binary firmware: each one comes from its author's package, with its own
  licence (see [`firmware/README.md`](firmware/README.md)).

## 📺 BOOKWORM

This project is part of the **BOOKWORM** channel: making complex open-source technology accessible to
everyone.

- 🎬 YouTube: [@kennyTech73](https://www.youtube.com/@kennyTech73)

---

*First Gentoo 6.19 Sky1 boot on OrangePi 6 Plus — 13 April 2026* 🚀
*First Gentoo 7.0 Sky1 boot on OrangePi 6 Plus — 19 April 2026* 🚀
*First Ubuntu 26.10 boot on Sky1 7.0 kernel — 16 October 2026* 🚀
*Sky1 series ported to Linux 7.2.11, booted on the first try — 16 October 2026* 🚀
