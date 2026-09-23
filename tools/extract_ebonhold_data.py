"""Extract Project Ebonhold game data from a local client install.

    python extract_ebonhold_data.py [--client C:/ebonhold] [--out <dir>] [--lua-tomes <file.lua>]
                                    [--lua-maps <file.lua>] [--seen <file.json>]

Reads (read-only):
  * Data/patch-*.MPQ        DBFilesClient/Spell.dbc, SpellIcon.dbc, Achievement.dbc, WorldMapArea.dbc,
                             AreaTable.dbc (custom versions shipped by the server) and
                             ProjectEbonhold's perks_data.lua
  * Cache/WDB/enUS/itemcache.wdb   item records the client has already seen (real tome item
                             names, quality, tooltip text). Optional: grows as you play, but the
                             client EMPTIES it now and then (restart after a patch...): the tome
                             items seen by any run are kept in ../reference/data/itemcache_seen.json
                             (--seen) and merged back, so a new run never loses them.

Writes into --out (default: ../reference/data next to this script):
  * custom_spells.json   every custom spell (id >= 100000): name, rank, description, icon path
  * tomes.json           the complete tome list (one per ProjectEbonhold requiredSpell), with the
                         REAL item id (== the tome spell id), item name, quality, linked echoes
  * achievements.json    custom achievements (id > 5000)
  * maps.json            continent / zone maps: WorldMapArea id, file name (GetMapInfo), world bounds
  * summary.txt          what each custom spell id range contains
With --lua-tomes, also writes a Lua data module for an addon: `local _, ns = ...; ns.TomeData = {...}`.
With --lua-maps, writes `ns.MapData = { maps = ..., hub = ... }`: world bounds of every map plus the
calibration of EbonholdHub's map images (to put its tome locations on the in-game world map).

Requires: pip install mpyq lupa
"""
import argparse
import json
import os
import re
import struct
import sys

try:
    sys.stdout.reconfigure(errors="replace")
except AttributeError:
    pass

try:
    import mpyq
except ImportError:
    print("ERROR: pip install mpyq")
    sys.exit(2)

HERE = os.path.dirname(os.path.abspath(__file__))
BS = chr(92)

# Later archives override earlier ones: custom letter/number patches win.
MPQ_PRIORITY = ["patch-X.MPQ", "patch-M.MPQ", "patch-I.MPQ", "patch-D.mpq", "patch-8.MPQ", "patch-6.MPQ",
                "patch-5.MPQ", "patch-4.MPQ", "enUS/patch-enUS-3.MPQ", "patch-3.MPQ", "patch-2.MPQ", "patch.MPQ"]

RANGES = [
    (100000, "Soul Ash skill tree nodes"),
    (200000, "Echoes (quality variants)"),
    (300000, "Tome spells (item id == spell id)"),
    (400000, "Utility (Loot Grip)"),
    (500000, "Difficulty buffs (Normal / Hard / Very Hard)"),
    (600000, "Difficulty debuffs, intensity mechanics"),
    (700000, "Affixes (weapon / armour procs)"),
    (900000, "Creature, boss and intensity mechanics"),
    (1000000, "Class Echoes"),
    (1200000, "Appearances (transmog collection)"),
    (2300000, "Mounts (collection)"),
]


def open_archives(client):
    archives = []
    for rel in MPQ_PRIORITY:
        path = os.path.join(client, "Data", rel)
        if os.path.isfile(path):
            try:
                archives.append((rel, mpyq.MPQArchive(path, listfile=True)))
            except Exception as exc:  # corrupt / locked archive: skip it
                print(f"warning: cannot open {rel}: {exc}")
    return archives


def read_first(archives, inner):
    key = inner.replace("/", BS).encode()
    for rel, arc in archives:
        if arc.files and key in arc.files:
            data = arc.read_file(key)
            if data:
                return rel, data
    return None, None


class DBC:
    def __init__(self, raw):
        magic, self.n, self.fields, self.size, self.strsize = struct.unpack_from("<4sIIII", raw, 0)
        if magic != b"WDBC":
            raise ValueError("not a WDBC file")
        self.raw = raw
        self.strbase = 20 + self.n * self.size

    def rows(self):
        for r in range(self.n):
            yield struct.unpack_from("<%dI" % self.fields, self.raw, 20 + r * self.size)

    def s(self, off):
        if not off or off >= self.strsize:
            return ""
        start = self.strbase + off
        return self.raw[start:self.raw.index(b"\0", start)].decode("utf-8", "replace")


