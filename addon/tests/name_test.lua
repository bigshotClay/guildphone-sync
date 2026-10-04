-- Does the exporter keep BOTH halves of a Forever name?
--
-- On Forever UnitName("player") returns name, SURNAME. In retail the
-- second value is the REALM. `local n = UnitName("player")` keeps only the
-- first, so every solo export lost the surname and nobody noticed until a
-- player said "you are not using the full name on my second character".
local FAIL = 0
local function check(what, got, want)
  if got == want then print(("  PASS  %s -> %q"):format(what, got))
  else print(("  FAIL  %s -> %q, wanted %q"):format(what, tostring(got), want)); FAIL = FAIL + 1 end
end

local function stub() local t = setmetatable({}, {__index=function() return function() end end}); return t end
GuildPhone = {}
CreateFrame = function() return stub() end
GetBuildInfo = function() return "1.60.1","60100","Sep 29 2026",16001,16001 end
GetRealmName = function() return "Classic Beta PvP" end
GetNormalizedRealmName = function() return "ClassicBetaPvP" end
UnitGUID = function() return "Player-4619-010E48D9" end
IsInGuild = function() return false end
GetGuildInfo = function() return nil end
UnitFactionGroup = function() return "Horde" end
time = function() return 1790000000 end
C_GuildInfo = { GuildRoster = function() end }

local D = os.getenv("GP_ADDON") or "addon/GuildPhone"
dofile(D .. "/Export.lua")
local GP = GuildPhone

-- Forever: second return is the surname.
UnitName = function() return "Mouse", "Nutz" end
check("Forever two-part name", GP.PlayerName(), "Mouse Nutz")

-- Retail/Classic: second return is the REALM and must NOT be appended.
UnitName = function() return "Mouse", "Classic Beta PvP" end
check("realm is not a surname", GP.PlayerName(), "Mouse")
UnitName = function() return "Mouse", "ClassicBetaPvP" end
check("normalised realm either", GP.PlayerName(), "Mouse")

-- A genuinely single-word name stays single.
UnitName = function() return "Mouse" end
check("single-word name", GP.PlayerName(), "Mouse")
UnitName = function() return "Mouse", "" end
check("empty second value", GP.PlayerName(), "Mouse")

-- And it reaches the export's S line, which is the thing that matters:
-- the helper being right is no use if the export does not call it.
UnitName = function() return "Mouse", "Nutz" end
local text = GP.BuildExport()
if not text then
  print("  FAIL  BuildExport produced nothing"); FAIL = FAIL + 1
else
  check("the S line carries it", text:match("\nS|[^|]*|([^|]*)|"), "Mouse Nutz")
end

print(("================  %d failed  ================"):format(FAIL))
os.exit(FAIL == 0 and 0 or 1)
