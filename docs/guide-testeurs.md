# Tester Ubuntu Sky1 sur Orange Pi 6 Plus : guide du testeur

🇫🇷 Français | 🇬🇧 [English](guide-testeurs.en.md)

Merci de tester ces ISO. Elles contiennent Ubuntu (26.10 ou 26.04.1 LTS) avec un noyau Linux adapté à
l'Orange Pi 6 Plus (puce CIX CD8180, « Sky1 ») : accélération graphique, son DP/HDMI, VPU, NPU, USB-C,
PCIe. Elles marchent bien sur la carte de développement ; vos retours servent à vérifier qu'elles
marchent aussi sur **d'autres cartes, écrans, disques et alimentations**.

## Les ISO

| Fichier | Ubuntu | SHA256 |
|---|---|---|
| `ubuntu-26.10-bookworm-sky1-orangepi6plus-arm64-20261026.iso` | 26.10 | `c36a461013e897b82ab37f894729c84cbd111d97a986f280c6e3c9a5ba74ebaa` |
| `ubuntu-26.04.1-bookworm-sky1-orangepi6plus-arm64-20261026.iso` | 26.04.1 LTS | `e9027782b8db7329e15f82162021344ea9b15fc45ddf9669b8faa7d48e601b33` |

Noyau 7.2.12-sky1-custom (paquet 7.2.12-3), réglages `bookworm-sky1-settings` 1.1.38.

Vérifier le fichier reçu (le résultat doit être identique à la colonne SHA256) :

```bash
sha256sum ubuntu-26.10-bookworm-sky1-orangepi6plus-arm64-20261026.iso
```

## 1. Préparer une clé USB (8 Go ou plus)

**Avec `dd`** (méthode la plus sûre). `dd` efface toute la clé sans demander : bien repérer son nom.

```bash
lsblk -o NAME,SIZE,MODEL,TRAN          # la clé : TRAN = usb (souvent sda ou sdb)
ISO=ubuntu-26.10-bookworm-sky1-orangepi6plus-arm64-20261026.iso
sudo umount /dev/sdX?*                 # sdX = la clé
sudo dd if="$ISO" of=/dev/sdX bs=4M conv=fsync status=progress
sudo cmp -n "$(stat -c %s "$ISO")" "$ISO" /dev/sdX && echo "clé identique à l'ISO"
```

Sous Windows ou macOS : balenaEtcher ou Rufus (mode image DD).

**Avec Ventoy** : copier le fichier `.iso` sur la clé Ventoy. Utiliser une clé en bon état : un vieux
support (ou un SSD en boîtier USB fatigué) donne des pannes **différentes à chaque démarrage** qui font
croire à un défaut de l'ISO. En cas de comportement bizarre avec Ventoy, réessayer avec une clé écrite
par `dd` avant de signaler le problème.

## 2. Démarrer en live (sans rien installer)

1. Brancher la clé, allumer, choisir la clé dans le menu de démarrage du firmware (Secure Boot désactivé).
2. Dans GRUB, garder l'entrée par défaut : **« Essayer ou installer Ubuntu - Orange Pi 6 Plus (noyau
   Sky1 …) »**. L'autre entrée (« noyau Ubuntu generique ») n'a pas d'accélération graphique : secours
   seulement.
3. **Écran HDMI noir dès l'allumage** (avant même GRUB) : bug connu du BIOS, pas une panne. Appuyer sur
   **Ctrl+Alt+Suppr** pour redémarrer.

Dans le live, essayer simplement d'utiliser la carte : bureau, navigateur, son, vidéos, USB, réseau.

## 3. Installer (facultatif)

> ⚠️ **L'installation efface le disque choisi.** Installer sur un SSD vide ou de test, ou faire d'abord
> une sauvegarde complète du disque.

- L'installateur est celui d'Ubuntu (icône sur le bureau du live).
- **Avec deux SSD**, choisir le disque par son **modèle et sa taille**, jamais par son nom : `nvme0n1` et
  `nvme1n1` peuvent s'inverser d'un démarrage à l'autre. Depuis le live : `lsblk -o NAME,SIZE,MODEL`.
