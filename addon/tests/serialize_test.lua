-- Unit test for the GuildPhone serialiser, with the WoW API stubbed.
-- Runs in plain Lua 5.1 - the same dialect the game uses.
local pass, fail = 0, 0
local function ok(c, m) if c then pass=pass+1; print("  PASS  "..m) else fail=fail+1; print("  FAIL  "..m) end end

-- ---- stubbed WoW API ----------------------------------------------------
local ROSTER = {
  -- name, rankName, rankIndex, level, _, zone, note, onote, online, status, class, ..., guid
  {"Thrallbane","Guild Master",0,60,nil,"Orgrimmar","","",true,"","WARRIOR",0,0,false,false,0,"Player-4呆-AAA1"},
  {"Grimfang",  "Officer",     2,60,nil,"Durotar",  "","",false,"","ROGUE", 0,0,false,false,0,"Player-4-BBB2"},
  {"Peon",      "Member",      5,42,nil,"Barrens",  "","",true,"","HUNTER",0,0,false,false,0,"Player-4-CCC3"},
}
-- The addon refuses to run outside WoW: Forever, so the stub must report a
-- Forever client or every test fails at the gate rather than at the thing
-- it is testing. 1.60.1 / interface 16001 is the beta client.
GetBuildInfo = function() return "1.60.1", "60100", "Sep 29 2026", 16001, 16001 end
IsInGuild   = function() return true end
GetGuildInfo= function() return "Test Guild", "Guild Master", 0 end
GetRealmName= function() return "Nightslayer" end
UnitFactionGroup = function() return "Horde" end
time        = function() return 1759100000 end
GetNumGuildMembers = function() return #ROSTER end
GetGuildRosterInfo = function(i) local r=ROSTER[i]; if not r then return nil end; return unpack(r) end
-- rank 4 deliberately has NO members: it must still appear in the export
local RANKS = {"Guild Master","Veteran","Officer","Raider","Trial","Member"}
GuildControlGetNumRanks = function() return #RANKS end
GuildControlGetRankName = function(i) return RANKS[i] end
C_GuildInfo = { GuildRoster = function() end }
UnitGUID = function() return "Player-4-AAA1" end
UnitName = function() return "Thrallbane" end
IsGuildLeader = function() return true end
CanGuildInvite = function() return true end
CanEditOfficerNote = function() return true end

local GP_ADDON = os.getenv("GP_ADDON") or "addon/GuildPhone"
local function gpload(f) dofile(GP_ADDON .. "/" .. f) end
gpload("Export.lua")
local GP = GuildPhone

print("== serializer ==")
local roster, err = GP.ReadRoster()
ok(roster ~= nil, "ReadRoster returned a roster" .. (err and (" ("..err..")") or ""))
ok(#roster.members == 3, "read 3 members")
ok(roster.faction == "Horde", "faction captured")
ok(roster.guild == "Test Guild", "guild name captured")

local nranks = 0; for _ in pairs(roster.ranks) do nranks = nranks + 1 end
ok(nranks == 6, "all 6 ranks captured, including ranks with no members (got "..nranks..")")
ok(roster.ranks[0] == "Guild Master", "rank index 0 is the GM (0-based roster vs 1-based control API)")
ok(roster.ranks[3] == "Raider", "empty rank 'Raider' present - members alone would never reveal it")

local s = GP.Serialize(roster)
ok(s:match("^GP1|Test Guild|Nightslayer|Horde|"), "header line well formed")
ok(select(2, s:gsub("\nR|","")) == 6, "6 rank rows emitted")
ok(select(2, s:gsub("\nM|","")) == 3, "3 member rows emitted")
ok(s:match("M|Player%-4%-BBB2|Grimfang|2|60|ROGUE"), "member row carries guid, name, rankIndex, level, class")

print("== authority line ==")
ok(s:match("\nS|Player%-4%-AAA1|Thrallbane|0|1|1|1"), "S line records who exported and their in-game authority")
IsGuildLeader = function() return false end
CanGuildInvite = function() return false end
CanEditOfficerNote = function() return false end
local r3 = GP.ReadRoster()
local s3 = GP.Serialize(r3)
ok(s3:match("\nS|[^|]*|[^|]*|0|0|0|0"), "a member with no guild permissions reports none")
IsGuildLeader = function() return true end
CanGuildInvite = function() return true end
CanEditOfficerNote = function() return true end

print("== checksum ==")
local body, sum = s:match("^(.*)\n#(%x+)$")
ok(body ~= nil and sum ~= nil, "export ends with a checksum")
ok(GP.Checksum(body) == sum, "checksum matches the body")
local tampered = body:gsub("Peon","Pwned")
ok(GP.Checksum(tampered) ~= sum, "a tampered body fails the checksum")

print("== escaping ==")
local r2 = { guild="A|B", realm="R", faction="Horde", exported=1, ranks={[0]="GM"},
             members={{guid="g1", name="Weird|Name", rankIndex=0, level=1, class="MAGE"}} }
local s2 = GP.Serialize(r2)
ok(not s2:match("Weird|Name"), "pipes in names are escaped, so fields cannot be forged")
ok(s2:match("Weird\\pName"), "escaped as \\p")

print("")

-- ---- the gate itself ----------------------------------------------------
-- The stub above reports Forever so the other tests reach the code they are
-- testing. That silently removes all coverage of the refusal path, which is
-- the whole reason the addon is Forever-only - so drive it explicitly here.
local real = GetBuildInfo
local function withClient(version, iface, fn)
    GetBuildInfo = function() return version, "x", "x", iface, iface end
    local a, b = fn()
    GetBuildInfo = real
    return a, b
end

ok(withClient("1.60.1", 16001, GP.IsForever) == true,
   "Forever 1.60.1 (16001) is supported")
ok(withClient("1.60.9", 16999, GP.IsForever) == true,
   "the whole 1.6x line is supported")
ok(withClient("1.15.4", 11404, GP.IsForever) == false,
   "Classic Era is refused")
ok(withClient("4.4.0", 40400, GP.IsForever) == false,
   "Cataclysm is refused")
ok(withClient("11.0.2", 110002, GP.IsForever) == false,
   "retail is refused")

local roster, why = withClient("1.15.4", 11404, GP.ReadRoster)
ok(roster == nil, "ReadRoster refuses outside Forever")
ok(type(why) == "string" and why:find("Forever"),
   "and says why, naming Forever")

local r2 = withClient("1.60.1", 16001, GP.ReadRoster)
ok(r2 ~= nil, "and reads normally once back on Forever")

print(("================  %d passed, %d failed  ================"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
