#!/usr/bin/env python3
"""anchors.py <num> [<num>...] — audit d'emplacement des ajouts.
Pour chaque patch, chaque fichier et chaque bloc de lignes ajoutées ('+'), compare la ligne
de contexte qui le précède immédiatement dans $REF_TREE et dans $PORT_TREE.
Signale les blocs dont l'ancrage diffère (ajout potentiellement mal placé)."""
import os, subprocess, sys

WORK = os.environ.get("WORK_DIR", "/usr/src/build/sky1-kernel")
TREES = {"ref": os.environ.get("REF_TREE", f"{WORK}/ref-7.0"),
         "port": os.environ.get("PORT_TREE", f"{WORK}/port-7.2.11")}

def git(tree, *a):
    return subprocess.run(["git", "-C", TREES[tree], *a], capture_output=True,
                          text=True, errors="surrogateescape").stdout

def blocks(diff):
    """{fichier: [(ancre, bloc_ajouté)]} — ancre = dernière ligne non '+' avant le bloc."""
    res, f, prev, cur = {}, None, None, []
    def flush():
        nonlocal cur
        if cur and f:
            res.setdefault(f, []).append((prev, "\n".join(cur)))
        cur = []
    for l in diff.split("\n"):
        if l.startswith("diff --git"):
            flush(); f = l.split(" b/", 1)[1]; prev = None; continue
        if l.startswith(("+++", "---", "index ", "new file", "deleted file", "similarity", "rename")):
            continue
        if l.startswith("@@"):
            flush(); prev = None; continue
        if l.startswith("+"):
            cur.append(l[1:]); continue
        flush()
        if l.startswith((" ", "-")):
            prev = l[1:]
    flush()
    return res

def first(tree, n):
    p = f"{int(n) - 1:04d}"
    return git(tree, "rev-list", "--max-parents=0", "HEAD").strip() if p == "0000" else f"apres-{p}"

bad = 0
for n in sys.argv[1:]:
    ref = blocks(git("ref", "diff", "-U3", first("ref", n), f"apres-{n}"))
    port = blocks(git("port", "diff", "-U3", first("port", n), f"apres-{n}"))
    for f, rb in ref.items():
        pmap = {}
        for anc, blk in port.get(f, []):
            pmap.setdefault(blk, []).append(anc)
        for anc, blk in rb:
            if anc is None:          # bloc en tête de hunk (fichier neuf, etc.)
                continue
            got = pmap.get(blk)
            if got is None:
                continue             # bloc adapté volontairement ou fusionné : vérifié ailleurs
            if anc not in got:
                bad += 1
                print(f"[{n}] {f}\n    ancre réf  : {anc.strip()[:90]!r}\n    ancre port : {got[0].strip()[:90] if got[0] else None!r}\n    bloc       : {blk.splitlines()[0].strip()[:90]!r}")
print(f"{bad} bloc(s) à ancrage différent")
