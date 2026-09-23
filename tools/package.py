"""Builds the release archive: dist/EbonTomeHunter-<version>.zip

    python tools/package.py

The zip holds one folder, EbonTomeHunter/, ready to drop into Interface/AddOns: every file of
the addon except tests/, plus LICENSE.txt. The version comes from the .toc (## Version) and
must be the same as ns.version in Core.lua (the script stops otherwise).
"""
import os
import re
import sys
import zipfile

try:
    sys.stdout.reconfigure(errors="replace")
except AttributeError:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
NAME = "EbonTomeHunter"
SOURCE = os.path.join(ROOT, NAME)


def main():
    toc = open(os.path.join(SOURCE, NAME + ".toc"), encoding="utf-8").read()
    core = open(os.path.join(SOURCE, "Core.lua"), encoding="utf-8").read()
    toc_version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
    core_version = re.search(r'ns\.version\s*=\s*"([^"]+)"', core).group(1)
    if toc_version != core_version:
        print(f"version mismatch: .toc {toc_version} / Core.lua {core_version}")
        return 1
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    out = os.path.join(ROOT, "dist", f"{NAME}-{toc_version}.zip")
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for dirpath, dirnames, filenames in os.walk(SOURCE):
            dirnames[:] = [d for d in dirnames if d != "tests"]
            for name in sorted(filenames):
                path = os.path.join(dirpath, name)
                zf.write(path, os.path.join(NAME, os.path.relpath(path, SOURCE)).replace("\\", "/"))
                count += 1
        license_path = os.path.join(ROOT, "LICENSE")
        if os.path.isfile(license_path):
            zf.write(license_path, f"{NAME}/LICENSE.txt")
            count += 1
    print(f"{os.path.relpath(out, ROOT)}: {count} files, version {toc_version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
