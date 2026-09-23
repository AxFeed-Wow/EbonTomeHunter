"""Build api_globals_335.txt: every global name a 3.3.5a addon can legitimately read.

Sources:
  * the 3.3.5a FrameXML dump (https://github.com/wowgaming/3.3.5-interface-files):
    identifiers not preceded by '.' or ':' in every .lua/.xml file (a superset --
    it also catches locals, which only makes the lint more permissive);
  * GlobalStrings.lua keys;
  * a curated list of C API / Lua-environment names FrameXML never happens to use;
  * Project Ebonhold names (server addon, client DLL, client extensions).

Usage:
    git clone --depth 1 https://github.com/wowgaming/3.3.5-interface-files
    python build_whitelist.py <path-to-3.3.5-interface-files>
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "api_globals_335.txt")

IDENT = re.compile(r"(?<![.:\w])([A-Za-z_][A-Za-z0-9_]*)")
LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if",
    "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}

# Lua 5.1 + WoW-provided Lua helpers.
LUA_ENV = """
_G _VERSION assert collectgarbage error gcinfo getfenv getmetatable ipairs load loadstring next
newproxy pairs pcall print rawequal rawget rawset select setfenv setmetatable tonumber tostring
type unpack xpcall coroutine math string table os debug bit
abs acos asin atan atan2 ceil cos deg exp floor fmod frexp ldexp log log10 max min mod rad random
sin sqrt tan format gsub gmatch strbyte strchar strfind strlen strlower strmatch strrep strrev
strsub strupper strtrim strsplit strjoin strconcat tostringall tinsert tremove tContains wipe sort
foreach foreachi getn date time difftime debugstack debuglocals debugprofilestart debugprofilestop
geterrorhandler seterrorhandler securecall issecure issecurevariable hooksecurefunc forceinsecure
getglobal setglobal scrub
""".split()

# C API that exists on 3.3.5a (build 12340) but that FrameXML does not reference.
C_API_EXTRA = """
GetBuildInfo GetFramerate GetNetStats GetAddOnMetadata GetNumAddOns IsAddOnLoaded LoadAddOn
EnableAddOn DisableAddOn GetAddOnInfo IsAddOnLoadOnDemand RegisterAddonMessagePrefix
SendAddonMessage SendChatMessage GetChannelName JoinChannelByName LeaveChannelByName
GetItemInfo GetItemIcon GetItemCount GetItemSpell GetItemCooldown GetItemFamily GetItemStats
GetContainerNumSlots GetContainerItemInfo GetContainerItemLink GetContainerItemID
GetContainerNumFreeSlots GetContainerItemCooldown UseContainerItem PickupContainerItem
SplitContainerItem DeleteCursorItem ClearCursor CursorHasItem GetCursorInfo
GetSpellInfo GetSpellLink GetSpellTexture GetSpellCooldown IsSpellKnown IsUsableSpell
IsSpellInRange GetNumSpellTabs GetSpellTabInfo GetSpellName GetSpellBookItemInfo
UnitGUID UnitName UnitClass UnitRace UnitLevel UnitHealth UnitHealthMax UnitPower UnitPowerMax
UnitPowerType UnitExists UnitIsDead UnitIsGhost UnitAffectingCombat UnitAura UnitBuff UnitDebuff
UnitCastingInfo UnitChannelInfo UnitIsPlayer UnitIsUnit UnitReaction UnitCanAttack UnitFactionGroup
UnitClassification UnitCreatureType UnitSex UnitXP UnitXPMax GetXPExhaustion UnitInRaid UnitInParty
UnitIsPartyLeader UnitStat UnitArmor UnitAttackPower UnitRangedAttackPower UnitAttackSpeed UnitDamage
GetNumPartyMembers GetNumRaidMembers GetRaidRosterInfo IsInInstance GetInstanceInfo GetRealZoneText
GetZoneText GetSubZoneText GetMinimapZoneText GetRealmName GetLocale GetTime GetGameTime time date
InCombatLockdown IsMounted IsFlying IsSwimming IsIndoors IsOutdoors IsFlyableArea IsFalling IsStealthed
GetMoney GetCoinText GetCoinTextureString GetInventoryItemLink GetInventoryItemID GetInventoryItemTexture
GetInventorySlotInfo GetInventoryItemDurability GetAverageItemLevel GetCombatRating GetCritChance
GetSpellBonusDamage GetSpellCritChance GetDodgeChance GetParryChance GetBlockChance GetHitModifier
GetExpertise GetArmorPenetration GetManaRegen GetUnitSpeed GetPlayerFacing GetPlayerMapPosition
GetCurrentMapContinent GetCurrentMapZone SetMapToCurrentZone GetMapInfo GetNumQuestLogEntries
GetQuestLogTitle GetQuestLink GetNumQuestLeaderBoards GetQuestLogLeaderBoard SelectQuestLogEntry
GetGossipOptions GetGossipText SelectGossipOption GetNumGossipOptions CloseGossip
GetMerchantNumItems GetMerchantItemInfo GetMerchantItemLink BuyMerchantItem CloseMerchant
RepairAllItems CanMerchantRepair GetRepairAllCost GetNumTalentTabs GetTalentTabInfo GetTalentInfo
LearnTalent GetUnspentTalentPoints GetActiveTalentGroup GetNumTalentGroups SetActiveTalentGroup
GetNumCompanions GetCompanionInfo CallCompanion DismissCompanion Dismount GetShapeshiftForm
GetNumShapeshiftForms GetShapeshiftFormInfo GetTotemInfo GetRuneCooldown GetRuneType GetComboPoints
GetCursorPosition GetScreenWidth GetScreenHeight GetMouseFocus IsShiftKeyDown IsControlKeyDown
IsAltKeyDown IsModifiedClick GetBindingKey SetBinding SetBindingClick SaveBindings GetCVar SetCVar
GetCVarBool RegisterCVar PlaySound PlaySoundFile PlayMusic StopMusic ReloadUI Logout Quit
CreateFrame UIParent WorldFrame GameTooltip ItemRefTooltip Minimap DEFAULT_CHAT_FRAME ChatFrame1
SlashCmdList StaticPopupDialogs StaticPopup_Show StaticPopup_Hide UISpecialFrames
InterfaceOptions_AddCategory InterfaceOptionsFrame_OpenToCategory RAID_CLASS_COLORS
ITEM_QUALITY_COLORS GetItemQualityColor CombatLogGetCurrentEventInfo_NOT_ON_335
GetAchievementInfo GetAchievementLink GetStatistic GetCurrencyListInfo GetCurrencyListSize
GetNumMacros GetMacroInfo CreateMacro EditMacro GetActionInfo GetActionTexture HasAction
GetNumLootItems GetLootSlotInfo GetLootSlotLink LootSlot CloseLoot GetLootMethod
AcceptGroup DeclineGroup InviteUnit UninviteUnit LeaveParty ConvertToRaid
GetGuildInfo GetNumGuildMembers GetGuildRosterInfo GuildRoster IsInGuild
GetFriendInfo GetNumFriends ShowFriends AddFriend RemoveFriend
GetWhoInfo SendWho SetWhoToUI BNGetInfo BNGetNumFriends
TakeScreenshot Screenshot GetScreenResolutions GetCurrentResolution
SecureCmdOptionParse RegisterStateDriver UnregisterStateDriver RegisterUnitWatch
GetNumBattlefieldScores GetBattlefieldScore GetBattlefieldStatus GetWorldPVPAreaInfo
GetAuctionItemInfo GetAuctionItemLink GetNumAuctionItems QueryAuctionItems CanSendAuctionQuery
PlaceAuctionBid StartAuction GetSendMailItem SendMail GetInboxHeaderInfo GetInboxNumItems TakeInboxItem
GetTradeSkillInfo GetNumTradeSkills GetTradeSkillLine GetTradeSkillItemLink DoTradeSkill
GetProfessions_NOT_ON_335 GetSkillLineInfo GetNumSkillLines
UnitThreatSituation UnitDetailedThreatSituation GetThreatStatusColor
GetEquipmentSetInfo GetNumEquipmentSets UseEquipmentSet EquipItemByName
GetGlyphSocketInfo GetGlyphLink GetNumGlyphSockets
GetBindLocation GetMacroIcons GetMacroItemIcons GetMacroIndexByName GetMacroBody DeleteMacro PickupMacro
GetNumMounts_NOT_ON_335 UnitIsTapped UnitIsTappedByPlayer UnitIsTappedByAllThreatList GetQuestGreenRange
GetCompanionCooldown PickupCompanion SummonRandomCritter_NOT_ON_335 IsUsableItem IsEquippedItem
GetItemCooldown GetInventoryItemCooldown GetWeaponEnchantInfo GetPetActionInfo HasPetUI UnitCreatureFamily
GetNumTrainerServices GetTrainerServiceInfo BuyTrainerService GetGuildBankItemInfo GetGuildBankItemLink
GetCurrentGuildBankTab GetNumGuildBankTabs GetGuildBankTabInfo GetLFGDungeonInfo GetLFGMode
GetExistingSocketInfo GetNewSocketInfo GetSocketTypes GetItemGem GetMirrorTimerInfo GetMirrorTimerProgress
GetAddOnCPUUsage UpdateAddOnCPUUsage GetAddOnMemoryUsage UpdateAddOnMemoryUsage GetFunctionCPUUsage
GetScriptCPUUsage ResetCPUUsage GetFrameCPUUsage GetEventCPUUsage
""".split()

# Project Ebonhold: server addon globals, client-DLL functions, client extensions.
EBONHOLD = """
ProjectEbonhold ProjectEbonholdDB ProjectEbonholdOptionsService ProjectEbonholdEchoJournal
ProjectEbonholdEchoJournalScroll ProjectEbonholdEchoJournalMyRunScroll ProjectEbonholdPlayerRunFrame
EbonholdPlayerRunData ExtractionService TalentDatabase PerkDatabase utils HardmodeFrame SpecCustomNames
EbonholdOpenURL EbonholdLog EbonholdWorldToScreen EbonholdGetPlayerPosition EbonholdRequestQuestPOI
ExtBankOpen ExtBankMove ExtBankUnlock ExtBankSetActive ExtBank_OnPacket
CheckPatches GetPatchCheckResult FetchLoginMessage GetLoginMessageResult
C_Timer C_Json C_MountJournal C_NamePlate C_VoiceChat C_TTSSettings LibStub
EbonholdGetMeleeHitBonus EbonholdGetSpellHitBonus EbonholdHitDisplayReady EbonholdGetOverride
EbonholdSpellMapAddRule EbonholdSpellMapBeginRuleLoad EbonholdSpellMapReady EbonholdSpellMapAlive
CopyToClipboard GetItemInfoInstant GetSpellBaseCooldown GetInventoryItemTransmog UnitIsControlled
FlashWindow IsWindowFocused SetCollectionsJournalShown ToggleCollectionsJournal
""".split()


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    root = sys.argv[1]
    names = set(LUA_ENV) | {n for n in C_API_EXTRA if not n.endswith("_NOT_ON_335")} | set(EBONHOLD)
    constants = {}
    for dirpath, _, files in os.walk(root):
        if ".git" in dirpath:
            continue
        for fn in files:
            if not fn.lower().endswith((".lua", ".xml")):
                continue
            with open(os.path.join(dirpath, fn), encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            if fn.lower().endswith(".lua"):
                # top-level NAME = number / "string" assignments -> real values for the smoke-test mock
                for m in re.finditer(r'^([A-Z][A-Z0-9_]*)\s*=\s*(-?\d+(?:\.\d+)?|"(?:[^"\\]|\\.)*")\s*;?\s*(?:--.*)?$', text, flags=re.M):
                    constants.setdefault(m.group(1), m.group(2))
            if fn.lower().endswith(".xml"):
                # Only script bodies and name="..." attributes carry globals in XML.
                chunks = re.findall(r"<(?:On\w+|Script\w*)[^>]*>(.*?)</", text, flags=re.S)
                chunks += re.findall(r'\b(?:name|inherits|parentKey|function)="([^"$]+)"', text)
                text = "\n".join(chunks)
            for m in IDENT.finditer(text):
                word = m.group(1)
                if word not in LUA_KEYWORDS:
                    names.add(word)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("# Generated by build_whitelist.py -- global names valid on WoW 3.3.5a + Project Ebonhold\n")
        for n in sorted(names):
            fh.write(n + "\n")
    with open(os.path.join(HERE, "api_constants_335.lua"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("-- Generated by build_whitelist.py -- FrameXML constants with their 3.3.5a values\n")
        fh.write("return {\n")
        for k in sorted(constants):
            fh.write(f"  {k} = {constants[k]},\n")
        fh.write("}\n")
    print(f"wrote {len(names)} names to {OUT} and {len(constants)} constants")
    return 0


if __name__ == "__main__":
    sys.exit(main())
