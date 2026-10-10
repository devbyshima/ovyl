#!/usr/bin/env python3
"""Builds Ovyl's in-app icons with the tasteful-icons skill and puts them in
the asset catalog as icon-<name>.

    python3 design/icons/export.py [path to the tasteful-icons skill]

The skill defaults to ~/Dev/.claude/skills/tasteful-icons, or $TASTEFUL_ICONS.
The spec comes from make-spec.py. The SVGs and a preview are kept in
design/icons; 1024-point PNGs go to design/icons/build, which git ignores.
"""
import json
import os
import re
import shutil
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
skill = sys.argv[1] if len(sys.argv) > 1 else os.environ.get(
    "TASTEFUL_ICONS", os.path.expanduser("~/Dev/.claude/skills/tasteful-icons"))
build = os.path.join(here, "build")
catalog = os.path.join(root, "Ovyl", "Resources", "Assets.xcassets", "Icons")
size = 256

subprocess.run([sys.executable, os.path.join(here, "make-spec.py")], check=True)
shutil.rmtree(build, ignore_errors=True)
subprocess.run([sys.executable, os.path.join(skill, "scripts", "tasteful_icons.py"), "build", build,
                "--spec", os.path.join(here, "icons.json"), "--sizes", f"1024,{size}"], check=True)

# The folder's glass goes over a tile the app draws in the folder's color, so
# its own tile comes out.
folder = os.path.join(build, "svg", "folder-glass.svg")
with open(folder) as f:
    data = f.read()
data, removed = re.subn(r'\n  <path d="[^"]+" fill="url\(#folder-glass-bg\)"/>', "", data)
assert removed == 1, "the folder's tile wasn't found"
with open(folder, "w") as f:
    f.write(data)
for z in (1024, size):
    subprocess.run(["rsvg-convert", "-w", str(z), "-h", str(z), folder, "-o",
                    os.path.join(build, f"png@{z}", "folder-glass.png")], check=True)

# One single-scale image per icon, drawn at whatever size the app asks for.
shutil.rmtree(catalog, ignore_errors=True)
os.makedirs(catalog)
with open(os.path.join(catalog, "Contents.json"), "w") as f:
    json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
names = [e["name"] for e in json.load(open(os.path.join(here, "icons.json")))["icons"]]
for name in names:
    folder = os.path.join(catalog, f"icon-{name}.imageset")
    os.makedirs(folder)
    shutil.copy(os.path.join(build, f"png@{size}", f"{name}.png"), os.path.join(folder, f"{name}.png"))
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
# The SVGs and the preview are kept beside the spec; the PNGs are made again
# from the SVGs whenever they're needed.
shutil.rmtree(os.path.join(build, f"png@{size}"))
shutil.rmtree(os.path.join(here, "svg"), ignore_errors=True)
shutil.copytree(os.path.join(build, "svg"), os.path.join(here, "svg"))
shutil.copy(os.path.join(build, "preview.png"), os.path.join(here, "preview.png"))
print(f"put {len(names)} icons in {os.path.relpath(catalog, root)}")
