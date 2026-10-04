-- Unit tests for the re-import reminder, WoW API stubbed. Plain Lua 5.1.
local pass, fail = 0, 0
-- io.write, not print: the addon's own print is silenced below so its chat
-- output does not pollute the test log.
local function ok(c,m)
  if c then pass=pass+1; io.write("  PASS  "..m.."\n") else fail=fail+1; io.write("  FAIL  "..m.."\n") end
end

local NOW = 1759100000
local ROSTER = {
  {"Thrallbane","Guild Master",0,60,nil,"Org","","",true,"","WARRIOR",0,0,false,false,0,"G-A"},
  {"Grimfang","Officer",2,60,nil,"Dur","","",false,"","ROGUE",0,0,false,false,0,"G-B"},
  {"Peon","Member",5,42,nil,"Bar","","",true,"","HUNTER",0,0,false,false,0,"G-C"},
}
-- The addon refuses to run outside WoW: Forever, so the stub must report a
-- Forever client or every test fails at the gate rather than at the thing
-- it is testing. 1.60.1 / interface 16001 is the beta client.
GetBuildInfo = function() return "1.60.1", "60100", "Sep 29 2026", 16001, 16001 end
IsInGuild=function() return true end
GetGuildInfo=function() return "Sig Guild","Guild Master",0 end
GetRealmName=function() return "Nightslayer" end
UnitFactionGroup=function() return "Alliance" end
time=function() return NOW end
GetNumGuildMembers=function() return #ROSTER end
GetGuildRosterInfo=function(i) local r=ROSTER[i]; if not r then return nil end; return unpack(r) end
local RANKS={"Guild Master","Veteran","Officer","Raider","Trial","Member"}
GuildControlGetNumRanks=function() return #RANKS end
GuildControlGetRankName=function(i) return RANKS[i] end
C_GuildInfo={GuildRoster=function() end}
UnitGUID=function() return "G-A" end
UnitName=function() return "Thrallbane" end
IsGuildLeader=function() return true end
CanGuildInvite=function() return true end
CanEditOfficerNote=function() return true end
-- frame / timer stubs so Remind.lua can load outside the game
CreateFrame=function() return { RegisterEvent=function() end, SetScript=function() end } end
C_Timer={ After=function() end }
print=function() end   -- silence the addon's own chat output

local GP_ADDON = os.getenv("GP_ADDON") or "addon/GuildPhone"
local function gpload(f) dofile(GP_ADDON .. "/" .. f) end
gpload("Export.lua")
gpload("Remind.lua")
local GP = GuildPhone
local realprint = io.write

-- ---- signature ---------------------------------------------------------
local r1 = GP.ReadRoster()
local sig1 = GP.RosterSignature(r1)

ROSTER[3][4] = 60                       -- Peon levels 42 -> 60
local sig_level = GP.RosterSignature(GP.ReadRoster())
ok(sig_level == sig1, "signature ignores level changes (would otherwise fire constantly at launch)")

ROSTER[3][3] = 2                        -- Peon promoted Member -> Officer
local sig_promo = GP.RosterSignature(GP.ReadRoster())
ok(sig_promo ~= sig1, "signature changes on a promotion")
ROSTER[3][3] = 5

local removed = table.remove(ROSTER, 3) -- Peon leaves
local sig_gone = GP.RosterSignature(GP.ReadRoster())
ok(sig_gone ~= sig1, "signature changes when someone leaves")
table.insert(ROSTER, removed)
ok(GP.RosterSignature(GP.ReadRoster()) == sig1, "signature is order independent and returns to the same value")

-- ---- authority ---------------------------------------------------------
ok(GP.HasGuildAuthority() == true, "guild leader has authority")
IsGuildLeader=function() return false end
CanGuildInvite=function() return false end
CanEditOfficerNote=function() return false end
ok(GP.HasGuildAuthority() == false, "plain member has none")

-- WoW: Forever has no CanEditOfficerNote global - only C_GuildInfo's. An
-- officer whose sole authority is the officer note must still be reminded,
-- or the roster quietly goes stale. HasGuildAuthority() read the bare global,
-- so on Forever this person was treated as a plain member.
local _realC = C_GuildInfo
CanEditOfficerNote = nil
C_GuildInfo = { GuildRoster = function() end, CanEditOfficerNote = function() return true end }
ok(GP.CanEditOfficerNote() == true, "the wrapper finds the permission in C_GuildInfo")
ok(GP.HasGuildAuthority() == true, "an officer-note-only officer has authority on Forever")
GuildPhoneDB = nil
local fdue = GP.CheckDue()
ok(fdue == true, "and is reminded to re-export")
C_GuildInfo = { GuildRoster = function() end, CanEditOfficerNote = function() return false end }
ok(GP.HasGuildAuthority() == false, "a plain member on Forever still has none")
C_GuildInfo = _realC
CanEditOfficerNote = function() return false end

-- ---- due logic ---------------------------------------------------------
GuildPhoneDB = nil
local due, why = GP.CheckDue()
ok(due == false, "a plain member is never reminded (they cannot act on it)")

IsGuildLeader=function() return true end
CanGuildInvite=function() return true end
CanEditOfficerNote=function() return true end

GuildPhoneDB = nil
due, why = GP.CheckDue()
ok(due == true, "missing state counts as overdue, not up to date: "..tostring(why))

GP.RecordExport(GP.ReadRoster())
due, why = GP.CheckDue()
ok(due == false, "freshly exported roster is not due")

ROSTER[#ROSTER+1] = {"Newbie","Member",5,1,nil,"X","","",true,"","MAGE",0,0,false,false,0,"G-D"}
due, why = GP.CheckDue()
ok(due == true and why:match("joined"), "a join makes it due: "..tostring(why))
table.remove(ROSTER)

GP.RecordExport(GP.ReadRoster())
local saved = removed
table.remove(ROSTER, 3)
due, why = GP.CheckDue()
ok(due == true and why:match("left"), "a departure makes it due: "..tostring(why))
table.insert(ROSTER, saved)

GP.RecordExport(GP.ReadRoster())
NOW = NOW + 8 * 86400
due, why = GP.CheckDue()
ok(due == true and why:match("day"), "time alone makes it due after the interval: "..tostring(why))

GuildPhoneDB.remindDays = 0
ok(GP.CheckDue() == false, "remindDays=0 disables reminders")
GuildPhoneDB.remindDays = 30
ok(GP.CheckDue() == false, "a longer interval suppresses it")
ok(GP.RemindDays() == 30, "interval is honoured")

realprint("\n")
realprint(("================  %d passed, %d failed  ================\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
