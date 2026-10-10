#!/usr/bin/env python3
"""Kiem tra macro placement trong config.json truoc khi chay OpenLane.

- Doc SIZE that tu file LEF cua tung macro (khong hardcode).
- Bao loi neu 2 macro chong lan nhau hoac tran ra ngoai DIE_AREA.
- Canh bao neu khe ho giua cac macro qua hep de dinh tuyen / cap nguon.
"""
import json, os, re, sys, itertools

MIN_GAP = 30.0        # um: khe ho toi thieu khuyen nghi giua 2 macro
MIN_DIE_MARGIN = 20.0 # um: khoang cach toi thieu tu macro toi bien die

here = os.path.dirname(os.path.abspath(__file__))
cfg = json.load(open(os.path.join(here, "config.json")))


def resolve(p):
    return os.path.join(here, p[5:]) if p.startswith("dir::") else p


def lef_size(path):
    txt = open(path).read()
    m = re.search(r"SIZE\s+([\d.]+)\s+BY\s+([\d.]+)\s*;", txt)
    return float(m.group(1)), float(m.group(2))


dx0, dy0, dx1, dy1 = [float(v) for v in cfg["DIE_AREA"].split()]

boxes = []
for mname, mdef in cfg["MACROS"].items():
    w, h = lef_size(resolve(mdef["lef"] if isinstance(mdef["lef"], str) else mdef["lef"][0]))
    for inst, idef in mdef["instances"].items():
        x, y = idef["location"]
        o = idef.get("orientation", "N")
        # N/S/FN/FS giu nguyen W x H; E/W/FE/FW xoay 90 do
        bw, bh = (h, w) if o in ("E", "W", "FE", "FW") else (w, h)
        boxes.append((inst, mname, o, x, y, x + bw, y + bh))

errors, warns = [], []

print(f"DIE_AREA: ({dx0}, {dy0}) - ({dx1}, {dy1})\n")
for inst, mname, o, x0, y0, x1, y1 in sorted(boxes, key=lambda b: (b[3], b[4])):
    print(f"  {inst:34s} {mname:34s} {o:2s}  x {x0:8.2f}..{x1:8.2f}  y {y0:8.2f}..{y1:8.2f}")
    if x0 < dx0 or y0 < dy0 or x1 > dx1 or y1 > dy1:
        errors.append(f"{inst} nam ngoai DIE_AREA (x {x0:.2f}..{x1:.2f}, y {y0:.2f}..{y1:.2f})")
    else:
        m = min(x0 - dx0, y0 - dy0, dx1 - x1, dy1 - y1)
        if m < MIN_DIE_MARGIN:
            warns.append(f"{inst} chi cach bien die {m:.2f} um (< {MIN_DIE_MARGIN})")

for a, b in itertools.combinations(boxes, 2):
    ax0, ay0, ax1, ay1 = a[3:]
    bx0, by0, bx1, by1 = b[3:]
    ox = min(ax1, bx1) - max(ax0, bx0)
    oy = min(ay1, by1) - max(ay0, by0)
    if ox > 0 and oy > 0:
        errors.append(f"CHONG LAN {a[0]} <-> {b[0]}: {ox:.3f} x {oy:.3f} um")
    elif ox > 0 or oy > 0:          # cung hang hoac cung cot -> co khe ho
        gap = -min(ox, oy)
        if gap < MIN_GAP:
            warns.append(f"khe ho {a[0]} <-> {b[0]} chi {gap:.2f} um (< {MIN_GAP})")

print()
for w in warns:
    print("WARNING:", w)
for e in errors:
    print("ERROR:  ", e)
print(f"\n{len(errors)} loi, {len(warns)} canh bao")
sys.exit(1 if errors else 0)
