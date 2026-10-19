#!/usr/bin/env python3
# =============================================================================
# vpu-seek-test.py — Déplacement dans une vidéo pendant la mise en route du VPU
# BOOKWORM Sky1 Kernel Builder
#
# Reproduit ce que font les lecteurs qui reprennent une vidéo à la dernière position
# (GNOME Showtime) : mise en pause, déplacement avec vidage <délai> s plus tard, puis
# lecture. Compte les images décodées ensuite. Sans le patch 0046, le VPU restait
# bloqué (0 image) quand le déplacement arrivait avant la fin de sa mise en route.
# Aucune fenêtre : les images vont dans un fakesink.
#
# Usage: diagnostics/vpu-seek-test.py <vidéo.mkv> [position_s] [délai_s] [décodeur]
#        défauts : position 60 s, délai 0.01 s, décodeur v4l2h264dec (avdec_h264 = logiciel)
#        Conteneur MKV H.264 (matroskademux + h264parse).
# =============================================================================
import sys
import time

import gi

gi.require_version("Gst", "1.0")
from gi.repository import GLib, Gst  # noqa: E402

if len(sys.argv) < 2:
    sys.exit(__doc__ or "Usage: vpu-seek-test.py <vidéo.mkv> [position_s] [délai_s] [décodeur]")

path = sys.argv[1]
pos = float(sys.argv[2]) if len(sys.argv) > 2 else 60.0
delay = float(sys.argv[3]) if len(sys.argv) > 3 else 0.01
dec = sys.argv[4] if len(sys.argv) > 4 else "v4l2h264dec"

Gst.init(None)
p = Gst.parse_launch(
    f'filesrc location="{path}" ! matroskademux ! h264parse ! {dec} '
    "! fakesink name=s signal-handoffs=true sync=false"
)
frames = {"n": 0}
p.get_by_name("s").connect("handoff", lambda *a: frames.__setitem__("n", frames["n"] + 1))


def run(seconds):
    ctx = GLib.MainContext.default()
    end = time.time() + seconds
    while time.time() < end:
        ctx.iteration(False)
        time.sleep(0.005)


p.set_state(Gst.State.PAUSED)
run(delay)
p.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE, int(pos * Gst.SECOND))
run(1.5)
p.set_state(Gst.State.PLAYING)
run(3)
p.set_state(Gst.State.NULL)

ok = frames["n"] > 0
print(f"{dec} : déplacement à {pos:.0f} s, {delay:.2f} s après la pause : "
      f"{frames['n']} images en 3 s — {'OK' if ok else 'BLOQUÉ'}")
sys.exit(0 if ok else 1)
