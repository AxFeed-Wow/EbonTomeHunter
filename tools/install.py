"""Installs the addon into World of Warcraft (Project Ebonhold client).

    python tools/install.py [--wow C:/ebonhold] [--remove-legacy] [--dry-run]

  * copies EbonTomeHunter/ (without tests/) to <wow>/Interface/AddOns/EbonTomeHunter;
  * the WoW folder comes from --wow, else the WOW_DIR environment variable, else C:/ebonhold;
  * the copy already installed is saved first to backups/<date>/ (not versioned);
  * files that no longer exist in the project are removed from the installed copy;
  * --remove-legacy also moves the folder of the former name (EbonTomePrices) to the backups:
    two copies of the addon must never be loaded together;
  * every installed file is compared with the project afterwards.
In game: /reload, or a FULL restart of the client when a file was added to the .toc.
"""
import argparse
import datetime
import filecmp
import os
import shutil
import subprocess
import sys

try:
    sys.stdout.reconfigure(errors="replace")
except AttributeError:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
NAME = "EbonTomeHunter"
LEGACY = "EbonTomePrices"
SOURCE = os.path.join(ROOT, NAME)
SKIP = {"tests"}


def game_running():
    if os.name != "nt":
        return False
    try:
        out = subprocess.run(["tasklist"], capture_output=True, text=True, errors="replace").stdout.lower()
    except OSError:
        return False
    return "ebonhold.exe" in out or "wow.exe" in out


def source_files():
    files = []
    for dirpath, dirnames, filenames in os.walk(SOURCE):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for name in filenames:
            files.append(os.path.relpath(os.path.join(dirpath, name), SOURCE))
    return sorted(files)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wow", default=os.environ.get("WOW_DIR", "C:/ebonhold"))
    ap.add_argument("--remove-legacy", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    addons = os.path.join(args.wow, "Interface", "AddOns")
    if not os.path.isdir(addons):
        print(f"no AddOns folder at {addons} (use --wow <World of Warcraft folder>)")
        return 2
    target = os.path.join(addons, NAME)
    legacy = os.path.join(addons, LEGACY)
    files = source_files()
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_root = os.path.join(ROOT, "backups", stamp)

    print(f"install {len(files)} files -> {target}")
    if args.dry_run:
        for f in files:
            print("  " + f)
        return 0
    if os.path.isdir(target):
        shutil.copytree(target, os.path.join(backup_root, NAME))
        print(f"previous version saved in {os.path.relpath(os.path.join(backup_root, NAME), ROOT)}")
    if args.remove_legacy and os.path.isdir(legacy):
        os.makedirs(backup_root, exist_ok=True)
        shutil.move(legacy, os.path.join(backup_root, LEGACY))
        print(f"former addon {LEGACY} moved to {os.path.relpath(os.path.join(backup_root, LEGACY), ROOT)}")
    elif os.path.isdir(legacy):
        print(f"WARNING: {legacy} is still installed: both would load (use --remove-legacy)")

    os.makedirs(target, exist_ok=True)
    wanted = set(files)
    for dirpath, _, filenames in os.walk(target, topdown=False):
        for name in filenames:
            rel = os.path.relpath(os.path.join(dirpath, name), target)
            if rel not in wanted:
                os.remove(os.path.join(dirpath, name))
                print(f"removed (no longer in the addon): {rel}")
        if dirpath != target and not os.listdir(dirpath):
            os.rmdir(dirpath)
    for rel in files:
        dest = os.path.join(target, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy2(os.path.join(SOURCE, rel), dest)

    bad = [rel for rel in files if not filecmp.cmp(os.path.join(SOURCE, rel), os.path.join(target, rel), shallow=False)]
    if bad:
        print("MISMATCH: " + ", ".join(bad))
        return 1
    print(f"OK: {len(files)} files identical to the project")
    if game_running():
        print("The game is running: /reload in game (full restart if a file was added to the .toc).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
