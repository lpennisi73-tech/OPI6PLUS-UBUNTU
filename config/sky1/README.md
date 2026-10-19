# Config Sky1 de référence

`config.sky1-next` : config noyau complète du dépôt
[Sky1-Linux/linux-sky1](https://github.com/Sky1-Linux/linux-sky1) (`config/config.sky1-next`,
dernier commit amont `ae7763c` du 2026-02-28, copie identique).

Utilisée par `config/inject-sky1-config.sh` : la config de base est celle du noyau Ubuntu
`-generic` ; on y ajoute les options Sky1 obligatoires et recommandées, puis les options de
cette config absentes de la config Ubuntu. Copiée ici pour que le build ne dépende plus de
linux-sky1 (à l'arrêt depuis février 2026, aucune série pour 7.2).
