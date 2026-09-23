"""Validate a WoW 3.3.5a addon for Project Ebonhold -- without starting the game.

    python validate_addon.py <AddonFolder> [--no-smoke] [--strict]

Checks, in order:
  1. TOC      : Interface 30300, Title, every listed file exists (exact case), no
                unlisted .lua files, SavedVariables names actually written.
  2. SYNTAX   : every .lua file is compiled by a REAL Lua 5.1 (lupa) -- catches
                goto, //, &|~<<>>, integer division, >200 locals, etc.
  3. GLOBALS  : Lua 5.1 bytecode is decoded to list exact global reads/writes:
                - reads of names unknown to 3.3.5a + Ebonhold  -> WARN (retail API or typo)
                - leaked global writes (not namespaced)        -> WARN
  4. RETAIL   : regex lint for APIs that do not exist on 3.3.5a         -> ERROR
  5. XML      : .xml files are well-formed.
  6. SMOKE    : loads the TOC files in order inside a mocked 3.3.5a client, then
                fires ADDON_LOADED / PLAYER_LOGIN / PLAYER_ENTERING_WORLD and runs
                every slash command with "" -> runtime errors reported.

Set WOW_LOCALE=frFR to boot the mock client in another locale.

Exit code: 0 = no errors (warnings allowed), 1 = errors (or warnings with --strict).
Requires: pip install lupa
"""
import os
import re
import struct
import sys
import xml.dom.minidom

HERE = os.path.dirname(os.path.abspath(__file__))

# Addon text is UTF-8; a Windows console is usually cp1252. Never let printing crash.
try:
    sys.stdout.reconfigure(errors="replace")
    sys.stderr.reconfigure(errors="replace")
except AttributeError:  # pragma: no cover
    pass

try:
    from lupa import lua51
except ImportError:  # pragma: no cover
    print("ERROR: lupa is not installed. Run: pip install lupa")
    sys.exit(2)


# --------------------------------------------------------------------------- report
class Report:
    def __init__(self):
        self.errors, self.warnings, self.infos = [], [], []

    def error(self, where, msg):
        self.errors.append(f"{where}: {msg}")

    def warn(self, where, msg):
        self.warnings.append(f"{where}: {msg}")

    def info(self, where, msg):
        self.infos.append(f"{where}: {msg}")


# --------------------------------------------------------------------------- TOC
def parse_toc(path):
    meta, files = {}, []
    with open(path, encoding="utf-8-sig", errors="replace") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            if line.startswith("##"):
                m = re.match(r"##\s*([^:]+):\s*(.*)", line)
                if m:
                    meta[m.group(1).strip()] = m.group(2).strip()
            elif line.startswith("#"):
                continue
            else:
                files.append(line.replace("\\", "/"))
    return meta, files


def exact_case_exists(root, rel):
    cur = root
    for part in rel.split("/"):
        try:
            entries = os.listdir(cur)
        except OSError:
            return False, False
        if part in entries:
            cur = os.path.join(cur, part)
            continue
        lower = {e.lower(): e for e in entries}
        if part.lower() in lower:
            return True, False  # exists, wrong case
        return False, False
    return True, True


