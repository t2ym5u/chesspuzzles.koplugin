-- ---------------------------------------------------------------------------
-- puzzles.lua — the puzzle bank and puzzle picking (pure Lua, no UI).
--
-- One data file per difficulty band (puzzles_<band>.lua, built offline by
-- tools/select_puzzles.py from the Lichess puzzle database, CC0). Each file
-- returns one text, one puzzle per line, sorted by rating:
--
--     <id> <board> <side> <castling> <ep> <uci,uci,...> <rating> <themes>
--
-- A band is read the first time it is needed and kept as raw lines plus a
-- rating array (~170 KB of text per band) until the game screen closes; a line is only split into a
-- puzzle table when that puzzle is played.
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local Puzzles = {}

Puzzles.BANDS = { "beginner", "easy", "medium", "hard", "expert" }
-- Rating range of each band: [lo, hi).
Puzzles.RANGES = {
    beginner = { 0, 1000 },
    easy     = { 1000, 1400 },
    medium   = { 1400, 1800 },
    hard     = { 1800, 2200 },
    expert   = { 2200, 4000 },
}

-- Theme filters: id -> theme code(s) in the data (see tools/select_puzzles.py).
Puzzles.THEMES = { "all", "mate1", "mate2", "mate3", "fork", "pin", "skewer",
                   "discovered", "sacrifice", "endgame", "promotion" }
Puzzles.THEME_CODE = {
    mate1 = "1", mate2 = "2", mate3 = "3", fork = "f", pin = "p", skewer = "s",
    discovered = "d", sacrifice = "x", endgame = "e", promotion = "q",
}

local bank = {}

-- Test hook: read the bands from another directory.
Puzzles.data_dir = _dir

function Puzzles.isBand(id)
    return Puzzles.RANGES[id] ~= nil
end

local function loadBand(band)
    local b = bank[band]
    if b then return b end
    b = { lines = {}, ratings = {}, themes = {} }
    bank[band] = b
    if not Puzzles.isBand(band) then return b end
    local chunk = loadfile(Puzzles.data_dir .. "puzzles_" .. band .. ".lua")
    local ok, text = pcall(chunk or error)
    if not ok or type(text) ~= "string" then return b end
    for line in text:gmatch("[^\n]+") do
        local rating, themes = line:match(" (%d+) (%S+)$")
        if rating then
            local n = #b.lines + 1
            b.lines[n] = line
            b.ratings[n] = tonumber(rating)
            b.themes[n] = themes
        end
    end
    return b
end

-- Forget the loaded bands: called when the game screen closes (all five
-- bands read again in ~15 ms on desktop), and by the tests.
function Puzzles.unload()
    bank = {}
end
Puzzles.release = Puzzles.unload

