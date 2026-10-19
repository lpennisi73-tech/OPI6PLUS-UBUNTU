#!/usr/bin/env python3
"""pick.py <fichier> <n> <amont|constructeur|both|texte:...|@fichier>
Résout le n-ième conflit (1 = premier restant) de <fichier> :
  amont         garde le côté amont (nouvelle base)
  constructeur  garde le côté constructeur
  both          amont puis constructeur
  texte:...     remplace par ce texte (\\n pour les retours ligne)
  @chemin       remplace par le contenu de ce fichier"""
import sys

path, n, how = sys.argv[1], int(sys.argv[2]), sys.argv[3]
lines = open(path, encoding="utf-8", errors="surrogateescape").read().split("\n")
out, i, k, done = [], 0, 0, False
while i < len(lines):
    if lines[i].startswith("<<<<<<< ") and not done:
        k += 1
        j = i + 1
        ours = []
        while not lines[j].startswith("======="):
            ours.append(lines[j]); j += 1
        j += 1
        theirs = []
        while not lines[j].startswith(">>>>>>> "):
            theirs.append(lines[j]); j += 1
        if k == n:
            if how == "amont": out += ours
            elif how == "constructeur": out += theirs
            elif how == "both": out += ours + theirs
            elif how.startswith("texte:"): out += how[6:].replace("\\n", "\n").replace("\\t", "\t").split("\n")
            elif how.startswith("@"): out += open(how[1:]).read().rstrip("\n").split("\n")
            else: sys.exit("choix inconnu")
            done = True
        else:
            out += lines[i:j + 1]
        i = j + 1
        continue
    out.append(lines[i]); i += 1
if not done:
    sys.exit(f"{path}: conflit {n} introuvable")
open(path, "w", encoding="utf-8", errors="surrogateescape").write("\n".join(out))
left = sum(1 for l in out if l.startswith("<<<<<<< "))
print(f"{path}: conflit résolu ({how.split(':')[0]}), {left} restant(s)")
