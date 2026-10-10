#!/usr/bin/env python3
"""Writes icons.json, the spec for Ovyl's in-app icons, for the tasteful-icons
skill. The gear's outline is computed here; everything else is plain paths.

    python3 design/icons/make-spec.py
    python3 <tasteful-icons>/scripts/tasteful_icons.py build design/icons/build --spec design/icons/icons.json
"""
import json
import math
import os


def rrect(x, y, w, h, r):
    return (f"M{x + r} {y}H{x + w - r}A{r} {r} 0 0 1 {x + w} {y + r}V{y + h - r}"
            f"A{r} {r} 0 0 1 {x + w - r} {y + h}H{x + r}A{r} {r} 0 0 1 {x} {y + h - r}"
            f"V{y + r}A{r} {r} 0 0 1 {x + r} {y}Z")


def circle(cx, cy, r):
    return f"M{cx - r} {cy}A{r} {r} 0 1 1 {cx + r} {cy}A{r} {r} 0 1 1 {cx - r} {cy}Z"


def gear(cx=256, cy=258, teeth=8, outer=160, root=126, tip=9.5, base=16):
    """A gear: flat-topped teeth joined by arcs on the root circle."""
    def at(r, deg):
        a = math.radians(deg - 90)
        return cx + r * math.cos(a), cy + r * math.sin(a)
    step = 360 / teeth
    d = []
    for i in range(teeth):
        c = i * step
        p = [at(root, c - base), at(outer, c - tip), at(outer, c + tip), at(root, c + base)]
        d.append(("M" if i == 0 else "L") + f"{p[0][0]:.1f} {p[0][1]:.1f}")
        d.append(f"L{p[1][0]:.1f} {p[1][1]:.1f}")
        d.append(f"A{outer} {outer} 0 0 1 {p[2][0]:.1f} {p[2][1]:.1f}")
        d.append(f"L{p[3][0]:.1f} {p[3][1]:.1f}")
        n = at(root, c + step - base)
        d.append(f"A{root} {root} 0 0 1 {n[0]:.1f} {n[1]:.1f}")
    return "".join(d) + "Z"


HOUSE = ("M236 118Q256 102 276 118L392 216Q410 232 392 246L372 246V362Q372 404 330 404H182"
         "Q140 404 140 362V246H120Q102 232 120 216Z")
BUBBLE = ("M256 116C350 116 418 172 418 246C418 320 350 376 256 376C238 376 221 374 205 370"
          "L138 400L150 342C116 318 94 284 94 246C94 172 162 116 256 116Z")
SPARKLES = ("M240 130Q268 244 382 272Q268 300 240 414Q212 300 98 272Q212 244 240 130Z"
            "M356 96Q366 140 410 150Q366 160 356 204Q346 160 302 150Q346 140 356 96Z")

# Every icon is Beam green, the app's one accent, except Delete, which is red
# as the app's other warnings of loss are.
ACCENT = "#B0C246"
DANGER = "#FF3B30"

icons = [
    # The sidebar.
    {"name": "home", "title": "Home", "color": ACCENT, "glyph": HOUSE,
     "marks": [{"d": rrect(224, 290, 64, 82, 24), "fill": True}]},
    {"name": "new", "title": "New", "color": ACCENT, "glyph": rrect(110, 112, 292, 292, 84),
     "marks": [{"d": "M256 194V322M192 258H320", "stroke": 34}]},
    {"name": "settings", "title": "Settings", "color": ACCENT, "glyph": gear(),
     "marks": [{"d": circle(256, 258, 46), "fill": True}]},
    # A folder's glass alone, laid over a tile in the folder's own color in
    # the app; export.py takes the tile out.
    {"name": "folder-glass", "title": "Folder", "color": "#808080",
     "glyph": "M144 128H212Q232 128 245 143L258 158H368Q410 158 410 200V354Q410 396 368 396H144"
              "Q102 396 102 354V170Q102 128 144 128Z",
     "palette": {"pool": "#FFFFFF", "shadow": "#000000"}, "shadow": [0.28, 14, 12],
     "glass": {"milk": [0.9, 0.6], "pool_opacity": 0.25}},
    # Settings' panes.
    {"name": "speech", "title": "Speech", "color": ACCENT, "glyph": BUBBLE,
     "marks": [{"d": "M176 226V266M216 206V286M256 186V306M296 206V286M336 226V266", "stroke": 24}]},
    {"name": "screen-text", "title": "Screen Text", "color": ACCENT, "glyph": rrect(100, 112, 312, 230, 56),
     "parts": [{"d": rrect(184, 364, 144, 38, 19)}],
     "marks": [{"d": "M168 198H344", "stroke": 28}, {"d": "M168 258H290", "stroke": 22}]},
    {"name": "formatting", "title": "Formatting", "color": ACCENT, "glyph": rrect(132, 100, 248, 316, 64),
     "marks": [{"d": "M192 176H320", "stroke": 30},
               {"d": circle(198, 252, 15), "fill": True}, {"d": "M242 252H318", "stroke": 22},
               {"d": circle(198, 324, 15), "fill": True}, {"d": "M242 324H298", "stroke": 22}]},
    {"name": "assistant", "title": "Assistant", "color": ACCENT, "glyph": SPARKLES,
     "glass": {"milk": [0.95, 0.75], "pool_opacity": 0.45}},
    # The bar under a note's media.
    {"name": "frames", "title": "Frames", "color": ACCENT,
     "glyph": rrect(112, 114, 128, 128, 36) + rrect(272, 114, 128, 128, 36)
              + rrect(112, 274, 128, 128, 36) + rrect(272, 274, 128, 128, 36)},
    {"name": "pictures", "title": "Pictures", "color": ACCENT, "glyph": rrect(100, 134, 312, 248, 56),
     "marks": [{"d": circle(330, 204, 24), "fill": True},
               {"d": "M156 336L216 268Q228 255 240 268L282 316L304 294Q316 283 328 294L360 336Z", "fill": True}]},
    {"name": "info", "title": "Info", "color": ACCENT, "glyph": circle(256, 258, 156),
     "marks": [{"d": circle(256, 184, 21), "fill": True}, {"d": "M256 244V334", "stroke": 34}]},
    {"name": "delete", "title": "Delete", "color": DANGER,
     "glyph": "M162 182H350Q364 182 362 196L346 372Q342 404 310 404H202Q170 404 166 372L150 196Q148 182 162 182Z",
     "parts": [{"d": "M140 126H212V116Q212 100 228 100H284Q300 100 300 116V126H372Q390 126 390 144"
                     "Q390 162 372 162H140Q122 162 122 144Q122 126 140 126Z"}],
     "marks": [{"d": "M222 232V350M290 232V350", "stroke": 22}]},
    {"name": "storage", "title": "Storage", "color": ACCENT,
     "glyph": rrect(108, 124, 296, 120, 44) + rrect(108, 272, 296, 120, 44),
     "marks": [{"d": "M166 184H262", "stroke": 22}, {"d": circle(344, 184, 18), "fill": True},
               {"d": "M166 332H262", "stroke": 22}, {"d": circle(344, 332, 18), "fill": True}]},
]

here = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(here, "icons.json"), "w") as f:
    json.dump({"icons": icons}, f, indent=2)
    f.write("\n")
print(f"wrote {len(icons)} icons to icons.json")