-- The bands loaded now (for the specs).
function Puzzles.loadedBands()
    local out = {}
    for band in pairs(bank) do out[#out + 1] = band end
    table.sort(out)
    return out
end

function Puzzles.count(band)
    return #loadBand(band).lines
end

function Puzzles.rating(band, index)
    return loadBand(band).ratings[index]
end

function Puzzles.hasTheme(band, index, theme)
    local code = Puzzles.THEME_CODE[theme]
    if not code then return true end
    local t = loadBand(band).themes[index]
    return t ~= nil and t:find(code, 1, true) ~= nil
end

-- Parse one line into a puzzle table.
function Puzzles.parse(line)
    local id, board, side, castle, ep, moves, rating, themes =
        line:match("^(%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%d+) (%S+)$")
    if not id then return nil end
    local list = {}
    for m in moves:gmatch("[^,]+") do list[#list + 1] = m end
    return {
        id     = id,
        fen    = table.concat({ board, side, castle, ep, "0", "1" }, " "),
        moves  = list,
        rating = tonumber(rating),
        themes = themes ~= "-" and themes or "",
    }
end

-- Puzzle `index` of `band`, or nil.
function Puzzles.get(band, index)
    local line = loadBand(band).lines[index]
    local p = line and Puzzles.parse(line)
    if p then
        p.band, p.index = band, index
    end
    return p
end

-- The band whose range holds `rating`.
function Puzzles.bandFor(rating)
    for _, id in ipairs(Puzzles.BANDS) do
        local r = Puzzles.RANGES[id]
        if rating < r[2] then return id end
    end
    return Puzzles.BANDS[#Puzzles.BANDS]
end

-- ---------------------------------------------------------------------------
-- Picking
--
-- opts = {
--   band    = band id, or "adaptive"
--   target  = rating to aim at (adaptive)
--   theme   = theme filter id ("all" or nil = any)
--   is_seen = function(band, index) -> bool
--   random  = function(n) -> 1..n (defaults to math.random)
-- }
-- Returns band, index, fresh (false when every matching puzzle had been seen
-- and an already-seen one is replayed), or nil when nothing matches at all.
-- ---------------------------------------------------------------------------

local function bandOrder(first)
    -- `first`, then the other bands by distance from it.
    local pos
    for i, id in ipairs(Puzzles.BANDS) do
        if id == first then pos = i end
    end
    pos = pos or 1
    local order = { Puzzles.BANDS[pos] }
    for d = 1, #Puzzles.BANDS do
        if Puzzles.BANDS[pos - d] then order[#order + 1] = Puzzles.BANDS[pos - d] end
        if Puzzles.BANDS[pos + d] then order[#order + 1] = Puzzles.BANDS[pos + d] end
    end
    return order
end

-- Every index of `band` matching the theme (and unseen if `fresh_only`).
local function candidates(band, theme, is_seen, fresh_only)
    local list = {}
    for i = 1, Puzzles.count(band) do
        if Puzzles.hasTheme(band, i, theme)
            and not (fresh_only and is_seen(band, i)) then
            list[#list + 1] = i
        end
    end
    return list
end

local function pickFixed(opts, fresh_only)
    for _, band in ipairs(bandOrder(opts.band)) do
        local list = candidates(band, opts.theme, opts.is_seen, fresh_only)
        if #list > 0 then
            return band, list[opts.random(#list)]
        end
    end
end

-- Adaptive: the matching puzzles nearest to the target rating; among those
-- within the smallest window (±50, ±100, ±200 … points) that holds any, one
-- at random, so a run at the same rating is not always the same puzzle.
local function pickAdaptive(opts, fresh_only)
    local target = opts.target or 1200
    local pool = {}
    -- Bands near the target first, so only one or two files get loaded;
    -- all of them only when those hold nothing that matches.
    for _, near_only in ipairs({ true, false }) do
        for _, band in ipairs(Puzzles.BANDS) do
            local r = Puzzles.RANGES[band]
            local near = target + 300 >= r[1] and target - 300 < r[2]
            if near == near_only then
                local list = candidates(band, opts.theme, opts.is_seen, fresh_only)
                for _, i in ipairs(list) do
                    pool[#pool + 1] = { band, i, math.abs(Puzzles.rating(band, i) - target) }
                end
            end
        end
        if #pool > 0 then break end
    end
    if #pool == 0 then return nil end
    local window = 50
    while true do
        local near = {}
        for _, e in ipairs(pool) do
            if e[3] <= window then near[#near + 1] = e end
        end
        if #near > 0 then
            local e = near[opts.random(#near)]
            return e[1], e[2]
        end
        window = window * 2
    end
end

function Puzzles.pick(opts)
    opts = opts or {}
    opts.is_seen = opts.is_seen or function() return false end
    opts.random  = opts.random or math.random
    local pick = opts.band == "adaptive" and pickAdaptive or pickFixed
    if opts.band ~= "adaptive" and not Puzzles.isBand(opts.band) then
        opts.band = Puzzles.BANDS[1]
    end
    local band, index = pick(opts, true)
    if band then return band, index, true end
    band, index = pick(opts, false)
    if band then return band, index, false end
    return nil
end

return Puzzles
