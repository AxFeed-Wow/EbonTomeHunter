"""Extracts the source of the ProjectEbonhold addon (shipped inside the client's MPQ archives) to
read its API locally:

    python tools/extract_pe_source.py [--client C:/ebonhold] [--out _extracted/ProjectEbonhold]

It is the server's code: for LOCAL reading only. Never commit it, never publish it
(_extracted/ is in .gitignore). The most useful files: projectebonhold.lua (every server message
code, CS / SS), modules/*/*_service.lua (the services the addon reads: PerkService,
CheckpointService...). Requires: pip install mpyq
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from extract_ebonhold_data import open_archives  # noqa: E402  (same MPQ priority order)

PREFIX = b"Interface\\AddOns\\ProjectEbonhold\\"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--client", default=os.environ.get("EBONHOLD_CLIENT", "C:/ebonhold"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(HERE), "_extracted", "ProjectEbonhold"))
    args = ap.parse_args()
    archives = open_archives(args.client)
    if not archives:
        print(f"no MPQ archives under {args.client}/Data")
        return 2
    written, skipped = {}, []
    for rel, arc in archives:            # highest priority first: the first copy of a file wins
        for key in arc.files or []:
            if not key.startswith(PREFIX) or key in written:
                continue
            try:
                data = arc.read_file(key)
            except Exception:            # a compression mpyq cannot read (some images): skip it
                skipped.append(key.decode("utf-8", "replace"))
                continue
            if data is None:
                continue
            path = os.path.join(args.out, *key[len(PREFIX):].decode("utf-8", "replace").split("\\"))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as fh:
                fh.write(data)
            written[key] = rel
    sources = sorted(set(written.values()))
    print(f"{len(written)} files of ProjectEbonhold -> {args.out} (from {', '.join(sources) or 'nothing'})")
    if skipped:
        lua = [k for k in skipped if k.lower().endswith((".lua", ".toc", ".xml"))]
        print(f"{len(skipped)} file(s) not readable by mpyq (unsupported compression), "
              f"{len(lua)} of them code: {', '.join(lua) if lua else 'none'}")
    return 0 if written else 1


if __name__ == "__main__":
    sys.exit(main())