def check_toc(addon_dir, rep):
    name = os.path.basename(os.path.normpath(addon_dir))
    toc = os.path.join(addon_dir, name + ".toc")
    if not os.path.isfile(toc):
        rep.error("TOC", f"missing {name}.toc (the .toc must share the folder name)")
        return name, {}, []
    meta, files = parse_toc(toc)
    if meta.get("Interface") != "30300":
        rep.error("TOC", f"## Interface must be 30300 (got {meta.get('Interface')!r})")
    for key in ("Title", "Notes", "Version"):
        if key not in meta:
            (rep.error if key == "Title" else rep.warn)("TOC", f"missing ## {key}")
    listed = set()
    for rel in files:
        if os.path.basename(rel).lower() == "bindings.xml":
            rep.warn("TOC", "Bindings.xml must NOT be listed in the .toc: the client loads it by itself; "
                            "listing it logs 'Unknown frame type: Binding' in FrameXML.log")
        exists, exact = exact_case_exists(addon_dir, rel)
        if not exists:
            rep.error("TOC", f"listed file not found: {rel}")
        elif not exact:
            rep.warn("TOC", f"case mismatch for {rel} (works on Windows, fragile elsewhere)")
        listed.add(rel.lower())
        if not rel.lower().endswith((".lua", ".xml")):
            rep.warn("TOC", f"only .lua/.xml belong in the TOC (the client ignores the rest): {rel}")
    xml_includes = collect_xml_includes(addon_dir)
    for dirpath, dirs, fns in os.walk(addon_dir):
        dirs[:] = [d for d in dirs if d not in (".git", "tests", "tools", "docs")]
        for fn in fns:
            if fn.lower().endswith(".lua"):
                rel = os.path.relpath(os.path.join(dirpath, fn), addon_dir).replace("\\", "/")
                if rel.lower() not in listed and rel.lower() not in xml_includes:
                    rep.warn("TOC", f"{rel} is not listed in the TOC (never loaded)")
    return name, meta, files


_xml_cache = {}


def collect_xml_includes(addon_dir):
    if addon_dir in _xml_cache:
        return _xml_cache[addon_dir]
    found = set()
    for dirpath, _, fns in os.walk(addon_dir):
        for fn in fns:
            if fn.lower().endswith(".xml"):
                base = os.path.relpath(dirpath, addon_dir).replace("\\", "/")
                with open(os.path.join(dirpath, fn), encoding="utf-8", errors="replace") as fh:
                    for m in re.finditer(r'<(?:Script|Include)\s+file="([^"]+)"', fh.read()):
                        rel = m.group(1).replace("\\", "/")
                        found.add((rel if base == "." else base + "/" + rel).lower())
    _xml_cache[addon_dir] = found
    return found


# --------------------------------------------------------------------------- Lua 5.1 bytecode
OP_GETGLOBAL, OP_SETGLOBAL = 5, 7


class Chunk:
    def __init__(self, data):
        self.d, self.p = data, 0
        hdr = data[:12]
        if hdr[:4] != b"\x1bLua" or hdr[4] != 0x51:
            raise ValueError("not Lua 5.1 bytecode")
        self.little = hdr[6] == 1
        self.sint, self.ssize, self.sinstr, self.snum = hdr[7], hdr[8], hdr[9], hdr[10]
        self.p = 12

    def _u(self, size):
        fmt = {1: "B", 4: "I", 8: "Q"}[size]
        v = struct.unpack_from(("<" if self.little else ">") + fmt, self.d, self.p)[0]
        self.p += size
        return v

    def int(self):
        return self._u(self.sint)

    def string(self):
        n = self._u(self.ssize)
        if n == 0:
            return None
        s = self.d[self.p:self.p + n - 1]
        self.p += n
        return s.decode("utf-8", errors="replace")

    def function(self, out):
        self.string()  # source
        self.int(); self.int()  # linedefined, lastlinedefined
        self.p += 4  # nups, numparams, is_vararg, maxstacksize
        code = [self._u(self.sinstr) for _ in range(self.int())]
        consts = []
        for _ in range(self.int()):
            t = self._u(1)
            if t == 0:
                consts.append(None)
            elif t == 1:
                consts.append(bool(self._u(1)))
            elif t == 3:
                self.p += self.snum
                consts.append(0)
            elif t == 4:
                consts.append(self.string())
            else:
                raise ValueError("bad constant type %d" % t)
        for _ in range(self.int()):
            self.function(out)
        lines = [self.int() for _ in range(self.int())]
        for _ in range(self.int()):
            self.string(); self.int(); self.int()
        for _ in range(self.int()):
            self.string()
        for pc, ins in enumerate(code):
            op = ins & 0x3F
            if op in (OP_GETGLOBAL, OP_SETGLOBAL):
                bx = (ins >> 14) & 0x3FFFF
                name = consts[bx] if bx < len(consts) else None
                line = lines[pc] if pc < len(lines) else 0
                if isinstance(name, str):
                    out.append(("get" if op == OP_GETGLOBAL else "set", name, line))


