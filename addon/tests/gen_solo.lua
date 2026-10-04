-- an unguilded player: the addon must still produce an export
-- The addon refuses to run outside WoW: Forever, so the stub must report a
-- Forever client or every test fails at the gate rather than at the thing
-- it is testing. 1.60.1 / interface 16001 is the beta client.
GetBuildInfo = function() return "1.60.1", "60100", "Sep 29 2026", 16001, 16001 end
-- Carry a server-issued challenge when the harness supplies one, the
-- same way a player does with /gp claim. Without it the export has no
-- code and the upload cannot claim anything.
GuildPhoneDB = { challenge = os.getenv("GP_CHALLENGE") }

IsInGuild=function() return false end
GetRealmName=function() return "Nightslayer" end
UnitFactionGroup=function() return "Horde" end
UnitGUID=function() return "SOLO-XYZ" end
UnitName=function() return "Lonewolf" end
UnitLevel=function() return 27 end
UnitClass=function() return "Shaman","SHAMAN" end
time=function() return 1759100000 end
local GP_ADDON = os.getenv("GP_ADDON") or "addon/GuildPhone"
local function gpload(f) dofile(GP_ADDON .. "/" .. f) end
gpload("Export.lua")
io.write((GuildPhone.BuildExport()))
