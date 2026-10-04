-- Scheduled re-import reminder.
--
-- The platform only learns about /gquit, kicks and promotions when an officer
-- re-imports. Without a nudge that never happens and the roster silently rots.
--
-- Reads persisted state, unlike the rest of the addon: see the note in
-- Export.lua. Missing state is treated as "overdue", never as "up to date".
local GP = GuildPhone

local DEFAULT_DAYS = 7

local function store()
    GuildPhoneDB = GuildPhoneDB or {}
    GuildPhoneDB.guilds = GuildPhoneDB.guilds or {}
    return GuildPhoneDB
end

local function guildState(name)
    local db = store()
    db.guilds[name] = db.guilds[name] or {}
    return db.guilds[name]
end

function GP.RecordExport(roster)
    local st = guildState(roster.guild)
    st.lastAt  = time and time() or 0
    st.lastSig = GP.RosterSignature(roster)
    st.members = #roster.members
end

function GP.RemindDays()
    local db = store()
    if db.remindDays == nil then return DEFAULT_DAYS end
    return db.remindDays
end

-- returns: shouldRemind, reason
function GP.CheckDue()
    if not IsInGuild() then return false end
    if not GP.HasGuildAuthority() then return false end   -- only officers can act on it
    local days = GP.RemindDays()
    if days == 0 then return false end                     -- snoozed off

    local roster = GP.ReadRoster()
    if not roster then return false end

    local st = guildState(roster.guild)
    -- Missing state (never exported, or the load bug ate it) => overdue.
    if not st.lastAt or not st.lastSig then
        return true, "this guild has not been exported yet"
    end

    local sig = GP.RosterSignature(roster)
    if sig ~= st.lastSig then
        local delta = #roster.members - (st.members or #roster.members)
        if delta > 0 then
            return true, ("%d member(s) joined since your last export"):format(delta)
        elseif delta < 0 then
            return true, ("%d member(s) left since your last export"):format(-delta)
        end
        return true, "ranks have changed since your last export"
    end

    local age = (time and time() or 0) - st.lastAt
    if age > days * 86400 then
        return true, ("your last export was %d day(s) ago"):format(math.floor(age/86400))
    end
    return false
end

-- The first thing a new installer sees.
--
-- Until now: nothing. GP.CheckDue() returns false for anybody who is not
-- an OFFICER with a loaded roster, and it is the only thing that ever
-- spoke. So an ordinary member installed the addon, logged in, saw no
-- sign it existed, and left. Twenty-one people downloaded it and not one
-- of them signed in - which looked like nobody wanting it, and was
-- actually a product that never said hello.
--
-- Shown once per character and then never again. A greeting that repeats
-- is an advert, and an addon that advertises at you gets uninstalled.
function GP.Greet()
    local db = store()
    db.greeted = db.greeted or {}
    local who = (UnitName and UnitName("player")) or "?"
    if db.greeted[who] then return end
    db.greeted[who] = true

    -- Already claimed on this account? Then they know what this is, and
    -- the greeting would be noise.
    if GP.GetChallenge and GP.GetChallenge() then return end
    if db.chars then
        for _ in pairs(db.chars) do return end
    end

    print("|cff58a6ffGuild Phone|r - your character can have a telephone number.")
    print("  1. get a code at |cff58a6ffguildphone.com|r")
    print("  2. type |cffffff00/gp claim YOUR-CODE|r here")
    print("  3. type |cffffff00/reload|r, then upload |cff58a6ffGuildPhone.lua|r")
    -- No "type X to stop this": it is shown once per character and never
    -- again, so there is nothing to stop. The first draft of this line
    -- offered /gp quiet, which does not exist - the same bug it was
    -- written to fix, introduced in the fix.
    print("  |cff999999That is all of it. |cffffff00/gp|r|cff999999 for help.|r")
end

function GP.Remind()
    local due, why = GP.CheckDue()
    if not due then return end
    print("|cff58a6ffGuildPhone|r: " .. why ..
          " - run |cffffff00/gp enroll|r, then |cffffff00/reload|r and upload the file")
    print("|cff58a6ffGuildPhone|r: (|cffffff00/gp remind off|r to stop, " ..
          "|cffffff00/gp remind 14|r to change the interval)")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
    -- the roster is not available immediately after login
    -- Eight seconds: after the login spam has scrolled past, long before
    -- somebody has stopped reading chat.
    if C_Timer then C_Timer.After(8,  function() GP.Greet() end) end
    if C_Timer then C_Timer.After(20, function() GP.RequestRoster() end) end
    if C_Timer then C_Timer.After(25, function() GP.Remind() end) end
end)
