-- Two commands, and each one finishes the job.
--
--   /gp claim CODE   claim this character, and export
--   /gp enroll       bring this guild in, or refresh its roster
--
-- Both end with a file on disk and one instruction: reload, then upload. The
-- old shape asked for a code in one place and an Export button in another,
-- and the order mattered in a way nothing told you - paste the code after
-- pressing the button and the file was written without it. The command that
-- needs the code is now the command that writes the file, so there is no
-- order to get wrong.
--
-- There is no window. The export is a FILE, written on /reload, and uploading
-- it is what every instruction says. Pasting text was a second route that
-- half worked, which is worse than no second route: it splits the support
-- questions and doubles what can break.
local GP = GuildPhone

-- Kept as a no-op: something may still call it, and an error in somebody's
-- chat frame is a worse outcome than nothing happening.
function GP.ShowExport() end

local function say(msg) print("|cff58a6ffGuildPhone|r: " .. msg) end
local function warn(msg) print("|cffff5555GuildPhone:|r " .. msg) end

-- /gp remind off | on | <days>
local function handleRemind(arg)
    GuildPhoneDB = GuildPhoneDB or {}
    if arg == "off" then
        GuildPhoneDB.remindDays = 0
        say("reminders off.")
    elseif arg == "on" then
        GuildPhoneDB.remindDays = nil
        say("reminders back on (every 7 days).")
    else
        local n = tonumber(arg)
        if n and n > 0 then
            GuildPhoneDB.remindDays = math.floor(n)
            say(("reminding every %d day(s)."):format(math.floor(n)))
        else
            say("usage: /gp remind off | on | <days>")
        end
    end
end

-- The guild roster arrives asynchronously, so every export waits for it. On
-- first use the client has not loaded it yet and exporting immediately
-- produces an empty roster - which looks like a broken addon rather than a
-- timing problem.
local function withRoster(done)
    GP.RequestRoster()
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("GUILD_ROSTER_UPDATE")
    local fired = false
    local function go()
        if fired then return end
        fired = true
        waiter:UnregisterAllEvents()
        done()
    end
    waiter:SetScript("OnEvent", go)
    C_Timer.After(2, go)        -- the event never fires for an unguilded player
end

-- Build the export and store it where the website's extractor looks. One
-- place, used by both commands: the file on disk is the product, and there is
-- no second key for anybody to write to by mistake.
-- One slot PER CHARACTER, keyed by name and realm.
--
-- A single slot meant each character overwrote the last, so claiming five
-- alts was five codes, five logins and five uploads - spending a
-- five-minute proof five times to establish one fact. The file accumulates
-- now: log in as each character once, run the command, and a single upload
-- claims all of them and imports every guild they are in.
--
-- The old single key is still written. It costs a few bytes, it is the key
-- every older server and the companion app look for, and the website
-- de-duplicates identical exports anyway.
local function writeExport()
    local text, err, roster = GP.BuildExport()
    if not text then
        warn(err or "could not build the export.")
        return nil
    end
    local entry = {
        export  = text,
        guild   = roster.guild,
        realm   = roster.realm,
        self    = roster.self and roster.self.name or nil,
        written = time and time() or 0,
    }
    GuildPhoneDB = GuildPhoneDB or {}
    GuildPhoneDB.chars = GuildPhoneDB.chars or {}
    local who = roster.self and roster.self.name or "unknown"
    GuildPhoneDB.chars[who .. "-" .. (roster.realm or "")] = entry
    GuildPhoneDB.export = entry
    if GP.RecordExport then GP.RecordExport(roster) end
    return text, roster
end

-- How many characters this file is currently carrying, so the chat message
-- can say what a single upload will do rather than leaving it to be found out.
local function exportCount()
    local n = 0
    for _ in pairs(GuildPhoneDB and GuildPhoneDB.chars or {}) do n = n + 1 end
    return n
end
GP.ExportCount = exportCount

local function reloadAndUpload()
    print("        Type |cffffff00/reload|r, then upload |cff58a6ffGuildPhone.lua|r "
        .. "at |cff58a6ffguildphone.com|r.")
    local n = exportCount()
    if n > 1 then
        print(("        |cff999999That one upload covers all %d of your characters "
            .. "and their guilds.|r"):format(n))
    end
end

local function handleClaim(raw)
    local code = GP.SetChallenge(raw)
    if not code then
        say("claim code cleared. Get one at guildphone.com and run "
            .. "|cffffff00/gp claim YOUR-CODE|r.")
        return
    end
    withRoster(function()
        local text, roster = writeExport()
        if not text then return end
        local who = roster.self and roster.self.name or "this character"
        say(("claiming |cffffffff%s|r with code |cff58a6ff%s|r."):format(who, code))
        if roster.guild ~= "" then
            print(("        %s - %d members exported too, so the whole guild gets numbers.")
                  :format(roster.guild, #roster.members))
        end
        reloadAndUpload()
        print("        |cff999999Claiming an alt? Log in as it and run this again - "
            .. "the same code still works until you upload.|r")
    end)
end

local function handleEnroll()
    withRoster(function()
        local text, roster = writeExport()
        if not text then return end
        if roster.guild == "" then
            say("you are not in a guild, so there is nothing to enroll.")
            print("        To get a number for this character, run "
                .. "|cffffff00/gp claim YOUR-CODE|r with a code from guildphone.com.")
            return
        end
        local nranks = 0
        for _ in pairs(roster.ranks) do nranks = nranks + 1 end
        say(("enrolling |cffffffff%s|r - %d members, %d ranks."):format(
            roster.guild, #roster.members, nranks))
        -- Whether this guild is new or already known is the server's question,
        -- not ours: it has the roster and we do not. Saying "new or updated"
        -- is honest and saves guessing wrongly in either direction.
        print("        If your guild is new to Guild Phone you are its first member. "
            .. "If not, this updates the roster.")
        reloadAndUpload()
        if not GP.GetChallenge() then
            print("        |cff999999This does not claim your own character - "
                .. "run /gp claim YOUR-CODE for that.|r")
        end
    end)
end

SLASH_GUILDPHONE1 = "/guildphone"
SLASH_GUILDPHONE2 = "/gp"
SlashCmdList["GUILDPHONE"] = function(msg)
    -- The raw message is kept: a claim code is case-normalised by
    -- SetChallenge, but lowercasing the whole line first would mangle
    -- anything else an argument ever needs to carry.
    local raw = msg or ""
    local cmd = raw:match("^(%S*)"):lower()

    if cmd == "remind" then
        return handleRemind(raw:match("^%S*%s+(%S+)"))
    end
    if cmd == "claim" then
        return handleClaim(raw:match("^%S*%s+(.+)$"))
    end
    if cmd == "enroll" or cmd == "enrol" then
        return handleEnroll()
    end
    if cmd == "status" then
        local due, why = GP.CheckDue()
        return say(due and ("export due - " .. why) or "roster is up to date.")
    end

    say("what would you like to do?")
    print("  |cffffff00/gp claim CODE|r   claim this character (run it on each one)")
    print("  |cffffff00/gp enroll|r       bring this guild in, or refresh its roster")
    print("  |cffffff00/gp status|r       is the roster due a re-export?")
    print("  |cffffff00/gp remind|r       off | on | <days>")
    local code = GP.GetChallenge()
    if code then
        print(("  |cff999999a claim code is stored (%s) and will go into the next export|r")
              :format(code))
    end
end