def load_whitelist():
    names = set()
    with open(os.path.join(HERE, "api_globals_335.txt"), encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#"):
                names.add(line)
    return names


# --------------------------------------------------------------------------- retail lint
# (pattern, message). Matched on code with comments and strings blanked, except
# where the pattern itself targets a string (templates).
RETAIL = [
    (r":SetColorTexture\s*\(", "SetColorTexture does not exist -> tex:SetTexture(r, g, b, a)"),
    (r":SetShown\s*\(", "SetShown does not exist -> if cond then f:Show() else f:Hide() end"),
    (r":SetEnabled\s*\(", "SetEnabled does not exist -> btn:Enable() / btn:Disable()"),
    (r":SetAtlas\s*\(", "atlases do not exist on 3.3.5a -> SetTexture + SetTexCoord"),
    (r":SetResizeBounds\s*\(", "SetResizeBounds does not exist -> SetMinResize / SetMaxResize"),
    (r":SetFromAlpha\s*\(|:SetToAlpha\s*\(", "Alpha animations use :SetChange(delta) on 3.3.5a"),
    (r":SetClipsChildren\s*\(", "SetClipsChildren does not exist (use a ScrollFrame to clip)"),
    (r":SetIgnoreParentScale\s*\(|:SetIgnoreParentAlpha\s*\(", "SetIgnoreParent* does not exist"),
    (r":SetObeyStepOnDrag\s*\(", "SetObeyStepOnDrag does not exist (round the value in OnValueChanged)"),
    (r":RegisterUnitEvent\s*\(", "RegisterUnitEvent does not exist -> RegisterEvent + filter the unit arg"),
    (r":SetMouseClickEnabled\s*\(|:SetMouseMotionEnabled\s*\(", "does not exist -> EnableMouse(bool)"),
    (r"\bCombatLogGetCurrentEventInfo\b", "CLEU args are passed to OnEvent directly on 3.3.5a (no CombatLogGetCurrentEventInfo)"),
    (r"\bC_Container\b", "C_Container does not exist -> GetContainerItemInfo/GetContainerItemLink/..."),
    (r"\bC_Item\b|\bC_Spell\b|\bC_AddOns\b|\bC_ChatInfo\b|\bC_Map\b|\bC_CVar\b|\bC_UnitAuras\b|\bC_Covenants\b|\bC_QuestLog\b|\bC_TooltipInfo\b|\bC_EquipmentSet\b|\bC_PetJournal\b|\bC_FriendList\b|\bC_PartyInfo\b|\bC_Texture\b|\bC_CurrencyInfo\b",
     "retail C_ namespace -- does not exist on 3.3.5a"),
    (r"\bIsInGroup\s*\(|\bIsInRaid\s*\(|\bGetNumGroupMembers\s*\(|\bGetNumSubgroupMembers\s*\(",
     "group API is GetNumPartyMembers() / GetNumRaidMembers() / UnitInRaid on 3.3.5a"),
    (r"\bGetSpecialization\w*\s*\(", "no specializations on 3.3.5a -> talent points per tab (GetTalentTabInfo)"),
    (r"\bUnitIsTapDenied\b", "UnitIsTapDenied does not exist -> UnitIsTapped(unit) and not UnitIsTappedByPlayer(unit)"),
    (r"\bSOUNDKIT\b", "SOUNDKIT does not exist -> PlaySound(\"igMainMenuOpen\") with sound NAMES"),
    (r"\bEnum\.", "Enum table does not exist on 3.3.5a"),
    (r"\bMixin\s*\(|\bCreateFromMixins\s*\(|\bCreateAndInitFromMixin\s*\(", "Mixins do not exist -> copy methods manually"),
    (r"\bCreateColor\s*\(", "CreateColor does not exist -> plain {r,g,b} tables"),
    (r"\bGetClassColor\s*\(", "GetClassColor does not exist -> RAID_CLASS_COLORS[classToken]"),
    (r"\bUnitClassBase\s*\(", "UnitClassBase does not exist -> select(2, UnitClass(unit))"),
    (r"\bNineSliceUtil\b|\bScrollUtil\b|\bCreateDataProvider\b|\bCreateScrollBoxListLinearView\b|\bSettings\.Register",
     "retail UI framework -- does not exist on 3.3.5a"),
    (r"\btable\.unpack\b|\butf8\.|\bmath\.type\b|\bstring\.pack\b|\btable\.move\b", "Lua 5.2+ API -- 3.3.5a runs Lua 5.1 (use unpack, no utf8 lib)"),
    (r"\bGetAddOnEnableState\b|\bGetPhysicalScreenSize\b|\bUnitEffectiveLevel\b|\bIsPlayerSpell\b|\bGetMaxLevelForPlayerExpansion\b",
     "retail-only function"),
]
RETAIL_STRINGS = [
    (r"[\"']BackdropTemplate[\"']", "BackdropTemplate does not exist -- SetBackdrop is native on every frame"),
    (r"[\"'](?:BasicFrameTemplate\w*|ButtonFrameTemplate|PortraitFrameTemplate|UIPanelButtonNoTooltipTemplate|SharedButtonSmallTemplate)[\"']",
     "retail frame template -- use UIPanelButtonTemplate / UIPanelCloseButton / DialogBox backdrop"),
    (r"[\"']OnEnter[\"']\s*,\s*function\s*\(\s*self\s*,\s*motion", None),  # fine, placeholder
]

GUARDED_EXT = {"C_Timer", "C_Json", "C_MountJournal", "C_NamePlate", "C_VoiceChat"}
# Plain functions added by the AwesomeWotLK client extension: present on Ebonhold, absent on a stock client.
GUARDED_FUNCS = ("GetItemInfoInstant", "CopyToClipboard", "GetSpellBaseCooldown", "GetInventoryItemTransmog",
                 "UnitIsControlled", "FlashWindow", "IsWindowFocused")
PROTECTED = re.compile(
    r"\b(CastSpellByName|CastSpellByID|CastSpell|UseAction|TargetUnit|AssistUnit|FocusUnit|ClearTarget|"
    r"RunMacro|RunMacroText|SpellStopCasting|UseItemByName|UseInventoryItem|TargetNearestEnemy|"
    r"MoveForwardStart|JumpOrAscendStart|PetAttack|CancelUnitBuff|ChangeActionBarPage)\s*\("
)


def blank_comments_strings(src):
    """Replace comments and string contents with spaces, keeping line numbers."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i + len(m.group(0)))
                j = n if j < 0 else j + len(close)
            else:
                j = src.find("\n", i)
                j = n if j < 0 else j
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
        elif c in "\"'":
            j = i + 1
            while j < n and src[j] != c and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            out.append(c + re.sub(r"[^\n]", " ", src[i + 1:j]) + (c if j < n else ""))
            i = j + 1
        elif c == "[" and re.match(r"\[(=*)\[", src[i:]):
            m = re.match(r"\[(=*)\[", src[i:])
            close = "]" + m.group(1) + "]"
            j = src.find(close, i + len(m.group(0)))
            j = n if j < 0 else j + len(close)
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def line_of(text, pos):
    return text.count("\n", 0, pos) + 1


def is_feature_guarded(matched, code_lines, line):
    """True when the retail API is feature-detected on the same line or the 3 lines above:
    `if f.SetShown then`, `type(C_Container) == "table"`, `pcall(...)`, `unpack or table.unpack`."""
    words = [w for w in re.findall(r"[A-Za-z_]\w*", matched) if w not in ("table", "string", "math")]
    if not words:
        return False
    name = re.escape(words[-1] if not words[0].startswith("C_") else words[0])
    window = "\n".join(code_lines[max(0, line - 4):line])
    guard = (rf"\.{name}\b(?!\s*\()|type\s*\(\s*[\w.:]*{name}\s*\)|\bpcall\b|\bif\s+[\w.]*{name}\b|"
             rf"\b{name}\s+then\b|\bor\s+[\w.]*{name}\b|\b{name}\s+or\b|\band\s+[\w.]*{name}\b(?!\s*\()|\bnot\s+[\w.]*{name}\b")
    return re.search(guard, window) is not None


# --------------------------------------------------------------------------- per-file checks
def read_source(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw, False
    return raw, True


def check_lua_file(lua, addon_dir, rel, whitelist, rep, all_sets, all_gets):
    path = os.path.join(addon_dir, rel)
    raw, utf8_ok = read_source(path)
    if not utf8_ok:
        rep.warn(rel, "file is not valid UTF-8 (accents will display as garbage in game)")
    compile_fn = lua.eval(
        "function(src, name) local f, e = loadstring(src, '@' .. name); "
        "if not f then return nil, e end; return string.dump(f), false end"
    )
    dumped, err = compile_fn(raw, rel.encode())
    if dumped is None:
        rep.syntax_failed = True
        rep.error(rel, "Lua 5.1 syntax error: " + (err.decode("utf-8", "replace") if isinstance(err, bytes) else str(err)))
        return
    refs = []
    try:
        ch = Chunk(dumped)
        ch.function(refs)
    except Exception as exc:  # decoding problem must never hide the rest
        rep.info(rel, f"bytecode analysis skipped ({exc})")
    for kind, name, line in refs:
        (all_sets if kind == "set" else all_gets).setdefault(name, []).append((rel, line))

    text = raw.decode("utf-8", errors="replace")
    code = blank_comments_strings(text)
    code_lines = code.split("\n")
    for pattern, msg in RETAIL:
        for m in re.finditer(pattern, code):
            line = line_of(code, m.start())
            if is_feature_guarded(m.group(0), code_lines, line):
                rep.info(f"{rel}:{line}", "guarded use of a retail-only API (fine): " + msg)
            else:
                rep.error(f"{rel}:{line}", msg)
    for pattern, msg in RETAIL_STRINGS:
        if not msg:
            continue
        for m in re.finditer(pattern, text):
            rep.error(f"{rel}:{line_of(text, m.start())}", msg)
    for m in PROTECTED.finditer(code):
        rep.warn(f"{rel}:{line_of(code, m.start())}",
                 f"{m.group(1)} is a PROTECTED function: it only works from a secure button "
                 "(SecureActionButtonTemplate) clicked by the player, never from addon code/timers")
    if re.search(r"\bthis\b\s*[:.]", code) or re.search(r"\barg1\b", code):
        rep.warn(rel, "uses legacy implicit globals this/arg1 -- use handler parameters (self, event, ...)")
    for fn in GUARDED_FUNCS:
        if re.search(r"%s\s*\(" % fn, code) and not re.search(
            r"(?:type\s*\(\s*%s\s*\)|%s\s+and|if\s+not\s+%s|if\s+%s|pcall\s*\(\s*%s)" % ((fn,) * 5), code
        ):
            rep.warn(rel, f"{fn} comes from the AwesomeWotLK client extension -- guard it "
                          f"(if {fn} then ... end) so the addon still works on a stock client")
    for ext in GUARDED_EXT:
        if re.search(r"\b%s\." % ext, code) and not re.search(
            r"(?:type\s*\(\s*%s\s*\)|\b%s\s+and\b|if\s+not\s+%s\b|if\s+%s\b|\b%s\s*~=\s*nil|%s\s+then)" % ((ext,) * 6), code
        ):
            rep.warn(rel, f"{ext} comes from a client extension that may be absent -- guard it "
                          f"(if {ext} and {ext}.X then ... else <OnUpdate fallback> end)")


def named_frames(addon_dir):
    """Globals created implicitly: CreateFrame(type, "Name") and XML name="..." attributes."""
    names = set()
    for dirpath, _, fns in os.walk(addon_dir):
        for fn in fns:
            low = fn.lower()
            if not low.endswith((".lua", ".xml")):
                continue
            with open(os.path.join(dirpath, fn), encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            if low.endswith(".lua"):
                names.update(re.findall(r"""CreateFrame\s*\(\s*["'][A-Za-z]+["']\s*,\s*["']([A-Za-z_][A-Za-z0-9_]*)["']""", text))
            else:
                names.update(re.findall(r'name="([A-Za-z_][A-Za-z0-9_]*)"', text))
    return names


def check_globals(addon_name, meta, all_sets, all_gets, whitelist, rep, frames=()):
    saved = set()
    for key in ("SavedVariables", "SavedVariablesPerCharacter"):
        for n in re.split(r"[,\s]+", meta.get(key, "")):
            if n:
                saved.add(n)
    for sv in saved:
        if sv not in all_sets and sv not in all_gets:
            rep.warn("TOC", f"SavedVariable {sv} is never used by the code")
    defined = set(all_sets) | set(frames)
    prefix = re.sub(r"[^a-z]", "", addon_name.lower())[:4]
    for name, sites in sorted(all_sets.items()):
        low = name.lower()
        if name in saved or name.startswith(("SLASH_", "BINDING_")) or (prefix and low.startswith(prefix)):
            continue
        rel, line = sites[0]
        if name in whitelist and re.match(r"[A-Z]", name) and not name.isupper():
            rep.warn(f"{rel}:{line}", f"assignment to '{name}' may OVERWRITE a Blizzard/Ebonhold global -- "
                                      "use hooksecurefunc / HookScript instead of replacing it (taint, breaks other addons)")
        elif name.isupper():
            rep.warn(f"{rel}:{line}", f"global constant write '{name}' -- prefix it with {addon_name.upper()}_ or make it local")
        else:
            rep.warn(f"{rel}:{line}", f"global write '{name}' leaks into _G -- make it local or prefix it with {addon_name}")
    deps = [d for key in ("Dependencies", "RequiredDeps", "OptionalDeps")
            for d in re.split(r"[,\s]+", meta.get(key, "")) if d]
    unknown = {}
    for name, sites in all_gets.items():
        if name in whitelist or name in defined or name in saved:
            continue
        if any(name.startswith(d) for d in deps):
            continue  # globals of a declared (optional) dependency
        unknown[name] = sites
    for name, sites in sorted(unknown.items()):
        rel, line = sites[0]
        more = f" (+{len(sites) - 1} more)" if len(sites) > 1 else ""
        rep.warn(f"{rel}:{line}", f"global '{name}' is not a known 3.3.5a/Ebonhold name -- typo, missing local, "
                                  f"or retail-only API{more}")


def check_xml(addon_dir, rep):
    for dirpath, _, fns in os.walk(addon_dir):
        for fn in fns:
            if fn.lower().endswith(".xml"):
                rel = os.path.relpath(os.path.join(dirpath, fn), addon_dir)
                try:
                    xml.dom.minidom.parse(os.path.join(dirpath, fn))
                except Exception as exc:
                    rep.error(rel, f"malformed XML: {exc}")


# --------------------------------------------------------------------------- smoke test
def smoke_test(addon_dir, addon_name, meta, files, whitelist, rep, with_ebonhold, own=()):
    """Boot the addon in a fresh mocked client. Pass 1 has ProjectEbonhold, pass 2 does not."""
    label = "SMOKE+PE" if with_ebonhold else "SMOKE-noPE"
    lua = lua51.LuaRuntime(encoding=None, unpack_returned_tuples=True)
    with open(os.path.join(HERE, "wow_mock.lua"), "rb") as fh:
        lua.execute(fh.read())
    mock = lua.eval("WOWMOCK")
    mock.SetKnown(lua.table_from([n.encode() for n in sorted(whitelist)]))
    events_path = os.path.join(HERE, "api_events_335.txt")
    if os.path.isfile(events_path):
        with open(events_path, encoding="utf-8") as fh:
            names = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
        mock.SetEvents(lua.table_from([n.encode() for n in names]))
    const_path = os.path.join(HERE, "api_constants_335.lua")
    if os.path.isfile(const_path):
        with open(const_path, "rb") as fh:
            mock.SetConstants(fh.read())
    for key, value in meta.items():
        mock.meta[key.encode()] = value.encode()
    for key in ("SavedVariables", "SavedVariablesPerCharacter"):
        for n in re.split(r"[,\s]+", meta.get(key, "")):
            if n:
                mock.saved[n.encode()] = True
    for n in own:
        mock.own[n.encode()] = True
    locale = os.environ.get("WOW_LOCALE")
    if locale:
        mock.locale = locale.encode()
    if with_ebonhold:
        mock.InstallEbonhold()
    else:
        mock.RemoveEbonhold()
    ns_holder = mock.NewNamespace()
    for rel in files:
        if not rel.lower().endswith(".lua"):
            continue
        path = os.path.join(addon_dir, rel)
        if not os.path.isfile(path):
            continue
        raw, _ = read_source(path)
        err = mock.LoadFile(raw, rel.encode(), addon_name.encode(), ns_holder)
        if err:
            rep.error(f"{label} {rel}", "error while loading: " + err.decode("utf-8", "replace"))
    errs = mock.Boot(addon_name.encode())
    scenario = os.path.join(addon_dir, "tests", "scenario.lua")
    if os.path.isfile(scenario):
        with open(scenario, "rb") as fh:
            errs = mock.RunScenario(fh.read())
        rep.info(label, "tests/scenario.lua executed")
    for i in range(1, len(errs) + 1):
        rep.error(label, errs[i].decode("utf-8", "replace"))
    notes = mock.notes
    for i in range(1, len(notes) + 1):
        rep.info(label, notes[i].decode("utf-8", "replace"))


# --------------------------------------------------------------------------- main
def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__)
        return 2
    addon_dir = os.path.abspath(args[0])
    rep = Report()
    whitelist = load_whitelist()
    lua = lua51.LuaRuntime(encoding=None, unpack_returned_tuples=True)

    addon_name, meta, files = check_toc(addon_dir, rep)
    all_sets, all_gets = {}, {}
    seen = set()
    lua_files = [f for f in files if f.lower().endswith(".lua")]
    for dirpath, dirs, fns in os.walk(addon_dir):
        dirs[:] = [d for d in dirs if d not in (".git", "tests", "tools", "docs")]
        for fn in fns:
            if fn.lower().endswith(".lua"):
                rel = os.path.relpath(os.path.join(dirpath, fn), addon_dir).replace("\\", "/")
                if rel not in lua_files:
                    lua_files.append(rel)
    for rel in lua_files:
        if rel.lower() in seen or not os.path.isfile(os.path.join(addon_dir, rel)):
            continue
        seen.add(rel.lower())
        check_lua_file(lua, addon_dir, rel, whitelist, rep, all_sets, all_gets)
    check_globals(addon_name, meta, all_sets, all_gets, whitelist, rep, named_frames(addon_dir))
    check_xml(addon_dir, rep)
    if meta.get("Dependencies") or meta.get("RequiredDeps"):
        rep.info("SMOKE", "skipped: the addon has hard ## Dependencies that the mock cannot provide")
    elif "--no-smoke" not in argv and not getattr(rep, "syntax_failed", False)             and not any(e.startswith("TOC:") for e in rep.errors):
        own = set(all_sets)
        smoke_test(addon_dir, addon_name, meta, files, whitelist, rep, with_ebonhold=True, own=own)
        smoke_test(addon_dir, addon_name, meta, files, whitelist, rep, with_ebonhold=False, own=own)

    print(f"=== {addon_name} ===")
    for label, items in (("ERROR", rep.errors), ("WARN ", rep.warnings), ("info ", rep.infos)):
        for item in items:
            print(f"[{label}] {item}")
    print(f"--- {len(rep.errors)} error(s), {len(rep.warnings)} warning(s)")
    if rep.errors or ("--strict" in argv and rep.warnings):
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
