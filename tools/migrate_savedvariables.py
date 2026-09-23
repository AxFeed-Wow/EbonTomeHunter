"""One-off migration of the saved data of the former name (EbonTomePrices 1.x) to EbonTomeHunter.

    python tools/migrate_savedvariables.py [--wow C:/ebonhold] [--dry-run] [--force]

WoW names the SavedVariables files after the addon folder, so renaming the addon starts it
empty. For every
    WTF/Account/<account>/SavedVariables/EbonTomePrices.lua                   (prices, network...)
    WTF/Account/<account>/<realm>/<character>/SavedVariables/EbonTomePrices.lua  (wishlist)
this writes EbonTomeHunter.lua next to it, with the global renamed
(EbonTomePricesDB -> EbonTomeHunterDB, EbonTomePricesCharDB -> EbonTomeHunterCharDB).
The old files are kept untouched. The game must be CLOSED (it rewrites the SavedVariables
when it quits). An existing EbonTomeHunter.lua is only replaced with --force.
"""
import argparse
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(errors="replace")
except AttributeError:
    pass

OLD, NEW = "EbonTomePrices", "EbonTomeHunter"
# bytes: the file is copied exactly as the game wrote it (CRLF line ends, any encoding)
GLOBALS = [(re.compile(rb"^EbonTomePricesDB(\s*=)", re.M), rb"EbonTomeHunterDB\1"),
           (re.compile(rb"^EbonTomePricesCharDB(\s*=)", re.M), rb"EbonTomeHunterCharDB\1")]


def game_running():
    if os.name != "nt":
        return False
    try:
        out = subprocess.run(["tasklist"], capture_output=True, text=True, errors="replace").stdout.lower()
    except OSError:
        return False
    return "ebonhold.exe" in out or "wow.exe" in out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wow", default=os.environ.get("WOW_DIR", "C:/ebonhold"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    wtf = os.path.join(args.wow, "WTF", "Account")
    if not os.path.isdir(wtf):
        print(f"no WTF/Account folder at {wtf}")
        return 2
    if game_running() and not args.dry_run:
        print("the game is running: close it first (it would overwrite the SavedVariables when it quits)")
        return 3
    found = 0
    for dirpath, _, filenames in os.walk(wtf):
        if os.path.basename(dirpath) != "SavedVariables" or OLD + ".lua" not in filenames:
            continue
        found += 1
        source = os.path.join(dirpath, OLD + ".lua")
        dest = os.path.join(dirpath, NEW + ".lua")
        rel = os.path.relpath(source, args.wow)
        if os.path.exists(dest) and not args.force:
            print(f"skip {rel}: {NEW}.lua already exists (--force to replace it)")
            continue
        with open(source, "rb") as fh:
            text = fh.read()
        renamed, count = text, 0
        for pattern, repl in GLOBALS:
            renamed, n = pattern.subn(repl, renamed)
            count += n
        if count == 0:
            print(f"skip {rel}: no {OLD} global inside")
            continue
        print(f"{'would write' if args.dry_run else 'write'} {os.path.relpath(dest, args.wow)} ({count} table(s))")
        if not args.dry_run:
            with open(dest, "wb") as fh:
                fh.write(renamed)
    if found == 0:
        print(f"no {OLD}.lua SavedVariables found: nothing to migrate")
    return 0


if __name__ == "__main__":
    sys.exit(main())
