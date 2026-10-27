# Testing Ubuntu Sky1 on the Orange Pi 6 Plus: tester's guide

🇫🇷 [Français](guide-testeurs.md) | 🇬🇧 English

Thank you for testing these ISOs. They contain Ubuntu (26.10 or 26.04.1 LTS) with a Linux kernel adapted
to the Orange Pi 6 Plus (CIX CD8180 chip, "Sky1"): graphics acceleration, DP/HDMI sound, VPU, NPU, USB-C,
PCIe. They work well on the development board; your feedback checks that they also work on **other
boards, screens, disks and power supplies**.

## The ISOs

| File | Ubuntu | SHA256 |
|---|---|---|
| `ubuntu-26.10-bookworm-sky1-orangepi6plus-arm64-20261026.iso` | 26.10 | `c36a461013e897b82ab37f894729c84cbd111d97a986f280c6e3c9a5ba74ebaa` |
| `ubuntu-26.04.1-bookworm-sky1-orangepi6plus-arm64-20261026.iso` | 26.04.1 LTS | `e9027782b8db7329e15f82162021344ea9b15fc45ddf9669b8faa7d48e601b33` |

Kernel 7.2.12-sky1-custom (package 7.2.12-3), `bookworm-sky1-settings` 1.1.38.

Check the file you received (the result must match the SHA256 column):

```bash
sha256sum ubuntu-26.10-bookworm-sky1-orangepi6plus-arm64-20261026.iso
```

## 1. Prepare a USB stick (8 GB or more)

**With `dd`** (the safest method). `dd` erases the whole stick without asking: identify its name carefully.

```bash
lsblk -o NAME,SIZE,MODEL,TRAN          # the stick: TRAN = usb (often sda or sdb)
ISO=ubuntu-26.10-bookworm-sky1-orangepi6plus-arm64-20261026.iso
sudo umount /dev/sdX?*                 # sdX = the stick
sudo dd if="$ISO" of=/dev/sdX bs=4M conv=fsync status=progress
sudo cmp -n "$(stat -c %s "$ISO")" "$ISO" /dev/sdX && echo "stick identical to the ISO"
```

On Windows or macOS: balenaEtcher or Rufus (DD image mode).

**With Ventoy**: copy the `.iso` file onto the Ventoy stick. Use a medium in good condition: a worn-out
stick (or a tired SSD in a USB enclosure) gives **different failures at every boot** that look like an ISO
defect. If Ventoy behaves strangely, try again with a stick written by `dd` before reporting the problem.

## 2. Boot the live session (without installing anything)

1. Plug in the stick, power on, pick the stick in the firmware boot menu (Secure Boot disabled).
2. In GRUB, keep the default entry: **"Essayer ou installer Ubuntu - Orange Pi 6 Plus (noyau Sky1 …)"**
   (French for "Try or install Ubuntu - Orange Pi 6 Plus (Sky1 kernel)"). The other entry ("noyau Ubuntu
   generique", generic Ubuntu kernel) has no graphics acceleration: fallback only.
3. **Black HDMI screen right at power-on** (even before GRUB): known BIOS bug, not a failure. Press
   **Ctrl+Alt+Del** to restart.

In the live session, simply use the board: desktop, browser, sound, videos, USB, network.

## 3. Install (optional)

> ⚠️ **Installing erases the chosen disk.** Install on an empty or spare SSD, or make a full backup of
> the disk first.

- The installer is Ubuntu's own (icon on the live desktop).
- **With two SSDs**, choose the disk by its **model and size**, never by its name: `nvme0n1` and `nvme1n1`
  can swap from one boot to the next. From the live session: `lsblk -o NAME,SIZE,MODEL`.
- Tick "third-party codecs" (third-party software): without them, the GNOME video players have no H.264
  decoder.
- After installing, to receive kernel and settings fixes through `sudo apt upgrade`:

  ```bash
  curl -fsSL https://www.bookworm-mon0.org/apt/setup.sh | sudo bash
  ```

## 4. What to test

Whatever you usually do with the board. In particular:

- **Screens**: HDMI, DisplayPort, two screens, resolutions, screen blanking and wake-up.
- **Sound**: HDMI, DisplayPort, headphone jack; does sound come back after the screen was blanked?
- **Video**: VLC and the GNOME player (Showtime), full screen, YouTube in the browser.
- **USB**: sticks, disks, USB-C ports, keyboard and mouse.
- **Network**: both Ethernet ports, and an M.2 Wi-Fi card if you have one (never tested).
- **Disks**: second NVMe SSD.
- **Shutdown and reboot**: clean, without unusual waits.
- **Duration**: leave it running for a long time (one night playing a video, for example).

Also note your hardware: board memory size, BIOS version (shown by the report), screens, power supply
(model and wattage of the USB-C charger).

## 5. Known limitations (no need to report them)

- **System suspend disabled**: the board does not wake up, so suspend is blocked. Screen blanking works.
- **Black HDMI screen at boot**: BIOS bug, Ctrl+Alt+Del.
- **Showtime on Ubuntu 26.04.1**: choppy video while the on-screen controls are shown (smooth once they
  disappear). VLC is smooth.
- **HDR disabled**: enabling it crashed the desktop.
- **GPU hang, rare**: mostly with 3 or 4 videos playing at once. The GPU restarts by itself within a few
  seconds; the GNOME session is either kept or restarted (back to the login screen). This case is known,
  but a report is still useful if it happens during normal use.
- **Video decoding on the CPU** in desktop players (the VPU is used for encoding and explicit GStreamer
  pipelines).

## 6. Send a report

The `rapport-testeur.sh` script (provided with this guide, or in the GitHub repository
https://github.com/lpennisi73-tech/OPI6PLUS-UBUNTU, `diagnostics/` folder) gathers everything needed to
analyse a problem into one file: versions, hardware, logs of the current **and previous** boot, crashes,
installer logs. Its messages are in French.

```bash
chmod +x rapport-testeur.sh
sudo ./rapport-testeur.sh
```

It asks for a short description (what happened and roughly when; you can answer in English), then writes
`rapport-sky1-<date>.tar.gz` in your home folder. To skip the question: `sudo ./rapport-testeur.sh -m "your
description"`.

- **After a crash or a forced restart**: reboot normally, then run the script. It also reads the previous
  boot, the one where the problem happened. Do not wait for several reboots.
- **In the live session**: the file disappears at reboot. Copy it to a USB stick before restarting. (The
  live session does not keep logs from one boot to the next: run the script **before** restarting.)
- **Even if everything works**, a report is useful: it shows that your hardware works.

**Personal data**: the script removes the machine name, user names, MAC, IP and e-mail addresses, serial
numbers of disks and devices, password hashes and network lines (Wi-Fi, DHCP). It never reads the
installer file that contains the account created. The report is plain text: you can open and review it
before sending it. Nothing is sent automatically.

Send the file to the person who gave you the ISOs, if possible with a photo of the screen when something
looks wrong.
