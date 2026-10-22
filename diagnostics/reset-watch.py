#!/usr/bin/python3 -I
# Surveille les registres de reset partagés du Sky1 (reset-controller@16000000) :
#   0x400 RESET_GROUP0_S0_DOMAIN_0 (GPU_RESET_N bit 6, DP_RESET4_N bit 25)
#   0x800 RESET_GROUP0_RCSU        (DP4_RCSU bit 18, GPU_RCSU bit 28)
# Lecture en boucle serrée (un cœur occupé) ; chaque changement est journalisé avec
# l'heure, pour voir si un reset du DP touche le bit du GPU.
# Usage : sudo diagnostics/reset-watch.py [fichier-journal]   (Ctrl+C pour arrêter)
import mmap, os, struct, sys, time

BASE = 0x16000000
REGS = {0x400: {"GPU": 6, "DP4": 25}, 0x800: {"DP4_RCSU": 18, "GPU_RCSU": 28}}

out = open(sys.argv[1], "a", buffering=1) if len(sys.argv) > 1 else sys.stdout
if out is sys.stdout:
    sys.stdout.reconfigure(line_buffering=True)
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
mem = mmap.mmap(fd, mmap.PAGESIZE, mmap.MAP_SHARED, mmap.PROT_READ, offset=BASE)


def rd(off):
    return struct.unpack_from("<I", mem, off)[0]


def stamp():
    t = time.time()
    return time.strftime("%H:%M:%S", time.localtime(t)) + f".{int(t % 1 * 1e6):06d}"


def bits(off, v):
    return " ".join(f"{n}={(v >> b) & 1}" for n, b in REGS[off].items())


last = {off: rd(off) for off in REGS}
for off, v in last.items():
    print(f"{stamp()} départ 0x{off:x}=0x{v:08x} {bits(off, v)}", file=out)
try:
    while True:
        for off in REGS:
            v = rd(off)
            if v != last[off]:
                print(f"{stamp()} 0x{off:x}: 0x{last[off]:08x} -> 0x{v:08x} {bits(off, v)}", file=out)
                last[off] = v
except KeyboardInterrupt:
    print(f"{stamp()} arrêt", file=out)
