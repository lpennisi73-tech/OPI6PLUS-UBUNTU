# Guide : cloner et restaurer le disque de l'Orange Pi 6 Plus

Outil : `scripts-addons/bookworm-clone.sh` (dd + zstd, avec vérifications).
Ce guide décrit le cas réel : sauvegarder le NVMe interne avant une installation, et le remettre
en état si quelque chose tourne mal.

---

## Ce qu'il faut

| | Sur cette machine |
|---|---|
| Disque à sauvegarder | NVMe interne **`nvme0n1`**, Crucial **CT1000T500SSD8**, 931,5 Go |
| Disque de sauvegarde | disque USB nommé **`BK_CLONE`** dans ce guide (à remplacer par le nom du vôtre), 1,8 To, exFAT |
| Clé live | clé Ventoy avec l'ISO BOOKWORM Sky1 (ou l'ISO Ubuntu officielle) |

- Le disque de sauvegarde doit être en **exFAT, ext4 ou NTFS**, jamais en FAT32 (fichiers limités à 4 Go,
  l'image fait plusieurs centaines de Go).
- Il lui faut de la place : jusqu'à la taille du NVMe dans le pire cas, beaucoup moins après un TRIM
  (étape 0 bis). Le script prévient s'il y en a moins que la taille du disque : après un TRIM, on peut
  répondre « o » (il s'arrête proprement si la place venait à manquer).
- Le NVMe se clone **depuis la clé live**, jamais depuis le système installé : un système en marche modifie
  ses fichiers pendant la copie, et le clone serait incohérent. Le script refuse de toute façon.

---

## 0. Préparer le disque de sauvegarde (une seule fois, depuis le système installé)

Copier le script et ce guide sur `BK_CLONE` :

```bash
mkdir -p /run/media/$USER/BK_CLONE/bookworm-clone
cp /usr/src/bookworm-sky1-kernel-ubuntu/scripts-addons/bookworm-clone.sh \
   /usr/src/bookworm-sky1-kernel-ubuntu/docs/guide-clonage.md \
   /run/media/$USER/BK_CLONE/bookworm-clone/
sync
```

---

## 0 bis. Juste avant chaque clonage : TRIM (depuis le système installé)

L'image contient **tout** le disque, espace libre compris. Les zones libérées par TRIM se relisent en zéros
et se compressent presque à rien ; les fichiers effacés depuis le dernier TRIM (builds du noyau, ISO…)
gardent leurs anciennes données, qui ne se compressent pas. Avant de redémarrer sur la clé live :

```bash
sudo fstrim -av
```

Il affiche ce qui a été libéré, par exemple `/ : 774 GiB … réduits`. L'image ne fera alors guère plus que
la place réellement occupée (environ 100 Go ici), au lieu de risquer de dépasser la place libre de `BK_CLONE`.
Ubuntu fait déjà un TRIM chaque semaine (`fstrim.timer`), mais le faire juste avant est plus sûr.

---

## 1. Cloner (sauvegarder) le NVMe

1. Brancher la clé Ventoy **et** le disque `BK_CLONE`, redémarrer, démarrer sur la clé
   (ISO BOOKWORM Sky1, première entrée du menu).
2. Dans le système live, choisir **« Essayer Ubuntu »** (ne rien installer), puis ouvrir un **Terminal**.
3. Aller dans le dossier du script (le bureau du live monte les disques dans `/run/media/ubuntu/`) :
   ```bash
   cd /run/media/ubuntu/BK_CLONE/bookworm-clone
   ```
   Si le dossier n'existe pas : ouvrir `BK_CLONE` une fois dans le gestionnaire de fichiers (cela le monte),
   puis réessayer.
4. Repérer les disques :
   ```bash
   sudo bash bookworm-clone.sh list
   ```
   Vérifier : **`nvme0n1`** = `CT1000T500SSD8`, 931,5G, **sans** point de montage ;
   **`sda`** (ou `sdb`…) = `BK_CLONE`, 1,8T, transport `usb`, monté dans `/run/media/ubuntu/BK_CLONE`.
5. Lancer le clonage :
   ```bash
   sudo bash bookworm-clone.sh save /dev/nvme0n1 /run/media/ubuntu/BK_CLONE
   ```
   Le script affiche le disque source et la destination, puis :
   1. enregistre la table de partitions et les identifiants du disque ;
   2. lit tout le NVMe (barre de progression de `dd`) et le compresse ;
   3. **décompresse toute l'image pour la vérifier** (aucune place en plus sur le disque, seulement du temps).
6. Attendre la fin. **Le clone n'est bon que si la dernière ligne verte est :**
   ```
   === Clonage terminé et vérifié ===
   ```
   et que le dossier de l'image est indiqué, par exemple `/run/media/ubuntu/BK_CLONE/clone-nvme0n1-20261018-1430`.
   **Noter ce nom de dossier.**
7. Démonter proprement avant de débrancher :
   ```bash
   sync
   ```
   puis « Éjecter » `BK_CLONE` dans le gestionnaire de fichiers.

Si un message rouge `ERREUR` s'affiche : **le clone n'est pas utilisable**. Ne pas lancer d'installation,
lire le message (voir « Messages » plus bas) et recommencer.

Durée : la lecture et la vérification prennent chacune le temps de lire environ 1 To ; compter largement
plus d'une heure en tout selon la vitesse du disque USB.

---

## 2. Avant de prendre un risque : vérifier qu'on a bien un bon clone

Depuis n'importe quel système (live ou installé), disque `BK_CLONE` branché :

```bash
sudo bash bookworm-clone.sh info /run/media/ubuntu/BK_CLONE/clone-nvme0n1-<date>
```

La ligne **« Dernière vérif. »** doit afficher une date. Pour un contrôle complet (plus long) :

```bash
sudo bash bookworm-clone.sh verify /run/media/ubuntu/BK_CLONE/clone-nvme0n1-<date>
```

Ce n'est qu'après ce contrôle qu'on peut installer, tester, casser… sans crainte.

---

## 3. Restaurer le NVMe (retour en arrière)

1. Brancher la clé Ventoy **et** `BK_CLONE`, démarrer sur la clé, **« Essayer Ubuntu »**, ouvrir un Terminal.
2. ```bash
   cd /run/media/ubuntu/BK_CLONE/bookworm-clone
   sudo bash bookworm-clone.sh list
   ```
   Vérifier que **`nvme0n1`** n'a **aucun point de montage**. Si le bureau a monté une de ses partitions
   (icône dans la barre latérale), l'éjecter d'abord.
3. Lancer la restauration :
   ```bash
   sudo bash bookworm-clone.sh restore /run/media/ubuntu/BK_CLONE/clone-nvme0n1-<date> /dev/nvme0n1
   ```
4. Le script affiche l'image (date, disque d'origine, n° de série) et le disque cible, puis **vérifie l'image
   avant d'écrire quoi que ce soit**. Si l'image est abîmée, il s'arrête : le NVMe n'est pas touché.
5. Il demande de **taper le nom du disque** : taper exactement
   ```
   nvme0n1
   ```
   puis Entrée. Toute autre réponse annule (rien n'est écrit).
6. Écriture, puis **relecture du NVMe et comparaison avec l'image**. La restauration n'est bonne que si
   la dernière ligne verte est :
   ```
   === Restauration terminée et vérifiée ===
   ```
7. Éteindre, retirer la clé Ventoy et `BK_CLONE`, rallumer : la machine redémarre sur le système sauvegardé,
   exactement dans l'état du clone (mêmes UUID, même GRUB, mêmes fichiers).

---

## Règles d'or

1. **Toujours cloner et restaurer depuis la clé live.**
2. **Lire deux fois le nom du disque** : `nvme0n1` = le NVMe interne à sauvegarder ou restaurer ;
   le disque USB de sauvegarde (`sda`…) ne doit **jamais** être la cible d'un `restore`.
3. **Un clone sans « terminé et vérifié » n'est pas un clone.**
4. **Ne pas débrancher** `BK_CLONE` pendant un clonage ou une restauration, et `sync` avant de l'éjecter.
5. Garder **au moins un clone vérifié** avant d'en supprimer un ancien.
6. Un seul `bookworm-clone.sh` à la fois sur un même disque.

---

## Messages

| Message | Signification | Que faire |
|---|---|---|
| `Partitions de /dev/nvme0n1 encore montées` | le NVMe est utilisé (système en marche ou partition montée par le bureau) | démarrer sur la clé live, éjecter les partitions du NVMe |
| `… porte le système en cours` | tentative de restaurer le disque du système qui tourne | démarrer sur la clé live |
| `n'est pas un disque entier` | une partition a été donnée (`/dev/nvme0n1p2`) | donner le disque : `/dev/nvme0n1` |
| `n'est pas sur un disque (mémoire ou système live)` | le dossier de destination est dans la mémoire du live | utiliser le dossier de `BK_CLONE` (`/run/media/ubuntu/BK_CLONE`) |
| `place libre … inférieure à la taille du disque` | le disque de sauvegarde risque d'être trop petit | libérer de la place ou accepter le risque (le script s'arrête proprement si ça déborde) |
| `échec de la copie … place insuffisante ?` | le disque de sauvegarde est plein ou a été débranché | libérer de la place, recommencer ; supprimer le dossier incomplet (fichier `.partial`) |
| `IMAGE NON CONFORME` / `échec de décompression` | l'image est abîmée | ne pas l'utiliser ; refaire un clone (et surveiller le disque de sauvegarde) |
| `trop petit` | le disque cible est plus petit que le disque cloné | restaurer sur un disque au moins aussi grand |
| `confirmation incorrecte` | le nom tapé n'est pas celui du disque | relancer et taper exactement le nom affiché |
| `le disque relu ne correspond PAS à l'image` | l'écriture sur la cible est défaillante | relancer la restauration ; si ça recommence, le disque cible est suspect |

---

## Contenu d'un dossier de clone

| Fichier | Rôle |
|---|---|
| `disk.img.zst` | l'image compressée du disque entier |
| `clone.info` | date, disque d'origine, modèle, n° de série, taille, empreintes SHA256, date de dernière vérification |
| `partitions.sfdisk` | table de partitions (lisible, restaurable seule avec `sfdisk`) |
| `lsblk.txt`, `blkid.txt` | partitions, systèmes de fichiers et UUID au moment du clone |
| `clone.log` | journal complet du clonage |

Ne pas modifier ni renommer les fichiers à l'intérieur du dossier ; le dossier lui-même peut être renommé.