def parse_spells(archives):
    rel, raw = read_first(archives, "DBFilesClient/Spell.dbc")
    if not raw:
        raise SystemExit("Spell.dbc not found in the client archives")
    icons = {}
    _, iraw = read_first(archives, "DBFilesClient/SpellIcon.dbc")
    if iraw:
        idbc = DBC(iraw)
        for f in idbc.rows():
            icons[f[0]] = idbc.s(f[1])
    dbc = DBC(raw)
    spells = {}
    for f in dbc.rows():
        if f[0] < 100000:
            continue
        # 3.3.5a layout: 133 SpellIconID, 136 SpellName[enUS], 153 Rank, 170 Description, 187 ToolTip
        spells[f[0]] = {
            "id": f[0], "name": dbc.s(f[136]), "rank": dbc.s(f[153]),
            "description": dbc.s(f[170]), "tooltip": dbc.s(f[187]), "icon": icons.get(f[133], ""),
        }
    print(f"Spell.dbc ({rel}): {dbc.n} spells, {len(spells)} custom")
    return spells


def parse_achievements(archives):
    rel, raw = read_first(archives, "DBFilesClient/Achievement.dbc")
    if not raw:
        return []
    dbc = DBC(raw)
    out = []
    for f in dbc.rows():
        if f[0] > 5000:
            out.append({"id": f[0], "title": dbc.s(f[4]), "description": dbc.s(f[21]),
                        "points": f[39], "reward": dbc.s(f[43])})
    print(f"Achievement.dbc ({rel}): {len(out)} custom achievements")
    return out


def parse_perks(archives, client):
    """PerkDatabase from ProjectEbonhold (patch-4.MPQ), evaluated by a real Lua 5.1."""
    rel, raw = read_first(archives, "Interface/AddOns/ProjectEbonhold/modules/perks/perks_data.lua")
    if not raw:
        print("warning: perks_data.lua not found, tomes will have no echo links")
        return {}
    from lupa import lua51
    lua = lua51.LuaRuntime(encoding=None, unpack_returned_tuples=True)
    lua.execute(b"ProjectEbonhold = {}")
    fn = lua.eval(b"function(src) local f = assert(loadstring(src, '@perks_data.lua')); f('ProjectEbonhold', {}) end")
    fn(raw)
    db = lua.eval(b"ProjectEbonhold.PerkDatabase")
    perks = {}
    for key in db.keys():
        row = db[key]
        comment = row[b"comment"]
        perks[int(key)] = {
            "spellId": int(key), "quality": int(row[b"quality"] or 0),
            "requiredSpell": int(row[b"requiredSpell"] or 0),
            "comment": comment.decode("utf-8", "replace") if comment else "",
            "classMask": int(row[b"classMask"] or 0), "maxStack": int(row[b"maxStack"] or 1),
        }
    print(f"PerkDatabase ({rel}): {len(perks)} echoes")
    return perks


