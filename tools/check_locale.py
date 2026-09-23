"""Checks EbonTomeHunter/Locale.lua against the code.

    python tools/check_locale.py

  * every English key has a French translation (and the French table has no extra key);
  * every key used in the code (L.Key or L["Key"]) exists;
  * no key is left unused.
Exit code 0 when everything matches.
"""
import glob
import os
import re
import sys

try:
    sys.stdout.reconfigure(errors="replace")
except AttributeError:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(os.path.dirname(HERE), "EbonTomeHunter")
# Keys looked up indirectly (Share.Decode returns the key of its error message).
DYNAMIC = {"ShareCorrupt", "ShareNoString", "ShareVersion"}
KEY = re.compile(r'^\s+(\w+)\s*=\s*"', re.M)


def table(lines, opening):
    start = next(i for i, line in enumerate(lines) if line.startswith(opening))
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "}")
    return set(KEY.findall("\n".join(lines[start:end])))


def main(addon_dir=ADDON):
    lines = open(os.path.join(addon_dir, "Locale.lua"), encoding="utf-8").read().split("\n")
    english, french = table(lines, "local L = {"), table(lines, "local fr = {")
    used = set(DYNAMIC)
    for path in glob.glob(os.path.join(addon_dir, "*.lua")):
        if os.path.basename(path) == "Locale.lua":
            continue
        source = open(path, encoding="utf-8").read()
        used |= set(re.findall(r'\bL\.(\w+)', source)) | set(re.findall(r'\bL\["(\w+)"\]', source))
    problems = {
        "English keys without French text": sorted(english - french),
        "French keys that English does not have": sorted(french - english),
        "keys used in the code but not defined": sorted(used - english),
        "keys defined but never used": sorted(english - used),
    }
    failed = False
    for label, keys in problems.items():
        if keys:
            failed = True
            print(f"[ERROR] {label}: {', '.join(keys)}")
    print(f"locale: {len(english)} keys, {len(french)} translated, {len(used)} used -> {'FAIL' if failed else 'OK'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
