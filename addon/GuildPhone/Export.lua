-- GuildPhone roster export.
--
-- Follows the approach proven by the Olympus addon on WoW: Forever.
--
-- Deliberately STATELESS: there is a live Forever beta bug where SavedVariables
-- are written correctly but not read back, so nothing here depends on reading
-- its own saved state. Everything is derived from the live roster at export.
--
-- Serialisation is kept pure (GuildPhone.Serialize takes a table, returns a
-- string) so it can be unit tested outside the game.
--
-- The re-import reminder is the ONE feature that reads persisted state, and it
-- is written to tolerate the Forever SavedVariables load bug: if the state is
-- missing it assumes an export is overdue. Prompting slightly too often is a
-- far better failure than never prompting at all.

local ADDON = ...
GuildPhone = GuildPhone or {}
local GP = GuildPhone

GP.FORMAT = "GP1"

----------------------------------------------------------------------
-- pure: table -> export string (testable without WoW)
----------------------------------------------------------------------
local function esc(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("|", "\\p"):gsub("\n", " ")
    return s
end

-- djb2: a checksum so a truncated or mangled paste is rejected on import
-- rather than silently importing half a guild. Deliberately arithmetic-only -
-- no bit library - so the same function runs in the game and in unit tests.
function GP.Checksum(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

-- roster = {
--   guild=, realm=, faction=, exported=, self={...},
--   ranks={ [0]=name,... }, members={ {guid,name,rankIndex,level,class}, ... }
-- }
function GP.Serialize(roster)
    local out = {}
    -- Sixth field: the client's interface number. The parser requires five,
    -- so adding one is backward compatible, and it lets the server refuse an
    -- export from a game version this product does not support rather than
    -- importing it and discovering the difference later.
    -- Seventh field: a challenge the SERVER minted, pasted in with /gp claim and
    -- carried back verbatim. The addon never generates it and never signs
    -- anything: a token signed here would be signed with a key sitting in this
    -- very file, which is no security at all. This only proves the client was
    -- open on this account within the last few minutes, which is what makes an
    -- old or shared export file worthless.
    out[#out+1] = table.concat({ GP.FORMAT, esc(roster.guild), esc(roster.realm),
                                 esc(roster.faction), tostring(roster.exported or 0),
                                 tostring(GP.ClientInterface()),
                                 esc(GP.GetChallenge() or "") }, "|")
    -- Who produced this export, and what the GAME says they may do. Rank names
    -- are arbitrary, so authority is taken from the permission APIs rather than
    -- from a rank index. Without this an ordinary member could paste a roster
    -- and be treated as the guild's administrator.
    if roster.self then
        local sf = roster.self
        out[#out+1] = table.concat({ "S", esc(sf.guid), esc(sf.name),
                                     tostring(sf.rankIndex or 99),
                                     sf.isLeader and "1" or "0",
                                     sf.canInvite and "1" or "0",
                                     sf.canOfficerNote and "1" or "0",
                                     -- 8th field: Forever exposes officership
                                     -- directly. Older parsers require only 7
                                     -- fields, so adding one is compatible.
                                     sf.isOfficer and "1" or "0" }, "|")
    end

    -- ranks next: importers need the full rank table, including ranks with
    -- zero members, which the member rows alone would never reveal.
    local ri = {}
    for idx in pairs(roster.ranks or {}) do ri[#ri+1] = idx end
    table.sort(ri)
    for _, idx in ipairs(ri) do
        out[#out+1] = table.concat({ "R", tostring(idx), esc(roster.ranks[idx]) }, "|")
    end
    for _, m in ipairs(roster.members or {}) do
        out[#out+1] = table.concat({ "M", esc(m.guid), esc(m.name), tostring(m.rankIndex),
                                     tostring(m.level or 0), esc(m.class) }, "|")
    end
    local body = table.concat(out, "\n")
    return body .. "\n#" .. GP.Checksum(body)
end

----------------------------------------------------------------------
-- live roster read (WoW only)
----------------------------------------------------------------------
function GP.RequestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()          -- legacy clients
    end
end



-- WoW: Forever only. Declaring one interface version in the .toc makes the
-- addon show as out of date elsewhere, but a player can tick "Load out of
-- date AddOns" and sail past it, so the check is enforced here too.
--
-- Matched on a RANGE, not on 16001 exactly. The beta reports interface
-- 16001 for client 1.60.1; a launch build will be 1.60.2 or 1.61 and report
-- something slightly different. Pinning the exact number would break the
-- addon for everyone on launch day, which is also pilot day. 16000-16999
-- covers the whole 1.6x line and excludes Classic Era (11xxx), TBC (20xxx),
-- Wrath (30xxx), Cata (40xxx) and retail (1xxxxx).
GP.FOREVER_MIN, GP.FOREVER_MAX = 16000, 16999

function GP.ClientInterface()
    if not GetBuildInfo then return 0 end
    local ok, _, _, _, iface = pcall(GetBuildInfo)
    return (ok and tonumber(iface)) or 0
end

function GP.IsForever()
    local i = GP.ClientInterface()
    return i >= GP.FOREVER_MIN and i <= GP.FOREVER_MAX
end

-- Returns nil when the client is supported, or a message when it is not.
function GP.UnsupportedClient()
    if GP.IsForever() then return nil end
    local ver = GetBuildInfo and select(1, GetBuildInfo()) or "?"
    return ("GuildPhone supports World of Warcraft: Forever only. "
        .. "This client reports version %s (interface %d), so exporting is "
        .. "disabled."):format(tostring(ver), GP.ClientInterface())
end


-- WoW: Forever moved several guild permission calls from globals into
-- C_GuildInfo. CanEditOfficerNote in particular is simply absent as a global
-- there, so reading it the old way returned false for everyone - which left
-- CanGuildInvite as the only authority signal, and Forever grants that to
-- ranks as low as Initiate. An Initiate onboarded a 264-member guild as a
-- full admin before this was caught.
--
-- Check both namespaces, and prefer the strongest signal available.
function GP.CanEditOfficerNote()
    if C_GuildInfo and C_GuildInfo.CanEditOfficerNote then
        local ok, v = pcall(C_GuildInfo.CanEditOfficerNote)
        if ok then return v and true or false end
    end
    if CanEditOfficerNote then
        local ok, v = pcall(CanEditOfficerNote)
        if ok then return v and true or false end
    end
    return false
end

-- Forever exposes this directly, which is a far better question than
-- inferring officership from a bundle of individual permissions.
function GP.IsGuildOfficer()
    if C_GuildInfo and C_GuildInfo.IsGuildOfficer then
        local ok, v = pcall(C_GuildInfo.IsGuildOfficer)
        if ok then return v and true or false end
    end
    return false
end


-- The player's own name, both halves of it.
--
-- On WoW: Forever UnitName("player") returns TWO values and the second is
-- the SURNAME - /gpdiag on a character called Mouse Nutz reports
-- `UnitName('player')  "Mouse", "Nutz"`. In retail the second return is the
-- REALM, which is why nobody writing this expected to need it, and why
-- `local name = UnitName("player")` silently kept only "Mouse". Every
-- character claimed from a solo export lost its surname at the source; the
-- guild path never did, because GetGuildRosterInfo hands back the whole
-- name in one string.
--
-- Guarded against the retail meaning anyway: if the second value is the
-- realm, it is not a surname and must not be appended. The addon is
-- Forever-only, but a wrong name is worse than a missing one and the check
-- costs nothing.
local function PlayerName()
    if not UnitName then return "" end
    local first, second = UnitName("player")
    first = first or ""
    if not second or second == "" then return first end
    local realm  = GetRealmName and GetRealmName() or ""
    local nrealm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
    if second == realm or second == nrealm then return first end
    return first .. " " .. second
end
GP.PlayerName = PlayerName

-- An unguilded player still needs a number, so they get an export too: just
-- the S line and themselves as the only member. The platform reads the empty
-- guild name as "put this one in the public pool".
local function SoloRoster()
    local guid = UnitGUID and UnitGUID("player") or ""
    local name = PlayerName()
    return {
        self = {
            guid = guid, name = name, rankIndex = 99,
            isLeader = false, canInvite = false, canOfficerNote = false,
            isOfficer = false,
        },
        guild    = "",
        realm    = GetRealmName and GetRealmName() or "",
        faction  = UnitFactionGroup and UnitFactionGroup("player") or "",
        exported = time and time() or 0,
        ranks    = {},
        members  = {{
            guid = guid, name = name, rankIndex = 99,
            level = UnitLevel and UnitLevel("player") or 0,
            class = UnitClass and select(2, UnitClass("player")) or "",
        }},
    }
end


-- ---- the claim challenge -------------------------------------------------
-- Stored rather than held in memory because exporting requires a /reload, which
-- discards memory. Deliberately not validated here: the addon cannot tell a
-- real challenge from a typo, and pretending otherwise would just produce a
-- confident wrong answer in game instead of a clear one on the website.
function GP.SetChallenge(code)
    GuildPhoneDB = GuildPhoneDB or {}
    code = tostring(code or ""):upper():gsub("%s", "")
    if code == "" then
        GuildPhoneDB.challenge = nil
        return nil
    end
    GuildPhoneDB.challenge = code
    return code
end

function GP.GetChallenge()
    return GuildPhoneDB and GuildPhoneDB.challenge or nil
end

-- Re-serialise an export that is already stored, so it picks up a challenge
-- pasted after the fact.
--
-- The export is built when the player presses the button and then sits in
-- SavedVariables until a reload writes it. A code pasted afterwards used to
-- change nothing: the file on disk still had an empty code field, and the
-- upload refused to claim while the player was certain they had done every
-- step. They had. The steps were just order-dependent for no reason a player
-- could see.
function GP.RestampExport()
    if not (GuildPhoneDB and GuildPhoneDB.export and GuildPhoneDB.export.export) then
        return false
    end
    local roster = GP.ReadRoster()
    if not roster then return false end
    GuildPhoneDB.export.export = GP.Serialize(roster)
    GuildPhoneDB.export.written = time and time() or 0
    return true
end

function GP.ReadRoster()
    local unsupported = GP.UnsupportedClient()
    if unsupported then return nil, unsupported end
    if not IsInGuild() then return SoloRoster() end

    local guildName = GetGuildInfo("player")
    if not guildName then return nil, "Guild info not loaded yet - try again in a moment." end

    local _, _, myRank = GetGuildInfo("player")
    local roster = {
        self = {
            guid           = UnitGUID and UnitGUID("player") or "",
            name           = PlayerName(),
            rankIndex      = myRank or 99,
            isLeader       = IsGuildLeader and IsGuildLeader() or false,
            canInvite      = CanGuildInvite and CanGuildInvite() or false,
            canOfficerNote = GP.CanEditOfficerNote(),
            isOfficer      = GP.IsGuildOfficer(),
        },
        guild    = guildName,
        realm    = GetRealmName and GetRealmName() or "",
        faction  = UnitFactionGroup and UnitFactionGroup("player") or "",
        exported = time and time() or 0,
        ranks    = {},
        members  = {},
    }

    -- Rank table from guild control: this is the ONLY way to see ranks that
    -- currently have no members. GuildControlGetRankName is 1-based while the
    -- roster's rankIndex is 0-based, hence the offset.
    local numRanks = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
    for i = 1, numRanks do
        local nm = GuildControlGetRankName and GuildControlGetRankName(i)
        if nm then roster.ranks[i - 1] = nm end
    end

    local total = GetNumGuildMembers()
    for i = 1, (total or 0) do
        local name, rankName, rankIndex, level, _, _, _, _, _, _, classFile,
              _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if name then
            -- guid is stable across rename, realm transfer and faction change;
            -- name is not, so guid is what the platform keys on.
            roster.members[#roster.members+1] = {
                guid      = guid or ("name:" .. name),
                name      = name,
                rankIndex = rankIndex or 0,
                level     = level,
                class     = classFile,
            }
            if rankName and roster.ranks[rankIndex or 0] == nil then
                roster.ranks[rankIndex or 0] = rankName
            end
        end
    end

    if #roster.members == 0 then
        return nil, "Roster is empty - open the guild panel once, then retry."
    end
    return roster
end

-- A signature of WHO IS IN THE GUILD AND AT WHAT RANK - deliberately not the
-- whole roster. Levels change constantly (especially at launch) and would make
-- a full-roster hash useless as a change signal. Joins, departures, promotions
-- and demotions are what the platform actually cares about.
function GP.RosterSignature(roster)
    local parts = {}
    for _, m in ipairs(roster.members or {}) do
        parts[#parts+1] = (m.guid or "") .. ":" .. tostring(m.rankIndex or 0)
    end
    table.sort(parts)
    return GP.Checksum(table.concat(parts, ","))
end

-- Does the game say this player may act for the guild? Rank names are arbitrary;
-- these permissions are not. Only officers are reminded, because only their
-- import updates the whole roster.
function GP.HasGuildAuthority()
    return (IsGuildLeader and IsGuildLeader())
        or (CanGuildInvite and CanGuildInvite())
        or GP.CanEditOfficerNote()
        or false
end

function GP.BuildExport()
    local roster, err = GP.ReadRoster()
    if not roster then return nil, err end
    return GP.Serialize(roster), nil, roster
end
