# =============================================================================
# dts-disable-cros-ec.py
# Désactiver l'EC ChromeOS (I2C 6, adresse 0x76) dans le DTS OrangePi 6 Plus
#
# Contexte:
#   Le DTS reprend de la carte de référence CIX (un portable) un EC
#   « google,cros-ec-i2c » avec batterie, charge, capot, rétroéclairage du
#   clavier, bouton marche et ventilateur. Sur l'OrangePi 6 Plus, rien ne
#   répond selon ce protocole : à chaque démarrage, cros-ec-i2c échoue
#   (« response of 0 bytes too short », « Failed to continue RWSIG: -74 »,
#   « Cannot identify the EC: error -71 ») et aucun de ses sous-nœuds n'est
#   utilisé. Ventilateur et bouton marche sont gérés par la carte elle-même.
#
# Fichier: arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts
# =============================================================================

import sys

TARGET = "arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts"

EC_DISABLE_BLOCK = """
/* No ChromeOS EC answers on this board (cros-ec-i2c: error -71).
 * Added by BOOKWORM Sky1 Kernel Builder
 */
&cros_ec {
\tstatus = "disabled";
};
"""

def apply_fix():
    try:
        with open(TARGET, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"ERREUR: {TARGET} introuvable")
        sys.exit(1)

    # Vérifier si déjà appliqué
    if EC_DISABLE_BLOCK.strip() in content:
        print("SKIP — EC déjà désactivé")
        sys.exit(0)

    if "cros_ec: ec@76 {" not in content:
        print("ERREUR: nœud cros_ec (ec@76) introuvable")
        sys.exit(1)

    with open(TARGET, 'w') as f:
        f.write(content.rstrip() + "\n" + EC_DISABLE_BLOCK)

    print("EC désactivé: &cros_ec (i2c6, 0x76)")

if __name__ == "__main__":
    apply_fix()