def parse_itemcache(client):
    path = os.path.join(client, "Cache", "WDB", "enUS", "itemcache.wdb")
    if not os.path.isfile(path):
        return {}
    data = open(path, "rb").read()

    class R:
        def __init__(s, b): s.b, s.p = b, 0
        def u(s): v = struct.unpack_from("<I", s.b, s.p)[0]; s.p += 4; return v
        def i(s): v = struct.unpack_from("<i", s.b, s.p)[0]; s.p += 4; return v
        def f(s): v = struct.unpack_from("<f", s.b, s.p)[0]; s.p += 4; return v
        def s(s):
            e = s.b.index(b"\0", s.p); v = s.b[s.p:e].decode("utf-8", "replace"); s.p = e + 1; return v

    items, pos = {}, 24
    while pos + 8 <= len(data):
        entry, size = struct.unpack_from("<II", data, pos)
        pos += 8
        if entry == 0 and size == 0:
            break
        rec = R(data[pos:pos + size])
        pos += size
        try:
            item = {"id": entry, "class": rec.u(), "subclass": rec.u()}
            rec.i()
            item["name"] = rec.s(); rec.s(); rec.s(); rec.s()
            rec.u(); item["quality"] = rec.u(); rec.u(); rec.u()
            rec.u(); rec.u(); rec.u(); rec.i(); rec.i(); rec.u()
            item["requiredLevel"] = rec.u()
            rec.u(); rec.u(); rec.u()
            for _ in range(4): rec.u()
            rec.i(); item["stack"] = rec.i(); rec.u()
            for _ in range(rec.u()): rec.u(); rec.i()
            rec.u(); rec.u()
            for _ in range(2): rec.f(); rec.f(); rec.u()
            for _ in range(7): rec.u()
            rec.u(); rec.u(); rec.f()
            for _ in range(5): rec.i(); rec.u(); rec.i(); rec.i(); rec.u(); rec.i()
            item["bonding"] = rec.u()
            item["description"] = rec.s()
            items[entry] = item
        except Exception:
            continue
    print(f"itemcache.wdb: {len(items)} items")
    return items


def echo_name(comment):
    name = re.sub(r" - (Common|Uncommon|Rare|Epic|Legendary)$", "", comment or "")
    return re.sub(r"^(Warrior|Paladin|Hunter|Rogue|Priest|Death Knight|Shaman|Mage|Warlock|Druid) - ", "", name)


SEEN_DEFAULT = os.path.join(os.path.dirname(HERE), "reference", "data", "itemcache_seen.json")


def merge_seen(items, path):
    """The client empties its item cache now and then (new build, deleted Cache folder, restart
    after a patch): the tome items (300000-399999) seen by any run are kept in a JSON file and
    merged back, so a regeneration never loses the real names, qualities and tooltips."""
    seen = {}
    if path and os.path.isfile(path):
        try:
            seen = {int(k): v for k, v in json.load(open(path, encoding="utf-8")).items()}
        except (ValueError, OSError) as exc:
            print(f"warning: {path} unreadable ({exc}), starting a new one")
    fresh = 0
    for iid, item in items.items():
        if 300000 <= iid < 400000:
            seen[iid] = {"name": item["name"], "quality": item["quality"], "description": item.get("description", "")}
            fresh += 1
    merged = dict(items)
    for iid, rec in seen.items():
        merged.setdefault(iid, dict(rec, id=iid))
    if path:
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            json.dump({str(k): seen[k] for k in sorted(seen)}, fh, ensure_ascii=False, indent=1)
    print(f"tome items: {fresh} in the item cache now, {len(seen)} known ({os.path.basename(path or '-')})")
    return merged


def build_tomes(spells, perks, items):
    by_gate = {}
    for perk in perks.values():
        if 300000 <= perk["requiredSpell"] < 400000:
            by_gate.setdefault(perk["requiredSpell"], []).append(perk)
    tomes = []
    for tid in sorted(i for i in spells if 300000 <= i < 400000):
        spell = spells[tid]
        base = spell["name"][len("Tome of "):] if spell["name"].startswith("Tome of ") else spell["name"]
        linked = sorted(by_gate.get(tid, []), key=lambda p: p["spellId"])
        cached = items.get(tid)
        max_q = max((p["quality"] for p in linked), default=None)
        tomes.append({
            "itemId": tid,                                   # item id == tome spell id
            "itemName": cached["name"] if cached else "Tome of Echo: " + base,
            "itemNameVerified": bool(cached),
            "echoName": echo_name(linked[0]["comment"]) if linked else base,
            "quality": cached["quality"] if cached else (max_q + 1 if max_q is not None else 3),
            "echoes": [{"spellId": p["spellId"], "quality": p["quality"], "classMask": p["classMask"]} for p in linked],
            "description": (cached or {}).get("description") or spell["description"],
            "icon": spell["icon"],
        })
    return tomes


CONTINENT_NAMES = {"Azeroth": "Eastern Kingdoms", "Kalimdor": "Kalimdor", "Expansion01": "Outland", "Northrend": "Northrend"}

