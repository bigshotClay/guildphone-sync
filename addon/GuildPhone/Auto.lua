-- Automatic export for the companion app.
--
-- Addons have NO network access - no HTTP, no sockets, not even to localhost.
-- The only way data leaves the game is a file the client writes, or a string a
-- human copies. So: keep the roster cached during play and serialise it at
-- PLAYER_LOGOUT, which is the last event before SavedVariables are flushed to
-- disk. A companion app watching that file then has a current roster after
-- every session, with the officer doing nothing at all.
--
-- Writing is safe even on the Forever beta - that bug affects READING saved
-- variables back, not writing them.
local GP = GuildPhone

local cached          -- most recent roster seen this session

local f = CreateFrame("Frame")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(_, event)
    if event == "GUILD_ROSTER_UPDATE" then
        -- cache opportunistically; the roster is usually not readable at logout
        local r = GP.ReadRoster()
        if r then cached = r end
    elseif event == "PLAYER_LOGOUT" then
        if not cached then return end
        GuildPhoneDB = GuildPhoneDB or {}
        GuildPhoneDB.auto = {
            export   = GP.Serialize(cached),
            guild    = cached.guild,
            realm    = cached.realm,
            written  = time and time() or 0,
            hasAuth  = GP.HasGuildAuthority() and true or false,
        }
        GP.RecordExport(cached)
    end
end)

-- ask for a roster refresh periodically so the cache does not go stale
if C_Timer then
    C_Timer.NewTicker(300, function()
        if IsInGuild() then GP.RequestRoster() end
    end)
end
