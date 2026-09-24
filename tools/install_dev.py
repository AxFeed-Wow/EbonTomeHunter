"""Installs the developer helper EbonTomeHunterDev (tools/dev) into the game. Never for players.

    python tools/install_dev.py [--wow C:/ebonhold]

The WoW folder comes from --wow, else the WOW_DIR environment variable, else C:/ebonhold.
A new addon is loaded only after a full restart of the game (not a /reload).
"""
import argparse
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "EbonTomeHunterDev"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wow", default=os.environ.get("WOW_DIR", "C:/ebonhold"))
    args = ap.parse_args()
    addons = os.path.join(args.wow, "Interface", "AddOns")
    if not os.path.isdir(addons):
        print(f"no Interface/AddOns in {args.wow} (use --wow)")
        return 1
    target = os.path.join(addons, NAME)
    if os.path.isdir(target):
        shutil.rmtree(target)
    shutil.copytree(os.path.join(HERE, "dev", NAME), target)
    print(f"{NAME} installed in {target}. Restart the game completely, then /ethdev.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
