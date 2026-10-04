-- A SavedVariables file produced the way the GAME produces one: by running
-- the addon's own /gp claim command, then writing GuildPhoneDB out with WoW's
-- escaping.
--
-- This exists because UI.lua was loaded by no test at all. Every harness set
-- GuildPhoneDB.challenge directly and called Serialize, so the serialiser was
-- well covered and the COMMAND that fills it had never been executed outside
-- the game. The bug that mattered lived there: /gp wrote the export under a
-- key the website does not read, so exporting by command produced a file the
-- upload silently ignored - falling back to whatever the options panel had
-- written earlier, possibly without the claim code just pasted in.
--
--   GP_CODE=ABCD-2345 lua5.1 addon/tests/gen_claim_sv.lua > GuildPhone.lua
--
GetBuildInfo=function() return "1.60.1","60100","Sep 29 2026",16001,16001 end
GuildPhoneDB={}
IsInGuild=function() return true end
GetRealmName=function() return "Nightslayer" end
UnitFactionGroup=function() return "Horde" end
UnitGUID=function() return "Player-9999-E2ETEST1" end
UnitName=function() return "Endtoend Tester" end
UnitLevel=function() return 60 end
UnitClass=function() return "Warrior","WARRIOR" end
time=function() return os.time() end
GetGuildInfo=function() return "E2E Testguild","Guild Master",0 end
GetNumGuildMembers=function() return 2 end
GetGuildRosterInfo=function(i)
  if i==1 then return "Endtoend Tester","Guild Master",0,60,nil,nil,nil,nil,nil,nil,"WARRIOR",nil,nil,nil,nil,nil,"Player-9999-E2ETEST1" end
  if i==2 then return "Ragnarök Bjørnsdóttir","Member",4,55,nil,nil,nil,nil,nil,nil,"PRIEST",nil,nil,nil,nil,nil,"Player-9999-E2ETEST2" end
end
GuildControlGetRankName=function(i) return ({"Guild Master","Officer","Veteran","Raider","Member"})[i] end
GuildRoster=function() end
C_GuildInfo={GuildRoster=function() end}
CanEditGuildInfo=function() return true end
IsGuildLeader=function() return true end
C_Timer={After=function(_,f) f() end, NewTicker=function() return {Cancel=function() end} end}
SlashCmdList={}
print=function() end
local function stub() local f={} setmetatable(f,{__index=function() return function() return f end end}) return f end
CreateFrame=function() return stub() end
UIParent=stub() ChatFontNormal=stub() Settings=nil InterfaceOptions_AddCategory=function() end
local D=os.getenv("GP_ADDON") or "addon/GuildPhone"
dofile(D.."/Export.lua") dofile(D.."/Diag.lua") dofile(D.."/Remind.lua")
dofile(D.."/Auto.lua") dofile(D.."/UI.lua") dofile(D.."/Options.lua")

SlashCmdList["GUILDPHONE"]("claim "..(os.getenv("GP_CODE") or "AAAA-2222"))

-- WoW writes SavedVariables with \ddd escapes for bytes above 127
local function q(s)
  s = tostring(s):gsub("[\\\"]", "\\%0"):gsub("\n","\\n")
  return (s:gsub("[\128-\255]", function(c) return ("\\%d"):format(c:byte()) end))
end
local e = GuildPhoneDB.export
io.write('GuildPhoneDB = {\n')
io.write('\t["challenge"] = "'..q(GuildPhoneDB.challenge)..'",\n')
io.write('\t["export"] = {\n')
io.write('\t\t["guild"] = "'..q(e.guild)..'",\n')
io.write('\t\t["realm"] = "'..q(e.realm)..'",\n')
io.write('\t\t["self"] = "'..q(e.self)..'",\n')
io.write('\t\t["written"] = '..tostring(e.written)..',\n')
io.write('\t\t["export"] = "'..q(e.export)..'",\n')
io.write('\t},\n}\n')
