#!/usr/bin/env python3
"""rej_newside.py <fichier.rej> <sortie> — écrit le contenu « après patch » d'un .rej
à un seul hunk couvrant tout le fichier (remplacement complet ou création)."""
import re, sys

lines = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read().split("\n")
hunks = [i for i, l in enumerate(lines) if l.startswith("@@")]
if len(hunks) != 1 or not re.match(r"@@ -[01],\d+ \+1,(\d+) @@", lines[hunks[0]]):
    sys.exit(f"{sys.argv[1]}: pas un remplacement complet à un seul hunk")
want = int(re.match(r"@@ -[01],\d+ \+1,(\d+) @@", lines[hunks[0]]).group(1))
out, no_eol = [], False
for l in lines[hunks[0] + 1:]:
    if l.startswith("\\"):
        no_eol = out and True
        continue
    if l[:1] in ("+", " "):
        out.append(l[1:])
    elif l[:1] == "-":
        continue
    elif l == "":
        continue
if len(out) != want:
    sys.exit(f"{sys.argv[1]}: {len(out)} lignes reconstruites, {want} attendues")
with open(sys.argv[2], "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write("\n".join(out) + ("" if no_eol else "\n"))
print(f"{sys.argv[2]}: {len(out)} lignes")
