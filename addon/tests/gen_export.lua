-- deterministic officer export for the import round-trip test
local ROSTER = {
  {"Thrallbane","Guild Master",0,60,nil,"Org","","",true,"","WARRIOR",0,0,false,false,0,"GP-H-AAA1"},
  {"Grimfang","Officer",2,60,nil,"Dur","","",false,"","ROGUE",0,0,false,false,0,"GP-H-BBB2"},
  {"Peon","Member",5,42,nil,"Bar","","",true,"","HUNTER",0,0,false,false,0,"GP-H-CCC3"},
}
-- The addon refuses to run outside WoW: Forever, so the stub must report a
-- Forever client or every test fails at the gate rather than at the thing
-- it is testing. 1.60.1 / interface 16001 is the beta client.
GetBuildInfo = function() return "1.60.1", "60100", "Sep 29 2026", 16001, 16001 end
-- Carry a server-issued challenge when the harness supplies one, the
-- same way a player does with /gp claim. Without it the export has no
-- code and the upload cannot claim anything.
GuildPhoneDB = { challenge = os.getenv("GP_CHALLENGE") }

-- A player with alts produces one export per character, each from a
-- different guild and at a different moment. These overrides let the
-- harness build that file without a second stub that could drift from
-- this one: same addon code, same serialiser, different character.
local GUILD = os.getenv("GP_GUILD") or "Harness Import Guild"
local SELF  = os.getenv("GP_SELF")
local SGUID = os.getenv("GP_SELFGUID")
local WHEN  = tonumber(os.getenv("GP_EXPORTED") or "") or 1759100000
if SELF  then ROSTER[1][1]  = SELF  end
if SGUID then ROSTER[1][17] = SGUID end

IsInGuild=function() return true end
GetGuildInfo=function() return GUILD,"Guild Master",0 end
GetRealmName=function() return "Nightslayer" end
UnitFactionGroup=function() return "Alliance" end
time=function() return WHEN end
GetNumGuildMembers=function() return #ROSTER end
GetGuildRosterInfo=function(i) local r=ROSTER[i]; if not r then return nil end; return unpack(r) end
local RANKS={"Guild Master","Veteran","Officer","Raider","Trial","Member"}
GuildControlGetNumRanks=function() return #RANKS end
GuildControlGetRankName=function(i) return RANKS[i] end
C_GuildInfo={GuildRoster=function() end}
-- exported by the guild leader, so this is a clean onboarding
UnitGUID=function() return SGUID or "GP-H-AAA1" end
UnitName=function() return SELF or "Thrallbane" end
IsGuildLeader=function() return true end
CanGuildInvite=function() return true end
CanEditOfficerNote=function() return true end
local GP_ADDON = os.getenv("GP_ADDON") or "addon/GuildPhone"
local function gpload(f) dofile(GP_ADDON .. "/" .. f) end
gpload("Export.lua")
io.write((GuildPhone.BuildExport()))
