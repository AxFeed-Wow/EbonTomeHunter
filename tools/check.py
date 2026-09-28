"""Every check of the project, in one command. Run it after each change.

    python tools/check.py

  1. validator with an English client (static checks, smoke test with and without
     ProjectEbonhold, tests/scenario.lua);
  2. the same with a French client (WOW_LOCALE=frFR);
  3. locale coverage (tools/check_locale.py).
The network tests of the scenario run with the real EbonAPI (Siphelis) when it is found:
EBONAPI_DIR, else ../ModelAddonsEbonhold/EbonAPI/EbonAPI next to this repository, else the
AddOns folder of the game (WOW_DIR, else C:/ebonhold). It is read where it is, never copied
(its licence forbids redistributing it). Then 1 and 2 run with it, and the English one once
more without it (the player who has not installed it). Without it (CI), 1 and 2 run without.
A warning counts as a failure: the project keeps 0 errors and 0 warnings.
Exit code 0 when everything passes. Requires: pip install lupa
"""
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(errors="replace")
except AttributeError:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ADDON = os.path.join(ROOT, "EbonTomeHunter")
SUMMARY = re.compile(r"^--- (\d+) error\(s\), (\d+) warning\(s\)", re.M)


def find_ebonapi():
    """The EbonAPI addon folder (the one holding EbonAPI.toc), or None."""
    places = [os.environ.get("EBONAPI_DIR"),
              os.path.join(os.path.dirname(ROOT), "ModelAddonsEbonhold", "EbonAPI", "EbonAPI"),
              os.path.join(os.environ.get("WOW_DIR", "C:/ebonhold"), "Interface", "AddOns", "EbonAPI")]
    for place in places:
        if place and os.path.isfile(os.path.join(place, "EbonAPI.toc")):
            return os.path.abspath(place)
    return None


def validate(locale=None, ebonapi=None):
    env = dict(os.environ)
    if locale:
        env["WOW_LOCALE"] = locale
    else:
        env.pop("WOW_LOCALE", None)
    command = [sys.executable, os.path.join(HERE, "validate_addon.py"), ADDON]
    if ebonapi:
        command += ["--with", ebonapi]
    run = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env)
    output = run.stdout + run.stderr
    match = SUMMARY.search(output)
    errors, warnings = (int(match.group(1)), int(match.group(2))) if match else (-1, -1)
    label = f"validator ({locale or 'enUS'}, {'with EbonAPI' if ebonapi else 'without EbonAPI'})"
    if errors != 0 or warnings != 0:
        print(f"[FAIL] {label}: {errors} error(s), {warnings} warning(s)")
        for line in output.splitlines():
            if line.startswith(("[ERROR]", "[WARN")) or line.startswith("    "):
                print("   " + line)
        if not match:
            print(output[-3000:])
        return False
    print(f"[ OK ] {label}: 0 error, 0 warning")
    return True


def main():
    ebonapi = find_ebonapi()
    if ebonapi:
        print(f"[info] EbonAPI found: {ebonapi} (network tests with several players)")
    else:
        print("[info] EbonAPI not found (EBONAPI_DIR): network tests without it")
    ok = validate(None, ebonapi) and True
    ok = validate("frFR", ebonapi) and ok
    if ebonapi:
        ok = validate() and ok
    run = subprocess.run([sys.executable, os.path.join(HERE, "check_locale.py")],
                         capture_output=True, text=True, encoding="utf-8", errors="replace")
    print(("[ OK ] " if run.returncode == 0 else "[FAIL] ") + run.stdout.strip().replace("\n", "\n       "))
    ok = ok and run.returncode == 0
    print("ALL CHECKS PASSED" if ok else "SOME CHECKS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
