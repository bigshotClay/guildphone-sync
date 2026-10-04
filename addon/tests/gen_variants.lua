-- export variants: AUTH=0 a plain member, AUTH=1 an officer; DROP=1 removes Peon
local AUTH = os.getenv("AUTH") == "1"
local DROP = os.getenv("DROP") == "1"
local ROSTER = {
  {"Thrallbane","Guild Master",0,60,nil,"Org","","",true,"","WARRIOR",0,0,false,false,0,"DG-AAA1"},
  {"Grimfang","Officer",2,60,nil,"Dur","","",false,"","ROGUE",0,0,false,false,0,"DG-BBB2"},
  {"Peon","Member",5,42,nil,"Bar","","",true,"","HUNTER",0,0,false,false,0,"DG-CCC3"},
}
if DROP then table.remove(ROSTER, 3) end
-- The addon refuses to run outside WoW: Forever, so the stub must report a
-- Forever client or every test fails at the gate rather than at the thing
-- it is testing. 1.60.1 / interface 16001 is the beta client.
GetBuildInfo = function() return "1.60.1", "60100", "Sep 29 2026", 16001, 16001 end
-- Carry a server-issued challenge when the harness supplies one, the
-- same way a player does with /gp claim. Without it the export has no
-- code and the upload cannot claim anything.
GuildPhoneDB = { challenge = os.getenv("GP_CHALLENGE") }

IsInGuild=function() return true end
GetGuildInfo=function() return "Dirty Guild Test","Member",5 end
GetRealmName=function() return "Nightslayer" end
UnitFactionGroup=function() return "Alliance" end
time=function() return 1759100000 end
GetNumGuildMembers=function() return #ROSTER end
GetGuildRosterInfo=function(i) local r=ROSTER[i]; if not r then return nil end; return unpack(r) end
local RANKS={"Guild Master","Veteran","Officer","Raider","Trial","Member"}
GuildControlGetNumRanks=function() return #RANKS end
GuildControlGetRankName=function(i) return RANKS[i] end
C_GuildInfo={GuildRoster=function() end}
-- the exporter is Peon (a plain member) unless AUTH=1, in which case Thrallbane
UnitGUID=function() return AUTH and "DG-AAA1" or "DG-CCC3" end
UnitName=function() return AUTH and "Thrallbane" or "Peon" end
IsGuildLeader=function() return AUTH end
CanGuildInvite=function() return AUTH end
CanEditOfficerNote=function() return AUTH end
local GP_ADDON = os.getenv("GP_ADDON") or "addon/GuildPhone"
local function gpload(f) dofile(GP_ADDON .. "/" .. f) end
gpload("Export.lua")
io.write((GuildPhone.BuildExport()))
