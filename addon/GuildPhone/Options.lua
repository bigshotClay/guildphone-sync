-- The options panel does not export any more.
--
-- It used to, with a button, while the claim code was pasted in by a slash
-- command somewhere else. Two halves of one job in two places, and the order
-- mattered in a way nothing told you: press the button, then paste the code,
-- and the file on disk was written without it. The upload then imported the
-- roster and refused the claim, which reads like a bug in the website to
-- somebody who did every step they were given.
--
-- So the commands do the work and this panel says what to type. A page that
-- only tells you things cannot be half-done.
local GP = GuildPhone

local panel = CreateFrame("Frame")
panel.name = "GuildPhone"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("GuildPhone")

local blurb = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
blurb:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
blurb:SetJustifyH("LEFT")
blurb:SetJustifyV("TOP")

local steps = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
steps:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -16)
steps:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
steps:SetJustifyH("LEFT")
steps:SetJustifyV("TOP")

local state = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
state:SetPoint("TOPLEFT", steps, "BOTTOMLEFT", 0, -18)
state:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
state:SetJustifyH("LEFT")
state:SetJustifyV("TOP")

local function refresh()
    local inGuild = IsInGuild and IsInGuild()
    blurb:SetText("A telephone system for your guild. Every character gets its own "
        .. "number, and keeps it. Nothing here talks to the internet: the addon "
        .. "writes a file and you upload it.")

    local lines = {
        "|cffffd100To claim this character|r",
        "   1.  Get a code at |cff58a6ffguildphone.com|r \226\128\148 |cffffd100Claim a character|r",
        "   2.  Type |cffffff00/gp claim YOUR-CODE|r here",
        "   3.  Type |cffffff00/reload|r, then upload |cff58a6ffGuildPhone.lua|r",
        "",
        "|cffffd100To claim your other characters|r",
        "   Log in as each one and run |cffffff00/gp claim|r again. The same",
        "   code works for all of them until you upload, and that one",
        "   upload claims every character in the file.",
        "",
    }
    if inGuild then
        lines[#lines+1] = "|cffffd100To bring your guild in, or refresh its roster|r"
        lines[#lines+1] = "   Type |cffffff00/gp enroll|r, then |cffffff00/reload|r and upload."
        lines[#lines+1] = "   |cff999999Claiming already exports the roster too, so you only"
        lines[#lines+1] = "   need this to refresh it later.|r"
    else
        lines[#lines+1] = "|cff999999You are not in a guild, so claiming gives you a number"
        lines[#lines+1] = "of your own. You keep it if you join one later.|r"
    end
    steps:SetText(table.concat(lines, "\n"))

    local code = GP.GetChallenge and GP.GetChallenge() or nil
    local saved = GuildPhoneDB and GuildPhoneDB.export
    local bits = {}
    if code then
        bits[#bits+1] = "|cff55ff55Claim code stored:|r " .. code
                     .. " |cff999999(goes into the next export)|r"
    else
        bits[#bits+1] = "|cff999999No claim code stored. Without one an export still "
                     .. "gives\nthe guild numbers, but claims nobody.|r"
    end
    -- Count what the file actually holds. A player who has claimed four
    -- alts wants to see four here before they reload - the alternative is
    -- uploading and finding out.
    local names, n = {}, 0
    for _, e in pairs(GuildPhoneDB and GuildPhoneDB.chars or {}) do
        n = n + 1
        if e.self then names[#names+1] = e.self end
    end
    if n > 1 then
        table.sort(names)
        bits[#bits+1] = ("|cff999999Ready to upload: %d characters \226\128\148 %s."
            .. "\nReload, then upload the file once.|r"):format(n, table.concat(names, ", "))
    elseif saved and saved.export then
        bits[#bits+1] = ("|cff999999Export ready: %s%s. Reload and upload it.|r"):format(
            (saved.guild ~= "" and saved.guild or "your character"),
            saved.self and (" \226\128\148 " .. saved.self) or "")
    end
    state:SetText(table.concat(bits, "\n\n"))
end

panel:SetScript("OnShow", refresh)

-- Registration moved between expansions. Forever is a 1.60 client presenting
-- modern namespaces, so try the Settings API first and fall back rather than
-- assuming either.
local function register()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        category.ID = panel.name
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end
register()
