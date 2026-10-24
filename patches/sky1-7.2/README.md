# Série Sky1 portée sur Linux 7.2 (BOOKWORM)

Série `patches-next` de [Sky1-Linux/linux-sky1](https://github.com/Sky1-Linux/linux-sky1)
(43 patches, dernier commit amont 57e018a du 2026-02-28, base 7.0) portée sur **Linux 7.2.11**
le 2026-10-16, + deux patches BOOKWORM : `0044` (adaptation aux API 7.2) et `0045` (correctifs constatés au boot). Utilisée par `config/kernels/7.2.11-stable.conf` (`SKY1_PATCHES_LOCAL`).

S'applique en mode strict (`git apply`, sans fuzz) sur un `linux-7.2.11` vierge.
Chaque patch garde son en-tête d'origine (auteur, message) ; une ligne indique le portage :

- `[ported to Linux 7.2 by BOOKWORM: conflicts with upstream 7.2 resolved]` : conflits résolus à la main
- `[rebased on Linux 7.2 by BOOKWORM: context refreshed]` : contenu identique, contexte remis à jour

## Méthode

1. Référence : 7.0 vierge + série d'origine (s'applique sans conflit), un tag par patch.
2. Port : 7.2.11 + série, patch par patch. Conflits résolus par fusion à trois voies
   (base = réf avant le patch, constructeur = réf après, amont = 7.2 avant le patch).
3. Contrôles : lignes ajoutées/retirées identiques à la référence (hors fichiers adaptés),
   audit d'emplacement des ajouts (ligne d'ancrage), compilation des sous-systèmes touchés,
   simulation de la config du build (FORCE_BUILTIN / FORCE_DISABLED).

## Adaptations par patch

| Patch | Conflit | Résolution |
|---|---|---|
| 0001 DT | `sky1.dtsi` / `sky1-orion-o6.dts` amont réécrits en 7.2 | Version constructeur entière (celle attendue par tous les pilotes Sky1). Les 4 DTB compilent, y compris `sky1-xcp` (nouveau en 7.2). |
| 0003 clk | `source "drivers/clk/cix/Kconfig"` placé par le fuzz après une aide Kconfig | Replacé après `drivers/clk/bcm/Kconfig`. |
| 0004 reset | `reset-sky1.c` entré en amont (compatible `cix,sky1-system-control`) | Pilote constructeur (`cix,sky1-src` / `-fch`, utilisés par le DT constructeur). `RESET_SKY1` déclaré une seule fois (entrée amont + `default ARCH_CIX`). |
| 0005 mailbox | API 7.2 : `mailbox.h` supprimé, `TXDONE_BY_*` → `MBOX_TXDONE_BY_*` | Pilote constructeur adapté. |
| 0006 SCMI | Bloc ACPI placé par le fuzz avant l'allocation de `scmi_dev` (NULL deref en ACPI) | Replacé après `device_set_node()`. |
| 0008 PCIe | Amont 7.2 : quirks ASPM, `max_link_speed`, `read_sz`, `rp_readl/writel`, HPA | `pcie-cadence.h` : infra HPA retirée comme le constructeur, ajouts 7.2 conservés (`max_link_speed`, `quirk_broken_aspm_*`, accès config 32 bits `read_sz`, `rp_readl/writel`) + `ecam_support_flag`. `pcie-cadence-host.c` : définitions locales constructeur + `../../pci.h` + `max_link_speed`. `of.c` : version amont (même intention). Tout le dossier Cadence compile (sky1, j721e, sg2042). |
| 0009 PHY | `source "drivers/phy/cix/Kconfig"` placé par le fuzz **dans** une aide Kconfig → `PHY_CIX_*` invisibles | Replacé après `drivers/phy/cadence/Kconfig` (et `cix/` après `cadence/` dans le Makefile). |
| 0010 USB | 7.2 : USBSS + USBSSP unifiés dans `cdns.ko`, `USB_CDNSP*` supprimés, `cdns_host_init` non exporté | Pas de pilote `cdnsp-plat` séparé : `cdns3-plat.c` amont reconnaît `cdns,usbssp` (DRD conservé, PHY `cdnsp,usbN-phy`, autosuspend 200 ms). `USB_CDNSP_SKY1` dépend de `USB_CDNS3`. Dans le track : `USB_CDNSP_GADGET` → `USB_CDNS3_HOST` + `USB_CDNS3_GADGET`. |
| 0011 panthor | 7.2 : registres par bloc (`panthor_*_regs.h`), `gpu_read(iomem, …)`, init cohérence déplacée dans `panthor_gpu.c`, objets GEM non shmem | Une seule `panthor_gpu_coherency_init()` (amont) avec la logique Sky1 (ACE-Lite forcé, `force_noncoherent`) ; elle renseigne `coherency_mode` (code constructeur) **et** `selected_coherency` (lu par Mesa). `coherency_set` : nouvelle API + `SHAREABLE_CACHE`. `GPU_COHERENCY_SHAREABLE_CACHE` et registres PBHA dans `panthor_gpu_regs.h`. `panthor_is_sky1()` exporté. |
| 0014 son | `SND_HDA_CIX_IPBLOQ` déplacé par le constructeur (doublon) ; indentation `alc269.c` | Entrée constructeur + `depends on ARCH_DMA_ADDR_T_64BIT` (amont 7.2). Fixup `ALC256_FIXUP_CIX_PHECDA` conservé. |
| 0017 pmdomain/cpufreq | `scmi_pm_domain_remove()` : nettoyage parent/enfant amont ; `topology_update_freq_ref()` placé par le fuzz avant la mise à jour des fréquences | Nettoyage amont sous la garde `if (np)` du constructeur. `topology_update_freq_ref()` après `cpufreq_frequency_table_cpuinfo()` réussi (boost). |