# Tome drop locations of EbonholdHub / EbonCompletionist (data of worldofechoes.pages.dev) are
# percentages of THEIR map images, not of the game's maps. World bounds (yards) of those images:
# the Eastern Kingdoms and Kalimdor images are world-scale mosaics of zone maps, located by
# registering every in-game zone map onto them (SIFT, ~10 000 matched points, residual < 0.2 % of
# the image); the Outland and Northrend images ARE the in-game continent maps (bounds = None: same
# as WorldMapArea's Expansion01 / Northrend, offset < 1 px).
HUB_IMAGES = {
    "eastern-kingdoms": {"map": 0, "continent": "Azeroth", "bounds": (3139.1, -6849.3, 4886.6, -15368.7)},
    "kalimdor": {"map": 1, "continent": "Kalimdor", "bounds": (4301.7, -8243.5, 11902.3, -11303.6)},
    "outland": {"map": 530, "continent": "Expansion01", "bounds": None},
    "northrend": {"map": 571, "continent": "Northrend", "bounds": None},
}


def parse_map_areas(archives):
    """Continent and zone maps of WorldMapArea.dbc, with their world bounds and English names."""
    rel, raw = read_first(archives, "DBFilesClient/WorldMapArea.dbc")
    if not raw:
        print("warning: WorldMapArea.dbc not found")
        return []
    names, cities = {}, set()
    _, araw = read_first(archives, "DBFilesClient/AreaTable.dbc")
    if araw:
        adbc = DBC(araw)
        for f in adbc.rows():
            names[f[0]] = adbc.s(f[11])   # AreaName, enUS
            if f[4] & 0x8:                # AREA_FLAG_SLAVE_CAPITAL: capital cities, Shattrath, Dalaran
                cities.add(f[0])

    def as_float(v):
        return struct.unpack("<f", struct.pack("<I", v))[0]

    dbc = DBC(raw)
    maps = []
    # 3.3.5a layout: 0 id, 1 map, 2 area, 3 file name, 4-7 left/right/top/bottom, 8 displayMapID,
    # 9 defaultDungeonFloor, 10 parentWorldMapID
    for f in dbc.rows():
        left, right, top, bottom = (as_float(v) for v in f[4:8])
        if f[1] not in (0, 1, 530, 571) or left == right:
            continue   # battlegrounds, dungeon floors
        file = dbc.s(f[3])
        # Eversong, Ghostlands, Quel'Danas, Azuremyst, Bloodmyst (and their cities) are on map 530
        # (bounds in its coordinates) but drawn on the Eastern Kingdoms / Kalimdor maps: shownOn.
        shown_on = None if f[8] == 0xFFFFFFFF else f[8]
        maps.append({"id": f[0], "map": f[1], "area": f[2], "file": file,
                     "name": CONTINENT_NAMES.get(file, file) if f[2] == 0 else names.get(f[2], file),
                     "continent": f[2] == 0, "city": f[2] in cities, "shownOn": shown_on,
                     "left": round(left, 2), "right": round(right, 2), "top": round(top, 2), "bottom": round(bottom, 2)})
    print(f"WorldMapArea.dbc ({rel}): {len(maps)} continent and zone maps")
    return maps


def lua_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "") + '"'