- Cocher « codecs tiers » (logiciels tiers) : sans eux, les lecteurs vidéo GNOME n'ont pas de décodeur
  H.264.
- Après l'installation, pour recevoir les corrections du noyau et des réglages par `sudo apt upgrade` :

  ```bash
  curl -fsSL https://www.bookworm-mon0.org/apt/setup.sh | sudo bash
  ```

## 4. Quoi tester

Tout ce que vous faites d'habitude avec la carte. En particulier :

- **Écrans** : HDMI, DisplayPort, deux écrans, résolutions, extinction et rallumage de l'écran.
- **Son** : HDMI, DisplayPort, prise jack ; le son revient-il après une extinction de l'écran ?
- **Vidéo** : VLC et le lecteur GNOME (Showtime), plein écran, YouTube dans le navigateur.
- **USB** : clés, disques, ports USB-C, clavier et souris.
- **Réseau** : les deux ports Ethernet, et une carte Wi-Fi M.2 si vous en avez une (jamais testé).
- **Disques** : second SSD NVMe.
- **Arrêt et redémarrage** : propres, sans attente anormale.
- **Durée** : laisser tourner longtemps (une nuit avec une vidéo, par exemple).

Notez aussi votre matériel : quantité de mémoire de la carte, version du BIOS (affichée par le rapport),
écrans, alimentation (modèle et puissance du chargeur USB-C).

## 5. Limitations déjà connues (inutile de les signaler)

- **Veille système désactivée** : la carte ne se réveille pas, la mise en veille est donc bloquée.
  L'extinction de l'écran, elle, fonctionne.
- **Écran HDMI noir au démarrage** : bug du BIOS, Ctrl+Alt+Suppr.
- **Showtime sur Ubuntu 26.04.1** : vidéo saccadée quand les commandes sont affichées par-dessus
  (fluide quand elles disparaissent). VLC est fluide.
- **HDR désactivé** : l'activer faisait planter le bureau.
- **Blocage du GPU, rare** : surtout avec 3 ou 4 vidéos en même temps. Le GPU est remis en route tout seul
  en quelques secondes ; la session GNOME est gardée ou relancée (retour à l'écran de connexion). Ce cas
  est connu, mais un rapport reste utile s'il arrive en usage normal.
- **Décodage vidéo par le processeur** dans les lecteurs du bureau (le VPU sert à l'encodage et aux
  pipelines GStreamer explicites).

## 6. Envoyer un rapport

Le script `rapport-testeur.sh` (fourni avec ce guide, ou dans le dépôt GitHub
https://github.com/lpennisi73-tech/OPI6PLUS-UBUNTU, dossier `diagnostics/`) rassemble en un seul fichier
tout ce qu'il faut pour analyser un problème : versions, matériel, journaux du démarrage courant **et du
précédent**, plantages, journaux de l'installateur.

```bash
chmod +x rapport-testeur.sh
sudo ./rapport-testeur.sh
```

Il demande une courte description (ce qui s'est passé et vers quelle heure), puis écrit
`rapport-sky1-<date>.tar.gz` dans votre dossier personnel.

- **Après un plantage ou un redémarrage forcé** : redémarrer normalement, puis lancer le script. Il lit
  aussi le démarrage précédent, celui où le problème est arrivé. Ne pas attendre plusieurs redémarrages.
- **En live** : le fichier disparaît au redémarrage. Le copier sur une clé USB avant de redémarrer. (Le
  live ne garde pas les journaux d'un démarrage à l'autre : lancer le script **avant** de redémarrer.)
- **Même si tout va bien**, un rapport est utile : il montre que votre matériel fonctionne.

**Données personnelles** : le script retire le nom de la machine, les noms d'utilisateur, les adresses
MAC, IP et e-mail, les numéros de série des disques et périphériques, les empreintes de mots de passe et
les lignes réseau (Wi-Fi, DHCP). Il ne lit jamais le fichier de l'installateur qui contient le compte créé.
Le rapport est en texte clair : vous pouvez l'ouvrir et le relire avant de l'envoyer. Rien n'est envoyé
automatiquement.

Envoyez le fichier à la personne qui vous a transmis les ISO, avec si possible une photo de l'écran
quand quelque chose s'affiche mal.