| 0044 (BOOKWORM) | Pilotes constructeur écrits pour les API 7.0 : erreurs à la compilation complète (non vues au portage, qui ne compilait que les sous-systèmes en conflit) | `clk_ops.round_rate` → `.determine_rate` (`clk-sky1-audss`) ; DRM `drm_atomic_state` → `drm_atomic_commit` ; `DRM_COLOR_FORMAT_*` → `BIT(DRM_OUTPUT_COLOR_FORMAT_*)` (mêmes valeurs) ; `drm_atomic_private_obj_init()` sans état initial → `.atomic_create_state` (modèle komeda) ; `drm_panel_init()` → `devm_drm_panel_alloc()` ; `strncpy` → `strscpy` (VPU). Contrôle : les 73 dossiers de `.c` touchés par la série compilent avec la config du build. |
| 0045 (BOOKWORM) | Défauts constatés au premier boot 7.2.11 | linlon-dp : `aperture_remove_all_conflicting_devices()` avant `devm_drm_dev_alloc()` (simpledrm restait affiché comme 2ᵉ écran « Inconnu » dans GNOME). amvx : un firmware en échec n'est plus réutilisé par le cache et `mvx_fw_cache_get()` renvoie `-ENOENT` au lieu d'inscrire la session (sinon timeout puis `list_add corruption`, use-after-free de `session->fw_event`). NPU : `IRQF_ONESHOT` retiré (pas de handler threadé). Watchdog : `WQ_PERCPU`. |
| 0046 (BOOKWORM, 2026-10-19) | VPU bloqué si un lecteur se déplace dans la vidéo pendant la mise en route (Showtime reprend à la dernière position) : `STREAMON(CAPTURE)` → `-EINVAL`, le firmware refuse un vidage de sortie (« Output flush only allowed when stopped, or after response _SEQUENCE_PARAMETERS ») car le pilote croit encore avoir les paramètres de séquence, oubliés par le firmware au vidage de l'entrée | `mvx_session_streamoff()` : `received_seq_param` remis à zéro quand le port d'entrée est vidé. Reproduit 3/3 (seek avec vidage 10 ms après PAUSED), corrigé 3/3, autres seeks inchangés ; module testé à chaud, 0 WARNING ; série 46/46 stricte. |
| 0047 (BOOKWORM, 2026-10-21) | Activer le HDR dans les paramètres de GNOME fait planter le noyau et gnome-shell (constaté par l'utilisateur) : le chemin HDR du DP/HDMI n'est pas utilisable | `trilin_dp_add_properties()` : `Colorspace` et `HDR_OUTPUT_METADATA` ne sont plus attachés au connecteur, sauf avec le paramètre `trilin_dpsub.hdr=1`. Sans ces propriétés, mutter ne propose plus le HDR. `max_bpc` (10 bits) et les autres propriétés inchangés. Module compilé sans avertissement, série 47/47 stricte. |
| 0048 (BOOKWORM, 2026-10-21) | Son HDMI perdu jusqu'au redémarrage après un réveil de l'écran : le lien DP remonte alors que l'I2S tourne, la file audio du contrôleur ne se resynchronise pas (`SEC0_AUDIO_FIFO_READY` = 0) | `trilin_dp_prepare()` : `reset_dp_and_reinit()` (réinitialisation complète, comme au démarrage) avant la remontée du lien si l'audio tourne ; paramètre `trilin_dpsub.audio_reset` (défaut 1, 0644). Testé : 5 réveils (dont 2 après 15 min), son revenu à chaque fois. Module compilé sans avertissement, série 48/48 stricte. |
| 0049 (BOOKWORM, 2026-10-24) | GPU perdu jusqu'au redémarrage, environ une fois par jour : les 8 CSG ne répondent plus, `Failed to stop MCU`, `AS_ACTIVE bit stuck`, `Soft reset timeout`, puis « Failed to boot MCU after reset, making device unusable » ; le bureau repart en rendu logiciel | `panthor_device_reset_work()` : si le MCU ne redémarre pas, remise à zéro par la ligne de reset du GPU (`gpu_reset`, comme au sondage), puis nouvelle remise à zéro lente avant d'abandonner (`panthor_gpu_sky1_reset_pulse()` dans `panthor_gpu.c` : IRQ masquée, requêtes en attente abandonnées). Paramètres `panthor.sky1_hard_reset` (défaut 1) et `panthor.sky1_hard_reset_test` (essai : prend ce chemin à la prochaine remise à zéro). Module compilé sans avertissement (W=1), série 49/49 stricte. Validé (2026-10-24) : blocage provoqué, GPU récupéré dans la même seconde, session relancée avec l'accélération, glmark2 2862 ensuite. Dans le noyau 7.2.12-2. |
| 0012 affichage (BOOKWORM, 2026-10-18) | Licence : 8 fichiers HDCP de Trilinear Technologies (`drivers/gpu/drm/cix/dptx/hdcp/` : `hdcp2_hw_tx.[ch]`, `hdcp2_key_drvn_tx.[ch]`, `hdcp2_tx_state.[ch]`, `dptx_reg.h`, `dptx_aux_reg.h`) marqués « CONFIDENTIAL AND PROPRIETARY », sans licence GPL | Retirés avec l'option `TRILIN_DP_HDCP_VALIDATION` (validation HDCP « pré-silicium », désactivée) et ses 3 lignes de Makefile ; `cix_hdcp_ioctl.c` garde ses fonctions vides et ne les inclut plus. Ne change rien au noyau compilé. Fait avec `tools/portage-sky1/fixpatch.sh 0012`. Contrôle : série 45/45 stricte, identique à l'arbre de portage ; `trilin-dpsub` compile sans avertissement ; `PATCHES_EXTRA` et `FIXES` s'appliquent. |

Tous les autres patches (0012 affichage, hors retrait HDCP ci-dessus, 0013 réseau, 0015 VPU, 0016 NPU, 0019-0043 dont les
correctifs DP/HDMI/audio) s'appliquent tels quels ou avec simple rafraîchissement de contexte
(leurs erreurs de compilation dues aux API 7.2 sont corrigées à part, dans 0044).

## Correctifs locaux (patches/fixes) sur 7.2

- `FIXES` (scripts Python) : tous OK.
- `PATCHES_EXTRA` : 9001-9005, 9007-9009 s'appliquent. 9006 inutile (`parade,ps185hdm` en amont).
