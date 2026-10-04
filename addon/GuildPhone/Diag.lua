-- GuildPhone diagnostics: /gpdiag
--
-- Written for the first run against a WoW: Forever client, where several
-- things we depend on are unknown:
--
--   * Forever has RULESETS, not realms. Our schema uses realm as half of
--     what decides whether two guilds with the same name are the same guild,
--     and the addon fills it from GetRealmName(). What that returns here
--     decides whether the identity model is sound or silently broken.
--   * Forever is reported to present modern C_* namespaces rather than the
--     Classic-era globals this addon uses. If GetGuildRosterInfo is gone,
--     the export cannot be produced at all.
--
-- Everything is wrapped so a missing API reports as missing instead of
-- erroring: the whole point is to survive contact and still tell us what it
-- found. Output goes to chat AND to SavedVariables, so it can be pasted
-- even if the chat buffer scrolls.

local GP = GuildPhone or {}
GuildPhone = GP

local lines = {}
local function out(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    if not ok then s = tostring(fmt) end
    lines[#lines+1] = s
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff58a6ff[gpdiag]|r " .. s) end
end

-- Call a global by name and describe what came back, without assuming it exists.
local function probe(name, fn, ...)
    if type(fn) ~= "function" then out("%-34s MISSING", name); return end
    local packed = { pcall(fn, ...) }
    if not packed[1] then out("%-34s ERROR %s", name, tostring(packed[2])); return end
    local vals = {}
    for i = 2, #packed do
        local v = packed[i]
        vals[#vals+1] = (v == nil) and "nil" or (type(v) == "string" and ('"'..v..'"') or tostring(v))
    end
    out("%-34s %s", name, #vals > 0 and table.concat(vals, ", ") or "(no return)")
end

function GP.Diag()
    lines = {}
    out("=== guildphone diagnostics ===")

    local ver, build, date, iface = GetBuildInfo()
    out("%-34s %s build %s (%s) interface %s", "GetBuildInfo()",
        tostring(ver), tostring(build), tostring(date), tostring(iface))

    out("")
    out("--- identity: what names this character's world? ---")
    probe("GetRealmName()",            GetRealmName)
    probe("GetNormalizedRealmName()",  GetNormalizedRealmName)
    probe("GetRealmID()",              GetRealmID)
    probe("UnitName('player')",        UnitName, "player")
    probe("UnitFullName('player')",    UnitFullName, "player")
    probe("UnitGUID('player')",        UnitGUID, "player")
    probe("UnitFactionGroup('player')",UnitFactionGroup, "player")
    probe("UnitLevel('player')",       UnitLevel, "player")
    probe("UnitClass('player')",       UnitClass, "player")

    -- Forever replaced realms with rulesets. We do not know what the client
    -- calls that, so look for anything plausibly named rather than guessing.
    out("")
    out("--- anything ruleset/shard shaped in the global namespace ---")
    local found = 0
    for k, v in pairs(_G) do
        if type(k) == "string" and k:match("[Rr]uleset") or
           (type(k) == "string" and k:match("^C_Ruleset")) then
            out("  _G.%s = %s", k, type(v)); found = found + 1
            if found > 25 then out("  (more elided)"); break end
        end
    end
    if found == 0 then out("  nothing matching 'ruleset'") end
    for _, n in ipairs({ "C_Realm", "C_GameRules", "C_Seasons", "C_ClassicEra" }) do
        out("  %-22s %s", n, type(_G[n]))
    end

    out("")
    out("--- guild: does the Classic-era API still exist? ---")
    out("%-34s %s", "IsInGuild", type(IsInGuild))
    -- ---- account-wide identity -----------------------------------------
    -- Everything about binding an export to a Battle.net account depends on
    -- whether any of these exist on this client. The BattleTag is the one value
    -- we also receive independently, from Battle.net at sign-in, so it is the
    -- only thing that can cross-check a file against an account. If none of
    -- these answer, that whole approach is dead and we should not pretend
    -- otherwise.
    out("--- account-wide identity: can we see the Battle.net account at all? ---")
    probe("BNGetInfo()",               BNGetInfo)
    probe("BNFeaturesEnabled()",       BNFeaturesEnabled)
    probe("BNConnected()",             BNConnected)
    probe("BNGetNumFriends()",         BNGetNumFriends)
    probe("C_BattleNet exists",        function()
        return C_BattleNet and "table" or "MISSING" end)
    probe("C_BattleNet.GetAccountInfoByID(1)", function()
        if not (C_BattleNet and C_BattleNet.GetAccountInfoByID) then return "MISSING" end
        local a = C_BattleNet.GetAccountInfoByID(1)
        return a and (a.battleTag or "no battleTag field") or "nil"
    end)
    probe("GetAutoCompleteRealms()",   GetAutoCompleteRealms)
    probe("C_Login exists",            function()
        return C_Login and "table" or "MISSING" end)
    -- A per-account value that is NOT the BattleTag, in case the tag is hidden
    -- but something else stable is readable.
    probe("GetAccountExpansionLevel()", GetAccountExpansionLevel)
    probe("GetRestrictedAccountData()", GetRestrictedAccountData)
    probe("IsTrialAccount()",          IsTrialAccount)
    probe("IsVeteranTrialAccount()",   IsVeteranTrialAccount)
    probe("UnitGUID('player')",        UnitGUID, "player")

    probe("IsInGuild()",               IsInGuild)
    probe("GetGuildInfo('player')",    GetGuildInfo, "player")
    probe("GetNumGuildMembers()",      GetNumGuildMembers)
    probe("IsGuildLeader()",           IsGuildLeader)
    probe("CanGuildInvite()",          CanGuildInvite)
    probe("CanEditOfficerNote()",      CanEditOfficerNote)
    probe("GuildControlGetNumRanks()", GuildControlGetNumRanks)
    probe("GuildControlGetRankName(1)",GuildControlGetRankName, 1)

    out("")
    out("--- C_GuildInfo (the modern namespace Forever reportedly uses) ---")
    if type(C_GuildInfo) == "table" then
        local names = {}
        for k in pairs(C_GuildInfo) do names[#names+1] = k end
        table.sort(names)
        out("  C_GuildInfo has %d members: %s", #names, table.concat(names, ", "))
    else
        out("  C_GuildInfo is %s", type(C_GuildInfo))
    end

    out("")
    out("--- GetGuildRosterInfo: the field layout we actually depend on ---")
    out("  (we read 1=name 3=rankIndex 4=level 11=classFile 17=guid)")
    if type(GetGuildRosterInfo) ~= "function" then
        out("  GetGuildRosterInfo is MISSING - the export cannot be built")
    else
        local ok, packed = pcall(function() return { GetGuildRosterInfo(1) } end)
        if not ok then
            out("  ERROR: %s", tostring(packed))
        elseif #packed == 0 then
            out("  returned nothing - open the guild panel once, then rerun")
        else
            out("  %d fields returned:", #packed)
            for i = 1, #packed do
                local v = packed[i]
                out("    [%2d] %s", i, (v == nil) and "nil"
                    or (type(v) == "string" and ('"'..v..'"') or tostring(v)))
            end
        end
    end

    out("")
    out("--- can we build an export? ---")
    if type(GP.ReadRoster) == "function" then
        local roster, err = GP.ReadRoster()
        if roster then
            out("  ReadRoster ok: guild=%q realm=%q faction=%q members=%d ranks=%d",
                tostring(roster.guild), tostring(roster.realm),
                tostring(roster.faction), #roster.members,
                (function() local n=0 for _ in pairs(roster.ranks) do n=n+1 end return n end)())
        else
            out("  ReadRoster FAILED: %s", tostring(err))
        end
    else
        out("  GP.ReadRoster missing - Export.lua did not load")
    end

    out("")
    out("=== end ===")
    out("Saved to GuildPhoneDB.diag - /reload then copy it out of")
    out("WTF/Account/<id>/SavedVariables/GuildPhone.lua")

    GuildPhoneDB = GuildPhoneDB or {}
    GuildPhoneDB.diag = table.concat(lines, "\n")
    return GuildPhoneDB.diag
end

SLASH_GPDIAG1 = "/gpdiag"
SlashCmdList["GPDIAG"] = function() GP.Diag() end
