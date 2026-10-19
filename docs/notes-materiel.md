# Notes matériel OrangePi 6 Plus (période Gentoo, 2026-10-08 → 2026-10-14)

Extraites de l'ancien `scripts-addons/tips-gnome-49-openrc.md` (supprimé avec les addons OpenRC
lors du portage Ubuntu ; historique complet dans git). Les parties propres à OpenRC/GNOME
(sections 1 à 6 et 9) n'ont pas été reprises. Constats faits sous Gentoo : à revalider sous Ubuntu.

## 7. HDMI et audio DP/HDMI (OrangePi 6 Plus, validé le 2026-10-10 sur 6.18.14-lts)
Image : la sortie HDMI passe par le convertisseur DP→HDMI Parade PS185HDM (dp4/dpu4). Le noyau 6.18 ne connaît pas `parade,ps185hdm` dans simple-bridge : patch local 9006 (6.18-lts et 6.18.14-lts uniquement ; 6.19 et 7.0 l'ont déjà en amont). `dts-disable-unused-dpu.py` garde dpu3/dp3 (DP natif) et dpu4/dp4 (HDMI), désactive dp0/1/2 et les liens audio dptx0/1_audio (sinon la carte son reste en EPROBE_DEFER).
Son : carte ALSA `cix_sky1`, périphérique 0 = DP natif, 1 = HDMI. Le profil par défaut (`output:stereo-fallback`) n'expose que le périphérique 0 ; il faut le profil `pro-audio` pour avoir le HDMI. Règles WirePlumber (config/wireplumber/, installées par install.sh, étape 5b) :
- 51-sky1-hdmi-profile.conf : profil pro-audio par défaut (device.profile.priority.rules). Un profil déjà mémorisé dans ~/.local/state/wireplumber/ passe avant la règle.
- 52-sky1-hdmi-buffer.conf : node.force-quantum = 4096 sur les deux sinks (à 1024 : des milliers de xruns, son haché ; api.alsa.period-size seul aggrave le problème) et noms « DisplayPort » / « HDMI ».
Pièges de test :
- `pw-play --target` attend le NOM du nœud (alsa_output.platform-sound.pro-output-1), pas l'ID de `wpctl status` ; un ID inconnu retombe sur le sink par défaut (faux « pas de son », faux « marche une seule fois »).
- Le bouton « Tester » de GNOME ne marche pas avec Pro Audio (pas de disposition de haut-parleurs) : tester avec pw-play ou une vidéo.
- `speaker-test -D pipewire` échoue sans le plugin ALSA pipewire ; inutile pour GNOME/Firefox.
- Le pilote DP audio est sain : en direct sur hw:<carte cix_sky1>,1 (S16 ou S32) tout fonctionne ; le défaut venait de PipeWire (cible et quantum).
- build-pipeline : PATCHES_EXTRA est réappliqué à chaque lancement avec `patch -p1` sans -N ; repartir d'un arbre kernel neuf (mv linux-X linux-X.old) pour un build propre.
Contrôle : `wpctl status` doit lister les sinks « DisplayPort » et « HDMI » sans réglage manuel pour un nouvel utilisateur (validé avec un utilisateur de test).

### 7b. Écran noir au réveil (HDMI, et probablement DP) : patch 9007
Symptôme : après l'extinction de l'écran par GNOME, souris et clavier ne rallument rien ; `Ctrl+Alt+F2` non plus. Pourtant `status=connected`, `enabled`, `dpms On`, et l'état atomique donne crtc `active=1`.
Cause : au réveil, le moniteur/convertisseur fait Unplugged puis Plugged en ~2,5 s, environ 2 s après le link training. `trilin_dp_handle_disconnect()` éteint le PHY et met `active_stream_cnt = 0`, mais mutter ne voit jamais l'état « déconnecté » (le connecteur est de nouveau connecté quand il relit) et ne refait pas de modeset : le CRTC reste actif sur un lien mort.
Correctif : `9007-trilin-dp-recover-stale-crtc` — à la fin du travail HPD, si le connecteur a un CRTC actif et `active_stream_cnt == 0`, on appelle `drm_atomic_helper_reset_crtc()` (log : « HPD bounce: CRTC active but link torn down, forcing modeset »). Validé sur 6.18.14-lts, 6.19-latest et 7.0-next (HDMI), y compris sur arbre propre (2 déclenchements du log en ~580 s d'idle, image revenue) ; déclaré dans les 4 pistes (dry-run OK sur 6.19 et 7.0, test réel à faire).
Contournement sans patch : `echo off | sudo tee /sys/class/drm/card2-HDMI-A-1/status; sleep 3; echo detect | sudo tee /sys/class/drm/card2-HDMI-A-1/status`.
Diagnostic utile : `sudo dmesg | grep -a -E 'hpd event|encoder_(enable|disable)'` ; un Unplugged/Plugged sans encoder_disable/enable entre les deux est le signe du bug.

### 7c. Oops USB cdns3 au chargement des modules : patch 9008
Symptôme : Oops au boot (NULL deref dans `usb_hcd_is_primary_hcd`, appelé depuis `cdns_host_resume`) pendant le probe de `xhci_plat`.
Cause : le PM runtime resume appelle `cdns_host_resume()` avant que `host_dev` / le drvdata du hcd existent (course au chargement des modules).
Correctif : `9008-usb-cdns3-guard-null-hcd-in-cdns_host_resume` — retour anticipé si `cdns->host_dev` ou le hcd est NULL. Dans les 4 pistes (PATCHES_EXTRA, après 9007) ; 9005 ajouté aussi à `6.18-lts` (oubli). Validé sur 6.18.14-lts arbre propre : 0 Oops sur les boots testés (une course : confirmer sur plusieurs boots) ; dry-run OK sur 6.19 et 7.0.
Autre Oops encore non identifié : corruption de liste (hlist) dans finit_module/idempotent_init_module, `Code: b4000140 f9400be1 f9000001 b4000041 (f9000420)` ; il faut le bloc complet (pc, lr, Call trace, /var/log/messages).

### 7d. Pas de carte son DP/HDMI sur 7.0-next : patch 9009
Symptôme : seule la carte HDA (ALC269) existe, sinks « DisplayPort » / « HDMI » absents, `dmesg` : `platform sound: deferred probe pending: (reason unknown)` et `sky1-asoc-card sound: dai-link name:dptx3_audio` en boucle ; `/sys/kernel/debug/asoc/components` sans `hdmi-audio-codec`.
Cause : 9001 copie l'`of_node` du DP sur le pdev `hdmi-audio-codec.N.auto`. Ce nœud porte la compatible `cix,sky1-dptx`, donc si `snd-soc-hdmi-codec` n'est pas encore chargé à la création du pdev, `trilin-dptx-cix` réclame ce pdev (uevent : `DRIVER=trilin-dptx-cix`, `bind` du vrai pilote : EBUSY). Course au chargement des modules.
Correctif : `9009-trilin-dp-softdep-hdmi-codec` — `MODULE_SOFTDEP("pre: snd-soc-hdmi-codec");` dans `trilin_dptx_cix.c`, hors du `#if IS_ENABLED(CONFIG_DRM_CIX_COMPONENT_BIND_BYPASSED)` (option désactivée : le `softdep` existant `pre: linlon_dp` n'est pas compilé). Contrôle : `modinfo trilin_dpsub | grep softdep`. Déclaré dans les 4 pistes ; validé sur 7.0 (carte `cix_sky1` liée, sinks, son OK sur 5 boots de suite) et sur 6.18.14 arbre propre. Un boot silencieux inexpliqué juste après l'installation, non reproduit.
Contournement sans patch : `echo 'softdep trilin_dpsub pre: snd-soc-hdmi-codec' > /etc/modprobe.d/sky1-hdmi-codec.conf` puis `depmod -a`.
Pièges de diagnostic :
- `/tmp` est vidé au reboot (recréer `tone.wav`) ; `> /root/x` échoue sans root, utiliser `| sudo tee`.
- Le bloc audio du contrôleur (registres `0x908`–`0x95c`, canaux `0x954 = 0x87654321`, compteur de paquets `0x95c`) est programmé quand le son marche ; tout à 0 = rien n'est émis. `0x868`/`0xa68` passent à 0x8 à chaque lecture de `register_info` (artefact).
- Sur 7.0 l'ELD (`amixer -c 0 contents`) était nul pendant le boot silencieux ; non établi comme cause (le chemin `drm_get_edid` + `drm_add_edid_modes` ne le construit peut-être dans aucun noyau).
- Numéro de carte : il dépend de l'ordre de chargement (`cix_sky1` était la carte 1 sur un ancien boot 6.18.14, la carte 0 sur 7.0 et sur 6.18.14 avec 9009). Ne jamais le coder en dur : `grep cix_sky1 /proc/asound/cards`.

## 8. Une application n'a pas de son (Totem, apps ALSA) alors que GNOME joue
Symptôme : le son marche dans le navigateur ou avec `pw-play`, mais pas dans Totem. `GST_DEBUG=2 totem fichier` montre `alsalib error: Unknown PCM default:{AES0 ...}` ; `wpctl status` ne montre aucun flux de l'application ; `aplay -L` ne liste que `null` et `default:CARD=cixsky1` / `sysdefault:CARD=cixsky1`.
Cause : les liens ALSA→PipeWire sont absents de `/etc/alsa/conf.d/`. Toute application qui passe par ALSA ouvre alors directement `cix_sky1` périphérique 0 (le DisplayPort), que PipeWire tient déjà en profil Pro Audio : périphérique occupé, pas de son. Le USE `pipewire-alsa` installe les fichiers mais ne les active pas.
Correctif :
```
sudo mkdir -p /etc/alsa/conf.d
sudo ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf /etc/alsa/conf.d/50-pipewire.conf
sudo ln -sf /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf /etc/alsa/conf.d/99-pipewire-default.conf
aplay -L | grep -E '^(pipewire|default)$'
speaker-test -D pipewire -c 2 -t sine -l 1
```
Validé le 2026-10-11 (Totem rejoue le son après correction). Les liens avaient disparu, probablement lors d'un nettoyage ; à intégrer à `install.sh` (étape 5b) pour les nouveaux utilisateurs.
Diagnostic rapide : `gst-launch-1.0 playbin uri=file://... video-sink=fakesink audio-sink=pipewiresink` (puis `pulsesink`, `alsasink`) pour isoler le sink fautif.

## Bruit sans conséquence
- RealtimeKit1 absent (rtkit non installé), bolt.enroll non enregistré (bolt non installé), geolocation portal NotFound.
- « Failed to open gpu /dev/dri/card0 » : GPU Panthor sans affichage, mutter utilise card1 (linlondp).
- « Couldn't set runlevel stack / File exists » et « Session termination requested » du gnome-session-init-worker : normaux.
- 7.0-next : ~389 warnings dtc « CIX_PAD_GPIOxxx redéfini » (sky1-pinfunc.h vs dt-bindings/pinctrl/pads-sky1.h), build non bloquée.

## À faire
- Hang GPU panthor : 2 occurrences (12 et 14 octobre), non reproduit ; si ça revient, blackbox + dmesg complet ; envisager un rapport à dri-devel avec les deux piles.
- Envoyer le PR 0154 (HPD) ; 9006 : crédit Maud Spierings avant tout PR.
- HDMI/DP : réveil du DP natif avec un écran DP, tests DP + HDMI simultanés.
- Boot silencieux inexpliqué sur 7.0 juste après l'installation (non reproduit sur 5 boots) : si ça revient, garder `~/audio-check.log` et ne rien toucher.
- Oops hlist (finit_module/idempotent_init_module), `Code: b4000140 f9400be1 f9000001 b4000041 (f9000420)` : non identifié, il faut le bloc complet (pc, lr, Call trace).
- Avant le tag v1.9 : ménage (utilisateurs de test, `/boot/dtb/*hdmitest*`, arbres `.old`, fichiers `/root`), README « Limites connues ».
- Intégrer les liens ALSA→PipeWire (section 8) à install.sh, étape 5b.
- Signaler le défaut à Gentoo (gnome-base/gnome-session-openrc).
- Appel optionnel du script depuis install.sh (--all-users --skel).
- USB-C 10 Gbps (retourner le connecteur, autre port), KVM (rebind via usb-rebind-bus10).

## État des pistes (2026-10-11)
- 6.18.14-lts (défaut du script, stable) : HDMI + son + réveil + 0 Oops, validé avec 9004–9009 sur arbre propre.
- 6.19-latest : build, HDMI (sans 9006, amont), son, réveil, 0 Oops validés.
- 7.0-next : build, HDMI, son (9009), réveil (9007), 0 Oops validés (1 boot silencieux inexpliqué juste après l'installation, non reproduit).
- 6.18-lts (6.18.9) : supprimée, doublon périmé.
- 6.18.14-lts (2026-10-14) : conf stable = 9004-9009 + 9002/9003 ; conf de test (6.18.14-lts-hotschmoe) = stable + 9010-9012.


### 7e. Double écran DP natif + HDMI (validé le 2026-10-11 sur 6.18.14-lts)
- Image sur les deux écrans en même temps (`card0-DP-1` = DP natif, `card2-HDMI-A-1` = HDMI ; la numérotation des cartes DRM peut varier), son sur les deux (`alsa_output.platform-sound.pro-output-0` = DP, `pro-output-1` = HDMI) et réveil des deux écrans OK.
- Au réveil, seul le HDMI fait un Unplugged/Plugged (rattrapé par 9007 : « HPD bounce ... forcing modeset ») ; le DP natif se réveille sans HPD.
- À valider sur 6.19-latest et 7.0-next. glmark2 : 3117 (6.18.14-lts, double écran).

## 10. Hang GPU Mali (panthor) sous Firefox : gnome-shell perdu, rendu llvmpipe jusqu'au reboot (2026-10-12, 6.18.14-lts)
- Symptôme : après ~10 h d'uptime, deux pubs vidéo (Firefox) laguent, puis la session Wayland redémarre ; ensuite rendu logiciel (`glxinfo -B` : llvmpipe, mutter « Not hardware accelerated »).
- Chronologie : UBSAN amvx (décodeur V4L2) -> `panthor: job timeout pid=<firefox-bin>` (2x) -> `CSG 0..6 update request timedout`, `Failed to stop MCU`, `AS_ACTIVE bit stuck` -> reset GPU échoué -> gnome-shell : `Could not import pending buffer: Out of memory`, mort puis relancé.
- Les WARNING `panthor_vm_destroy` / `panthor_gpuva_sm_step_unmap` sont collatéraux (unmap en -110 ETIMEDOUT, `AS_ACTIVE` bloqué).
- Récupération : reboot (renderer Mali-G720 MC10 / Panfrost, Mesa 26.1.8).
- Firmware vérifié : le GPU (id 0xc870, G720) charge `arm/mali/arch12.8/mali_csffw.bin` (git sha 95a25d71…, CSF v3.13.0), identique à celui du dépôt et à `linux-firmware-20260622` (sha256 718f6224…). Piste firmware écartée.
- Non reproduit ; cause non établie (WebGL/canvas des pubs, driver panthor 6.18.14, DVFS/SCMI, BIOS 1.4 ?). Contournement : désactiver l'accélération de Firefox, bloquer les pubs. Pistes : 6.19/7.0, fréquence GPU fixe (gouverneur `userspace` + `set_freq` ; `performance` disponible avec le noyau de test (9012, testé le 2026-10-14, voir la mise à jour ci-dessous) ; fréquences 72/216/350/600/800/1000 MHz), rapport drm/panthor.
- Diagnostic : `glxinfo -B | grep renderer` (pas llvmpipe) ; `sudo dmesg | grep -a -E 'panthor|job timeout|AS_ACTIVE'`.
- Bruit associé : UBSAN `array-index-out-of-bounds` dans `amvx` (`mvx_mmu.c:443` et `:812`), non fatal.

### Mise à jour 2026-10-14 : deuxième occurrence, noyau de test 6.18.14 + #37/#40/#41
Deuxième blocage MCU panthor, cette fois sans Firefox : ~8 min après le boot, pendant une compilation distcc -j20 (noyau 6.18.14-lts-hotschmoe : stable + 9002/9003 + 9010-9012). Chronologie : à 325 s `scmi_protocol scmi_dev.5: Received valid OoO Delayed Response for 124` puis `scmi_dev.4: Message for 124 type 0 is not expected!` ; à 483 s `CSG 4/5/0 update request timedout`, `CSG suspend failed`, `Failed to stop MCU`, `AS_ACTIVE bit stuck`, `Soft reset timeout`, WARNING `panthor_mmu.c:2186` (panthor_gpuva_sm_step_unmap via group_release_work). Wayland tombé.
Autre boot, même charge : `scmi_dev.4: Invalid message type:0 for 713 - HDR:0xB245005 state:2` (en-tête décodé : protocole 0x14 clock, message 0x05 CLOCK_RATE_SET, token 713, état SENT_OK).
Non reproduit ensuite, sur le même noyau :
- gouverneur GPU `performance` : 34 min de charge, 0 erreur ; puis retour à `simple_ondemand` : 0 erreur ;
- stress alterné stress-ng (CPU) + glmark2-es2-wayland (rafales GPU), 44 min, 200 cycles : 0 erreur ;
- 10 bascules de /sys/devices/system/cpu/cpufreq/boost sous charge : 0 erreur ;
- nouvelle compilation distcc -j20 avec ~/blackbox.sh actif : 0 erreur.
Noyau 7.0 non modifié, compilation distcc -j20 : pas de reboot.
Conclusion : déclencheur inconnu ; le blocage n'est pas propre à Firefox (voir ci-dessus) ni prouvé lié à #41. Repli si ça revient : `echo performance | sudo tee /sys/class/devfreq/15000000.gpu/governor` (disponible avec 9012 ; fréquence max fixe). Diagnostic : `sudo dmesg | grep -a -E 'scmi|panthor'`, sauver `dmesg` avant tout reboot.

## 11. amvx (9002/9003) et état des PR (2026-10-14)
- 9002 (`pages[0]` -> `pages[]` dans `struct mvx_mmu_pages`, mvx_mmu.h) supprime les UBSAN `array-index-out-of-bounds` de `mvx_mmu.c` ; 9003 (`q->lock = &vport->vsession->mutex` dans `setup_vb2_queue`) est du durcissement sans symptôme connu. Validés sur arbre neuf avec la conf de test : encode hevc_v4l2m2m 313 fps (13,1x), plus aucune ligne UBSAN/mvx_mmu/vb2 dans dmesg. Ajoutés à `config/kernels/6.18.14-lts.conf` après 9009 (commit 6039c6f). Le `Firmware rsp: Error code=7` de la section 10 n'est pas traité par 9002/9003.
- PR #43 (Sky1-Linux/linux-sky1) : 0150/0151 (9005/9008, garde NULL cdns3), en attente de réaction.
- PR #44 (2026-10-14) : 0152/0153 (amvx, 9002/9003). Prêt, non envoyé : 0154 (trilin DP HPD, 9007), à envoyer à son tour. Le mainteneur ne réagit plus aux PR depuis début mars (#43 inclus) : ne pas attendre sa réponse avant d'envoyer la suite.
- Tested-by postés le 2026-10-14 sur les PR de hotschmoe #37, #40, #41 : encode VPU à 1200 MHz, glmark2-es2-wayland 2982, trafic SCMI CLOCK_RATE_GET ~0,5/s, stress 44 min sans erreur ; événement de la section 10 signalé dans #41.
- Audio 9001/9009 : utiles seulement sur 7.0-next (le son marche sur 6.18.14 sans 9001) ; à réécrire sur `patches-next/` et tester sur 7.0 avant tout PR. 9006 = rétroportage de Maud Spierings (amont >= 6.19) : citer l'auteur et les hashes avant tout PR.

## 12. Reboots à chaud pendant la compilation (2026-10-13/14, non élucidé)
Deux redémarrages brutaux de suite pendant la compilation d'un noyau 6.18.56 (distcc -j20, boot sur 6.18.14 modifié). Écartés : pas de panic (`kernel.panic=0` figerait la carte), watchdog `sky1-wdt` inactif, pstore vide, températures au repos 41-45 °C (seuils 85/95/98 °C), rien dans /var/log/messages. Restent : alimentation (bloc USB-C PD 20 V 5 A, 100 W, câble ?) ou protection thermique du firmware. Non reproduit depuis. Outil : `~/blackbox.sh` (écrit mémoire, swap, charge, températures, fréquence et lignes scmi/panthor/WARNING toutes les 3 s avec sync dans ~/blackbox-*.log) ; à lancer avant toute grosse compilation. Si ça revient : `tail -30` du dernier blackbox, comparer avec 7.0 non modifié, tester un autre câble USB-C marqué 5 A.

**Retour sous Ubuntu (2026-10-17, 03:10, noyau `7.2.11-sky1-perftest`)** : redémarrage brutal pendant
le build `7.2.11-perf-tick` (`make -j12 bindeb-pkg`, CPU à ~85 % user). Même tableau : journal coupé net
(dernière ligne : cron 03:10:01), pstore vide, `kernel.panic=0`, watchdog inactif. Températures relevées
juste après la relance du build : CPU 63-74 °C, DDR 68 °C (loin des seuils). Les trois builds complets
précédents (2026-10-16, noyau `-sky1-custom`, config Ubuntu) n'ont pas eu de souci : lien avec le noyau
perftest (préemption complète, HZ 250) possible mais pas prouvé. `~/blackbox.sh` (Gentoo) n'existait
plus : réécrit dans `diagnostics/blackbox.sh` (journal dans `/var/log/sky1-blackbox/`), lancé pendant
le build relancé.

## 13. Lecture vidéo sous Ubuntu 26.10 (2026-10-16, 7.2.11)

- **Sorties DP/HDMI à quantum 4096 (85 ms)** (`config/wireplumber/52-sky1-hdmi-buffer.conf`,
  xruns à 1024). Les clients PulseAudio recevaient des tampons trop petits (40 ms / 120 ms) :
  `config/pipewire/pipewire-pulse.conf.d/52-sky1-pulse-latency.conf` les aligne sur 4096.
- **VLC 3.0.24, son haché par moments malgré cela** : PipeWire ne signale aucune sous-alimentation,
  c'est le module de sortie PulseAudio de VLC qui recale le son sur l'image en retirant des
  morceaux (latence de sortie élevée). Avec la sortie ALSA (qui passe aussi par PipeWire,
  via `pipewire-alsa`) le son est propre, y compris en AC-3 5.1. Réglage par utilisateur :
  `aout=alsa` dans `~/.config/vlc/vlcrc` (ou *Outils → Préférences → Audio → Module de sortie :
  ALSA*), ou ponctuellement `vlc --aout=alsa`.
- **Showtime (lecteur GNOME)** : avec le VPU (`v4l2h264dec`, choisi d'office par GStreamer 1.28)
  image verte figée, sans son ; le décodage VPU est correct, c'est l'affichage VPU → GTK4 qui
  échoue. `config/environment.d/90-sky1-gst-v4l2-rank.conf` sort les décodeurs V4L2 de
  l'autoplug : décodage CPU, image et son parfaits. Décodage matériel dans GTK : à étudier.
- **Firmwares VPU** : paquet officiel `cix-vpu-firmware` de CIX (depuis le 2026-10-18 ; avant : copie de
  Sky1-Linux/sky1-firmware, plus ancienne et sans licence). Sans eux, le pilote amvx corrompait sa liste
  interne (corrigé dans le patch 0045). Voir `firmware/README.md`.

- **Showtime se ferme en plein écran** (2026-10-17, décodage CPU) : `MESA: error: drmPrimeHandleToFD() failed (err=22)`
  puis `Error 9 (Mauvais descripteur de fichier) dispatching to Wayland display`. En plein écran, GTK 4.24 fait de
  l'*offload* : il veut passer l'image vidéo à gnome-shell en dmabuf. Cette image est une texture GStreamer GL
  (`glsinkbin` → `gtk4paintablesink`) créée par Mesa panfrost dans un buffer privé (`exclusive_vm_root_gem`), que
  `panthor_gem_prime_export` refuse d'exporter (EINVAL). GTK envoie quand même le fd invalide et le compositeur coupe
  la connexion. Même plantage avec `GSK_RENDERER=gl` : le rendu de GTK (Vulkan panvk par défaut) n'y est pour rien.
  **Solution** : `GDK_DISABLE=offload` (`config/environment.d/90-sky1-gtk-offload.conf`), lecture fluide en plein écran.
  À signaler en amont : Mesa panfrost (export d'une ressource privée sur panthor) et GTK (échec d'export non vérifié).

- **Saccades vidéo à l'ouverture des notifications / du menu système** (2026-10-17) : `perf` montre le fil principal de
  gnome-shell à ~100 % d'un cœur dans `convert_ubyte` (Mesa `format_utils.c`) ← `_mesa_store_texsubimage` ←
  `st_TexImage` ← `glTexImage2D` ← `cogl_texture_2d_gl_allocate`. Une sonde sur `_mesa_TexImage2D` relève des
  envois `format=GL_BGRA, internalformat=GL_RGBA8` (panneau 1508×1116, icônes) : en OpenGL bureau, Mesa permute
  chaque pixel sur le processeur dans la mémoire du GPU. Images affichées : 60 → 43-49/s pendant les clics.
  **Solution** : `COGL_DRIVER=gles2` (`config/environment.d/90-sky1-mutter-gles.conf`) : en GLES, cogl envoie le BGRA
  tel quel. Validé par l'utilisateur (« ça fonctionne super bien »). Méthode : symboles Mesa et mutter récupérés sur
  ddebs.ubuntu.com (`mesa-libgallium-dbgsym`, `libmutter-51-0-dbgsym`), `perf probe` sur l'adresse de la fonction.

## 14. Performances GPU sous Ubuntu 26.10 (2026-10-16, 7.2.11)

Mesures (session GNOME Wayland, HDMI 4K + DP 1440p, Mesa 26.2.4) : glmark2-es2-wayland **1743**
(800×600) / **1434** (1080p), vkmark **2641**. GPU à 1 GHz en charge, 47 °C, aucune erreur panthor.
Sous Gentoo : glmark2-es2-wayland 2982, soit environ 40 % de moins sous Ubuntu.

Ce que montrent les essais (sous-ensemble de 8 scènes ; le bruit de mesure est d'environ ±10 %) :
- glmark2 à plus de 2000 images/s est limité par la **latence** CPU → GPU → CPU, pas par le
  calcul : `perf` montre le CPU inoccupé à 53 % pendant la scène `build`.
- Gouverneur CPU (config Ubuntu `ondemand`, Gentoo `schedutil`) : ondemand ~1400-1650,
  schedutil 863, performance 1777. Le gouverneur ne suffit pas à expliquer l'écart.
- Placement : petits cœurs A520 seuls (cpu1-4) 893 ; grands cœurs 1480-1580.
- Sans effet notable : THP `always` au lieu de `madvise`, veilles profondes cpuidle désactivées.
- Différences de config Ubuntu / Sky1 (Gentoo) restant à tester : `INIT_ON_ALLOC_DEFAULT_ON=y`
  (testable au boot avec `init_on_alloc=0`), HZ 1000 / 250, `NO_HZ_FULL`, `PREEMPT_DYNAMIC`,
  durcissements (KFENCE, UBSAN, FORTIFY, HARDENED_USERCOPY, SLAB_FREELIST_*, ZERO_CALL_USED_REGS).
  Autres pistes : panthor 7.2 et Mesa 26.2 (les deux ont changé depuis Gentoo).
- À vérifier : la comparaison n'est pas forcément à conditions égales (définition des écrans,
  version de glmark2 et de GNOME sous Gentoo).
- Boot avec `init_on_alloc=0` (ajouté à la main dans GRUB, `heap alloc:off`) : glmark2 complet
  **2136 et 2133** (reproductible ; texture ~3300, build 2472, terrain 57), contre 1743 avant.
  Mais le sous-ensemble de 8 scènes n'a pas bougé (1665 / 1662, avant 1389-1677) : l'effet
  d'`init_on_alloc` n'est pas prouvé. Il faut un contrôle (2 runs complets sur un boot normal).
- **Contrôle sur boot normal** (`heap alloc:on`) : glmark2 complet **2125 / 2155**, soit autant
  qu'avec `init_on_alloc=0` : ce paramètre ne joue pas. Le 1743 du premier jour a été mesuré
  avec le DP 1440p encore branché (GNOME composait 4K + 1440p) ; HDMI seul : ~2150.
- Bureau GNOME saccadé (menus, animations), signalé par l'utilisateur en HDMI 4K seul. L'écran est
  envoyé en 4K AR30 (10 bits), en mémoire linéaire (`modifier=0x0`). mutter a pris `card0` (DP,
  rien de branché) comme carte principale, alors que l'écran HDMI est sur `card2`.
  Runtime PM du GPU : `autosuspend_delay_ms=50`, GPU en veille plus de la moitié du temps
  (97 s contre 63 s actif sur 2 min) : chaque animation commence par un réveil du GPU (MCU).

### Blocage GPU du 2026-10-16, 20:57 (7.2.11, Mesa 26.2.4)
- Environ 2 min après le passage manuel du GPU en gouverneur devfreq `performance` (1 GHz fixe),
  pendant que l'utilisateur ouvrait menus et aperçu : `CSG 0..7 update request timedout`,
  `CSG suspend failed`, `Failed to stop MCU`, `Soft reset timeout`, 35× `AS_ACTIVE bit stuck`.
  gnome-shell : `Group became unusable`, `panfrost_batch_submit failed: 22`. Écran noir.
- Le redémarrage bloque : tâches `panthor_device_suspend` / `panthor_device_unplug` bloquées
  plus de 122 s ; coupure nécessaire. Aucun `job timeout` avant, rien de SCMI, pstore vide.
- Même signature que la §10 (Gentoo, 6.18.14) : le problème n'est donc propre ni au noyau 7.2
  ni à Ubuntu. Le lien avec `performance` n'est pas prouvé : sous Gentoo, ce gouverneur avait
  tenu 34 min sans erreur, et il était proposé comme contournement.
- **Essai runtime PM** (2026-10-16 soir) : `echo on > /sys/devices/platform/soc@0/15000000.gpu/power/control`
- **Blocage du 2026-10-17** (Showtime venait de lancer une vidéo) : la mise en veille runtime échoue (`CSG update request timedout`, `Failed to stop MCU`, `AS_ACTIVE bit stuck`). panthor s'interbloque : `pm_runtime_work → panthor_device_suspend → cancel_work_sync(reset)` attend le reset, qui attend `panthor_device_unplug → pm_runtime_resume`, qui attend la fin de la veille. gnome-shell et Showtime restent en état D dans `panthor_ioctl_dev_query → rpm_resume`. **Décision** : règle `config/udev/90-sky1-gpu-pm.rules` (`power/control=on`), posée par install.sh.
  (GPU jamais mis en veille, gouverneur `simple_ondemand` gardé) : **bureau nettement plus fluide**
  (avis de l'utilisateur) ; seul le menu système en haut à droite (extinction) saccade encore.
  Réglage à chaud, perdu au reboot. À décider : règle udev permanente (consommation au repos à mesurer),
  et suivi de la stabilité (moins de cycles veille/réveil du MCU).


### Noyau de test `7.2.11-sky1-perftest` (2026-10-17) : options Gentoo

Track `7.2.11-perf-test` (supprimé le 2026-10-17 avec les autres tracks de bisection, voir l'historique git) = 7.2.11-stable + `CONFIG_OVERRIDES` : HZ 250 (au lieu de 1000),
`NO_HZ_IDLE` (au lieu de `NO_HZ_FULL`), tick accounting, `PREEMPT` classique (au lieu de
dynamique + lazy), sans `SCHED_CORE` ni les durcissements Ubuntu (KFENCE, UBSAN, FORTIFY,
HARDENED_USERCOPY, SLAB_*, SHUFFLE, ZERO_CALL_USED_REGS, LIST_HARDENED, RANDOMIZE_KSTACK,
INIT_ON_ALLOC, PAGE_POISONING, FTRACE_SYSCALLS, FUNCTION_PROFILER).

| Mesure (glmark2-es2-wayland, 800×600, HDMI seul, runtime PM GPU `auto`) | Run 1 | Run 2 |
|---|---|---|
| `7.2.11-sky1-custom` (config Ubuntu) | 2125 | 2155 |
| `7.2.11-sky1-perftick` (horloge + préemption Gentoo seules, durcissements gardés) | 2513 | 2504 |
| `7.2.11-sky1-perfhard` (durcissements coupés seuls, horloge et préemption Ubuntu) | 2456 | 2450 |
| `7.2.11-sky1-perfubsan` (perftick + UBSAN coupé seul) | 2529 | 2499 |
| `7.2.11-sky1-perfubsan` + `init_on_alloc=0 hardened_usercopy=off` (au boot) | 2566 | 2556 |
| `7.2.11-sky1-perfubsan` + les mêmes + `randomize_kstack_offset=off` | 2550 | 2556 |
| **`7.2.11-sky1-custom` (nouveau stable : horloge/préemption Gentoo, UBSAN coupé)** | **2517** | **2529** |
| `7.2.11-sky1-custom` + `ondemand` réglé `up_threshold=50 sampling_down_factor=10` | 2811 | 2798 |
| `7.2.11-sky1-custom` + `ondemand` réglé `up_threshold=30 sampling_down_factor=50` | 2860 | 2902 |
| `7.2.11-sky1-custom` + gouverneur CPU `performance` (à chaud) | **2946** | **2938** |
| `7.2.11-sky1-perftest` (options Gentoo) | **2639** | **2651** |
| Gentoo (référence) | 2982 | |


**perfubsan ≈ perftick** (2514 contre 2508, dans le bruit) : UBSAN ne coûte rien de mesurable. Le coût des durcissements est ailleurs. Réglables au boot sans recompiler : `init_on_alloc=0`, `randomize_kstack_offset=off`, `hardened_usercopy=off` (`page_alloc.shuffle` est déjà à N). À la compilation seulement : `ZERO_CALL_USED_REGS`, `FORTIFY_SOURCE`, `SLAB_FREELIST_*`, `LIST_HARDENED`, `SCHED_STACK_END_CHECK`. Avec `init_on_alloc=0 hardened_usercopy=off` : ~2561 (+2 %, environ un tiers de l'écart avec perftest).. Avec en plus `randomize_kstack_offset=off` : ~2553, aucun effet. Les ~3 % restants (2553 → 2645) viennent des options de compilation.

**Gouverneur CPU** (2026-10-17, nouveau stable) : `ondemand` ~2490-2523, `performance` **2946 / 2938** (+17 %, au niveau de Gentoo 2982, mesuré sous Gentoo avec `cpupower` en `performance` permanent). CPU ≤ 54 °C pendant glmark2 : la charge GPU est faite de rafales courtes du fil de soumission, qu'`ondemand` ne suit pas (il reste bas). C'était l'écart de « latence, pas calcul » vu le 2026-10-16. Sous Ubuntu, `cpupower` est un script qui exige `linux-tools-<kver>` (absent pour un noyau maison) : passer par sysfs (`scaling_governor`). Réglage d'`ondemand` (valeurs d'origine : `up_threshold=95`, `sampling_down_factor=1`, `sampling_rate=8000` µs) : 50/10 → ~2805, **30/50 → ~2881** (−2 % contre `performance`, fréquence relâchée ~400 ms après la dernière rafale, CPU ≤ 53 °C).
**+24 %** environ (perftick seul : **+17 %**, perfhard seul : **+14 %** ; les deux groupes comptent et leurs gains se recouvrent en partie, ils ne s'additionnent pas), 0 erreur panthor, 0 WARNING au boot. Les options de la config Ubuntu
expliquent donc une bonne partie de l'écart.

**Observation utilisateur sur perftick** : deux vidéos en lecture (VLC + Showtime) ; ouvrir la liste des
notifications ou le menu système de gnome-shell fait saccader les vidéos, le reste du bureau est fluide.
C'est la même chose que le menu système : un à-coup côté gnome-shell/mutter à l'ouverture d'un menu
(construction du menu en JavaScript sur le fil principal du compositeur ?), pas une question de puissance.
Piste à creuser plus tard (profil `sysprof` de gnome-shell à l'ouverture du menu). Reste ~11 % (pistes : runtime PM GPU, Mesa, mutter).

**Avis de l'utilisateur** : bureau « beaucoup plus fluide, plus utilisable vraiment » ; seul le menu
système en haut à droite saccade encore une fois sur deux (GTK4/gnome-shell ?).

**Message SCMI vu une fois** (02:39:25, ~15 s après le lancement d'une vidéo dans Showtime) :
`scmi_dev.4: Received valid OoO Delayed Response for 697` puis `scmi_dev.3: Invalid message type:0
for 697 - HDR:0xAE45005 state:2`. En-tête décodé : protocole 0x14 (Clock), message 5
(`CLOCK_RATE_SET` asynchrone), jeton 697 (vraisemblablement l'horloge audio de la sortie HDMI).
Le firmware a envoyé la réponse différée (canal rx, `scmi_dev.4`) avant que la réponse immédiate
(canal tx, `scmi_dev.3`) soit traitée ; le noyau accepte la réponse différée (« valid ») et rejette
la réponse immédiate arrivée trop tard. Sans conséquence (le son marche). Jamais vu dans les boots
précédents (config Ubuntu) : la préemption complète change le minutage. À surveiller seulement si
ça se répète ou si un changement d'horloge échoue.
