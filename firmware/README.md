# Firmwares Sky1 : origine et licences

Le dépôt ne contient **aucun firmware binaire**. Chaque firmware vient d'un paquet publié par son
auteur, avec sa licence, et s'installe comme un paquet Debian ordinaire.

| Firmware | Pilote | D'où il vient | Licence | Installé |
|---|---|---|---|---|
| GPU Mali-G720 `arm/mali/arch12.8/mali_csffw.bin` | panthor | paquet Ubuntu `linux-firmware-misc` | Arm, « Redistributable-mali_csffw » (`/usr/share/doc/linux-firmware-misc/copyright`) | par Ubuntu |
| VPU `*.fwb` (16 codecs) | amvx (décodage/encodage V4L2) | paquet **`cix-vpu-firmware` 1.0.1-3** de CIX, dépôt APT `https://archive.cixtech.com/debian` (trixie), repris tel quel | déclarée par CIX : copyright Cix Technology 2026, GPL-2+ (`/usr/share/doc/cix-vpu-firmware/copyright`) | install.sh (étape 4) et ISO |
| DSP audio HiFi5 `dsp_fw.bin` | cix-dsp-rproc | paquet `cix-audio-dsp` 2.0.0 de CIX (même dépôt) | déclarée par CIX : MIT | **non** (le son fonctionne sans) |

## Firmwares du VPU

`packaging/fetch-cix-firmware.sh` télécharge le paquet de CIX une fois (cache : `BUILD_DIR/cix-firmware/`)
et vérifie son empreinte SHA256, figée dans le script. Si CIX change le paquet, le script s'arrête au lieu
d'installer un fichier inconnu. Pour passer à une nouvelle version : la tester, puis mettre à jour
`CIX_DEB`, `CIX_PATH` et `CIX_SHA256`.

Validé le 2026-10-18 sur Orange Pi 6 Plus : le noyau charge bien `h264dec.fwb` de CIX
(402 304 octets, sha256 `e92bf40d…`). Le décodage H.264 donne des images identiques, octet pour octet,
à l'ancien firmware, à la même vitesse (environ 850 images/s en 1080p).

## Historique

Jusqu'au 2026-10-18, les `.fwb` étaient copiés de
[Sky1-Linux/sky1-firmware](https://github.com/Sky1-Linux/sky1-firmware) (`dd81690`). Ce dépôt n'a aucun
texte de licence : il dit seulement que les fichiers sont « redistributable under their respective
licenses ». Ces copies venaient d'une ancienne BSP Radxa (`cix_beta2_radxa_dev`) et étaient plus
anciennes que celles de CIX (h264dec : 401 664 octets). Les `.fwb` étaient exclus par `.gitignore` et
n'ont jamais été dans le dépôt. Le Mali et `dsp_fw.bin` y étaient : le Mali était identique à celui
d'Ubuntu, et `dsp_fw.bin` n'était pas installé. Tous deux ont été retirés.

## Remarques sur les licences de CIX

Les fichiers `copyright` de CIX sont des modèles peu soignés : la licence GPL-2+ est déclarée pour des
binaires livrés sans source, et le texte MIT du DSP est copié de Mesa. C'est néanmoins l'autorisation
officielle publiée par l'auteur. Avant une diffusion chez Canonical, il vaudrait mieux demander à CIX une
licence de redistribution explicite, ou l'entrée de ces firmwares dans `linux-firmware`.
