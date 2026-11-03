-- ---------------------------------------------------------------------------
-- party_match.lua — a "· multiplayer" Chess Puzzles match (pure Lua, no UI).
--
-- Players (or teams) sit around one board. A puzzle is shown with a clock;
-- whoever thinks they have it claims it ("Who has it?") and plays the moves.
-- The clock stops during an attempt. The whole solution right wins the
-- puzzle's points; one wrong move and that player is out for this puzzle,
-- the position goes back to the start and the clock runs again for the
-- others. The puzzle ends when it is solved, when everyone is out, when the
-- time is up or when the solution is shown. A match is N puzzles, all from
-- one difficulty band. Nothing here touches the solo rating.
--
-- Points: the band's value (Beginner 1 … Expert 5) plus 1 for each move to
-- find beyond the first; each hint takes 1 off (never below 1).
-- ---------------------------------------------------------------------------

local Party = require("party")

local Match = {}
Match.__index = Match

Match.ROUNDS    = { 3, 5, 10 }
Match.DURATIONS = { 0, 60, 120, 180, 300 }   -- seconds, 0 = no limit
Match.BAND_POINTS = { beginner = 1, easy = 2, medium = 3, hard = 4, expert = 5 }

-- opts: rounds (default 5), duration (seconds, 0 = none, default 120),
-- band (default "easy").
function Match.new(names, opts)
    opts = opts or {}
    return setmetatable({
        scores   = Party.newScores(names),
        rounds   = tonumber(opts.rounds) or 5,
        duration = tonumber(opts.duration) or 120,
        band     = Match.BAND_POINTS[opts.band] and opts.band or "easy",
        used     = {},     -- puzzle indices already dealt in this match
        result   = nil,
    }, Match)
end

-- Points for a puzzle of `band` with `moves` player moves to find.
function Match.basePoints(band, moves)
    return (Match.BAND_POINTS[band] or 1) + math.max(0, (moves or 1) - 1)
end

-- A new puzzle (index in the band, number of player moves): next round,
-- fresh clock, nobody out.
function Match:startPuzzle(index, moves)
    Party.nextRound(self.scores)
    self.used[#self.used + 1] = index
    self.index     = index
    self.value     = Match.basePoints(self.band, moves)
    self.hints     = 0
    self.out       = {}
    self.player    = nil
    self.winner    = nil
    self.result    = nil   -- "solved" | "all_out" | "time_up" | "given_up"
    self.time_left = self.duration
end

function Match:wasUsed(index)
    for _i, v in ipairs(self.used) do
        if v == index then return true end
    end
    return false
end

function Match:round()
    return self.scores.round
end

function Match:hasClock()
    return self.duration > 0
end

function Match:isPuzzleOver()
    return self.result ~= nil
end

function Match:isLastRound()
    return self.scores.round >= self.rounds
end

function Match:isOver()
    return self:isPuzzleOver() and self:isLastRound()
end

function Match:isOut(i)
    return self.out[i] == true
end

-- The players who may still claim the puzzle (seat indices).
function Match:remaining()
    local list = {}
    for i = 1, #self.scores.names do
        if not self.out[i] then list[#list + 1] = i end
    end
    return list
end

function Match:canClaim(i)
    return not self:isPuzzleOver() and self.player == nil
        and self.scores.names[i] ~= nil and not self.out[i]
end

-- Player i says they have it: their attempt starts (the clock stops).
function Match:claim(i)
    if not self:canClaim(i) then return false end
    self.player = i
    return true
end

-- The player on the move went wrong: out for this puzzle. Returns true when
-- that leaves nobody (the puzzle is then over).
function Match:wrong()
    if not self.player then return false end
    self.out[self.player] = true
    self.player = nil
    if #self:remaining() == 0 then
        self.result = "all_out"
        return true
    end
    return false
end

-- The player on the move found the whole solution. Returns the points won.
function Match:solved()
    if not self.player or self:isPuzzleOver() then return 0 end
    local i = self.player
    Party.award(self.scores, i, self.value)
    self.winner = i
    self.player = nil
    self.result = "solved"
    return self.value
end

-- A hint, for everyone to see: the puzzle is worth 1 less (at least 1).
function Match:hint()
    if self:isPuzzleOver() then return end
    self.hints = self.hints + 1
    self.value = math.max(1, self.value - 1)
end

function Match:giveUp()
    if self:isPuzzleOver() then return end
    self.player = nil
    self.result = "given_up"
end

-- One second off the clock; it does not run during an attempt. Returns true
-- when that ran it out (the puzzle is then over).
function Match:tick()
    if not self:hasClock() or self:isPuzzleOver() or self.player then return false end
    self.time_left = math.max(0, self.time_left - 1)
    if self.time_left == 0 then
        self.result = "time_up"
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Save / restore
-- ---------------------------------------------------------------------------

function Match:serialize()
    local out = {}
    for i in pairs(self.out) do out[#out + 1] = i end
    local used = {}
    for k, v in ipairs(self.used) do used[k] = v end
    return {
        scores = Party.copyScores(self.scores),
        rounds = self.rounds, duration = self.duration, band = self.band,
        used = used, index = self.index, value = self.value, hints = self.hints,
        out = out, player = self.player, winner = self.winner,
        result = self.result, time_left = self.time_left,
    }
end

-- Returns a Match, or nil when `t` is unusable.
function Match.restore(t)
    if type(t) ~= "table" then return nil end
    local scores = Party.restoreScores(t.scores)
    if not scores or scores.round < 1 or not tonumber(t.index) then return nil end
    if not Match.BAND_POINTS[t.band] then return nil end
    local m = setmetatable({
        scores    = scores,
        rounds    = tonumber(t.rounds) or 5,
        duration  = tonumber(t.duration) or 0,
        band      = t.band,
        used      = {},
        index     = tonumber(t.index),
        value     = tonumber(t.value) or 1,
        hints     = tonumber(t.hints) or 0,
        out       = {},
        time_left = tonumber(t.time_left) or 0,
    }, Match)
    for _i, v in ipairs(type(t.used) == "table" and t.used or {}) do
        if tonumber(v) then m.used[#m.used + 1] = tonumber(v) end
    end
    for _i, v in ipairs(type(t.out) == "table" and t.out or {}) do
        if scores.names[v] then m.out[v] = true end
    end
    local valid = { solved = true, all_out = true, time_up = true, given_up = true }
    m.result = valid[t.result] and t.result or nil
    if scores.names[t.player] and not m.result then m.player = t.player end
    if scores.names[t.winner] then m.winner = t.winner end
    return m
end

return Match
