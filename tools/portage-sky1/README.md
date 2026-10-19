# Outils de portage de la série Sky1

Outils utilisés le 2026-10-16 pour porter `patches-next` de Sky1-Linux (base 7.0) sur
Linux 7.2.11 (`patches/sky1-7.2/`). Réutilisables pour un nouveau portage (7.2.x, 7.3…)
ou pour retoucher un patch de la série existante.

Langue des sorties : français. Aucun outil ne pousse quoi que ce soit ni ne touche à `linux-sky1`.

## Principe

Deux arbres git de travail, un tag `apres-NNNN` après chaque patch :

| Arbre | Contenu | Rôle |
|---|---|---|
| `REF_TREE` (défaut `/usr/src/build/sky1-kernel/ref-7.0`) | base d'origine + série d'origine | **l'état voulu** par chaque patch |
| `PORT_TREE` (défaut `.../port-7.2.11`) | nouvelle base + série portée | le portage en cours |

La série portée (`SERIES`, défaut `patches/sky1-7.2`) est modifiée **sur place** : faire un
commit avant de commencer, `git diff` montre ensuite chaque changement.

Paramètres dans `env.sh`, surchargeables par variable d'environnement
(`WORK_DIR`, `REF_TREE`, `PORT_TREE`, `SERIES`, `REJ_DIR`, `PORT_LABEL`).

## Outils

| Outil | Rôle | Modifie |
|---|---|---|
| `init-tree.sh <tarball> <dossier>` | extrait un noyau et en fait un dépôt git | crée le dossier |
| `triage.sh [début] [arbre] [série]` | applique la série à partir de `début`, un commit + tag par patch ; statut OK / AMONT / FUZZ / REJ(n) / +ABSENT ; hunks refusés dans `REJ_DIR` | l'arbre (reset) |
| `merge3.sh <num> <fichiers>` | fusion à trois voies (amont / base / constructeur) d'un patch en conflit | fichiers de `PORT_TREE` |
| `pick.py <fichier> <n> <choix>` | résout le n-ième conflit : `amont`, `constructeur`, `both`, `texte:…` (`\n`, `\t`), `@fichier` | le fichier |
| `rej_newside.py <.rej> <sortie>` | reconstruit un fichier entier depuis un `.rej` de remplacement/création complet | la sortie |
| `verify.sh <num> [adaptés…]` | lignes +/- identiques à la référence ? (`PEND=apres-<num>` pour un patch déjà commité) | rien |
| `anchors.py <num>…` | **audit d'emplacement** : chaque bloc ajouté a-t-il la même ligne d'ancrage que dans la référence ? | rien |
| `regen.sh <num>` | enregistre la résolution (commit + tag) et réécrit le fichier `.patch` (en-tête d'origine + note) | `PORT_TREE`, `SERIES` |
| `fixpatch.sh <num> <correctif.py>` | corrige un patch déjà strict (ex. mauvais placement) puis réapplique la suite | `PORT_TREE`, `SERIES` |
| `regen_all.sh` | réécrit toute la série depuis les tags (contexte rafraîchi, plus de fuzz) | `SERIES` |
| `check-strict.sh <tarball>` | test final : source vierge + série en `git apply` strict, comparée à `PORT_TREE` | rien (temporaire nettoyé) |

## Méthode (exemple : porter vers 7.3)

```bash
cd tools/portage-sky1
export PORT_TREE=/usr/src/build/sky1-kernel/port-7.3 SERIES=$PWD/../../patches/sky1-7.3 PORT_LABEL="Linux 7.3"
cp -r ../../patches/sky1-7.2 "$SERIES" && git -C ../.. add patches/sky1-7.3 && git -C ../.. commit -m "sky1-7.3: copie de départ"

./init-tree.sh /usr/src/build/sky1-kernel/linux-7.3.tar.xz "$PORT_TREE"
# REF_TREE : la base pour laquelle la série a été écrite + la série, tags compris.
# (ref-7.0 existe déjà ; sinon : ./init-tree.sh linux-7.0.tar.xz ref-7.0 && ./triage.sh 0000 <ref> <série d'origine>)

./triage.sh                      # 1er passage : liste OK / FUZZ / REJ
# Pour chaque patch REJ, dans l'ordre :
git -C "$PORT_TREE" reset -q --hard apres-<num-1>
patch -p1 -d "$PORT_TREE" --fuzz=3 -f < "$SERIES"/<num>-*.patch ; find "$PORT_TREE" -name '*.rej' -delete
./merge3.sh <num> <fichiers refusés>     # puis pick.py ou édition à la main
# compiler le sous-système touché, puis :
./verify.sh <num> <fichiers adaptés>
./regen.sh <num> && ./triage.sh <num+1>

./anchors.py $(seq -f '%04g' 1 43)       # OBLIGATOIRE : le fuzz place parfois mal un ajout
./regen_all.sh
./check-strict.sh /usr/src/build/sky1-kernel/linux-7.3.tar.xz
```

## Pièges rencontrés (7.0 → 7.2)

- **Le fuzz peut placer un ajout au mauvais endroit sans aucune erreur** : `verify.sh` ne le
  voit pas (mêmes lignes), seul `anchors.py` le détecte. Trois cas en 7.2 : une ligne
  `source "…/Kconfig"` insérée au milieu d'une aide Kconfig (options invisibles), un bloc
  avant l'allocation de la structure qu'il utilise, un appel déplacé avant la mise à jour
  dont il dépend.
- La série d'origine **n'est pas compilable à chaque étape** (un patch peut référencer un
  Kconfig créé plus loin) : pour compiler un sous-système en cours de route, créer un
  `Kconfig` vide temporaire si besoin, et faire la vraie compilation sur la série complète.
- `triage.sh` fait `git clean -fdx` : le `.config` de test est effacé à chaque reprise.
- Un patch « remplacement complet de fichier » (DT, pilotes réécrits) ne passe jamais par
  fuzz quand l'amont a modifié le fichier : `rej_newside.py` reconstruit la version voulue.
- **Compiler tous les dossiers touchés, pas seulement les patches en conflit** : un patch qui
  s'applique sans conflit peut ne plus compiler (API renommée/supprimée en amont). En 7.2 :
  `round_rate`, `drm_atomic_state`, `DRM_COLOR_FORMAT_*`, `drm_panel_init`… → patch 0044.
  Dans l'arbre de build (config réelle, après `make olddefconfig`) :
  `git -C "$PORT_TREE" diff --name-only <base> HEAD | grep '\.c$' | xargs -n1 dirname | sort -u | sed 's|$|/|' | xargs make -k -j$(nproc)`
- Simuler la config du build (`FORCE_BUILTIN` / `FORCE_DISABLED` du track) avant de rendre
  la main : c'est ce qui a révélé les options PHY disparues.

Détail des décisions du portage 7.2 : `patches/sky1-7.2/README.md`.