def write_lua_maps(maps, path):
    by_file = {m["file"]: m for m in maps}
    lines = [
        "-- GENERATED by extract_ebonhold_data.py --lua-maps from the client's WorldMapArea.dbc and",
        "-- AreaTable.dbc. Do not edit: regenerate after a server patch.",
        "-- maps[file] (file = GetMapInfo()): id = WorldMapArea id (SetMapByID(id); GetCurrentMapAreaID()",
        "--   returns id + 1 on 3.3.5a), map = instance id, name = English name, left/right/top/bottom =",
        "--   world bounds in yards. A world point on that map: x = (left - worldY) / (left - right),",
        "--   y = (top - worldX) / (top - bottom)   (0..1, from the top-left corner). shownOn = the",
        "--   continent whose map draws the zone (Eversong, Azuremyst...: on map 530, drawn on 0 / 1).",
        "-- hub[slug]: world bounds of the EbonholdHub / EbonCompletionist (worldofechoes) map images:",
        "--   their tome locations are percentages of these images.",
        "local _, ns = ...",
        "ns.MapData = {",
        "    maps = {",
    ]
    for m in sorted(maps, key=lambda m: (m["map"], not m["continent"], m["file"])):
        flags = (", continent = true" if m["continent"] else "") + (", city = true" if m["city"] else "")
        if m.get("shownOn") is not None:
            flags += f', shownOn = {m["shownOn"]}'
        lines.append(f'        [{lua_quote(m["file"])}] = {{ id = {m["id"]}, map = {m["map"]}, name = {lua_quote(m["name"])}{flags}, '
                     f'left = {m["left"]}, right = {m["right"]}, top = {m["top"]}, bottom = {m["bottom"]} }},')
    lines += ["    },", "    hub = {"]
    for slug, img in HUB_IMAGES.items():
        bounds = img["bounds"]
        if bounds is None:
            cont = by_file.get(img["continent"])
            if not cont:
                continue
            bounds = (cont["left"], cont["right"], cont["top"], cont["bottom"])
        lines.append(f'        [{lua_quote(slug)}] = {{ map = {img["map"]}, continent = {lua_quote(img["continent"])}, '
                     f'left = {bounds[0]}, right = {bounds[1]}, top = {bounds[2]}, bottom = {bounds[3]} }},')
    lines += ["    },", "}"]
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"wrote {path} ({len(maps)} maps)")


def write_lua_tomes(tomes, path):
    lines = [
        "-- GENERATED by extract_ebonhold_data.py from the client's Spell.dbc, ProjectEbonhold's",
        "-- PerkDatabase and the item cache. Do not edit: regenerate after a server patch.",
        "-- [itemId] = { name = item name, echo = echo name, quality = item quality,",
        "--              echoes = { echo spell ids }, verified = item name seen in game }",
        "local _, ns = ...",
        "ns.TomeData = {",
    ]
    for t in tomes:
        echoes = ", ".join(str(e["spellId"]) for e in t["echoes"])
        lines.append(f"    [{t['itemId']}] = {{ name = {lua_quote(t['itemName'])}, echo = {lua_quote(t['echoName'])}, "
                     f"quality = {t['quality']}, echoes = {{ {echoes} }}, verified = {'true' if t['itemNameVerified'] else 'false'}, "
                     f"desc = {lua_quote(t['description'] or '')} }},")
    lines.append("}")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"wrote {path} ({len(tomes)} tomes)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--client", default=os.environ.get("EBONHOLD_CLIENT", "C:/ebonhold"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(HERE), "reference", "data"))
    ap.add_argument("--lua-tomes")
    ap.add_argument("--lua-maps")
    ap.add_argument("--seen", default=SEEN_DEFAULT,
                    help="tome items seen in earlier runs (kept across item cache resets); '' = do not use")
    args = ap.parse_args()

    archives = open_archives(args.client)
    if not archives:
        print(f"no MPQ archives under {args.client}/Data")
        return 2
    spells = parse_spells(archives)
    achievements = parse_achievements(archives)
    perks = parse_perks(archives, args.client)
    items = merge_seen(parse_itemcache(args.client), args.seen)
    tomes = build_tomes(spells, perks, items)
    maps = parse_map_areas(archives)

    os.makedirs(args.out, exist_ok=True)
    json.dump(maps, open(os.path.join(args.out, "maps.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    json.dump(spells, open(os.path.join(args.out, "custom_spells.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    json.dump(tomes, open(os.path.join(args.out, "tomes.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    json.dump(achievements, open(os.path.join(args.out, "achievements.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    with open(os.path.join(args.out, "summary.txt"), "w", encoding="utf-8") as fh:
        for lo, label in RANGES:
            count = sum(1 for i in spells if lo <= i < lo + 100000)
            fh.write(f"{lo:>8}-{lo + 99999:<8} {count:>5}  {label}\n")
        fh.write(f"\ntomes: {len(tomes)} ({sum(t['itemNameVerified'] for t in tomes)} with an item name seen in game)\n")
        fh.write(f"custom achievements: {len(achievements)}\n")
    print(f"tomes: {len(tomes)} | data written to {args.out}")
    if args.lua_tomes:
        write_lua_tomes(tomes, args.lua_tomes)
    if args.lua_maps:
        write_lua_maps(maps, args.lua_maps)
    return 0


if __name__ == "__main__":
    sys.exit(main())
