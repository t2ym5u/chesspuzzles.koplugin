-- ---------------------------------------------------------------------------
-- game.lua — one puzzle being played (pure Lua, no UI).
--
-- Lichess convention: the FEN is the position before the opponent's move;
-- moves[1] is that move, played automatically; the player then has to find
-- moves[2], the game answers moves[3], and so on. At any step, a move that
-- checkmates is accepted as well, even when it is not the listed one.
--
-- States: "play" (player to find the next move), "reply" (the player's move
-- was right, the opponent's answer is about to be played), "solved",
-- "solution" (the player gave up; stepping through the remaining moves).
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ChessBoard = lrequire("board")

local Game = {}
Game.__index = Game

function Game:new()
    return setmetatable({ board = ChessBoard:new() }, self)
end

-- Start puzzle `p` (a Puzzles.get table). `daily` is a date string or nil.
-- `ratable`: the puzzle counts for the rating (first time it is played).
function Game:setPuzzle(p, daily, ratable)
    self.puzzle   = p
    self.daily    = daily
    self.ratable  = ratable and true or false
    self.rated    = false     -- the rating has been updated for this puzzle
    self.delta    = nil       -- the rating change it brought
    self.failed   = false     -- a wrong move, a hint or the solution
    self.hints    = 0
    self.hint_level = 0
    self.wrong    = nil
    self.played   = {}
    self.state    = "play"
    self.sol_step = 0
    self.sol_base = 0
    self.board:loadFEN(p.fen)
    self.player   = self.board.turn == "white" and "black" or "white"
    -- The opponent's move that sets the puzzle.
    self:_push(p.moves[1])
end

function Game:_push(uci)
    if not self.board:applyUCI(uci) then return false end
    self.played[#self.played + 1] = uci
    return true
end

function Game:ply()
    return #self.played
end

function Game:isOver()
    return self.state == "solved" or self.state == "solution"
end

function Game:isSolved()
    return self.state == "solved"
end

function Game:isShowingSolution()
    return self.state == "solution"
end

-- The listed move the player is expected to find now.
function Game:expected()
    if self.state ~= "play" then return nil end
    return self.puzzle.moves[#self.played + 1]
end

-- Number of moves the player has to find in the whole puzzle.
function Game:playerMoveCount()
    return math.floor(#self.puzzle.moves / 2)
end

-- Index (1-based) of the player move being looked for now.
function Game:playerMoveIndex()
    return math.floor(#self.played / 2) + 1
end

function Game:needsPromotion(fr, fc, tr, tc)
    return self.state == "play" and self.board:isPromotionMove(fr, fc, tr, tc)
end

-- The player's move. Returns:
--   "illegal" — not a legal move (nothing happens),
--   "wrong"   — legal but not the solution (marked, board unchanged, the
--               puzzle now counts as failed),
--   "correct" — right, the opponent's reply is pending (call playReply),
--   "solved"  — right, and that was the last move (or it mates).
function Game:tryMove(fr, fc, tr, tc, promo)
    if self.state ~= "play" then return "illegal" end
    local b = self.board
    local uci = ChessBoard.toUCI(fr, fc, tr, tc, promo)
    if b:isPromotionMove(fr, fc, tr, tc) and not promo then
        uci = uci .. "q"
    end
    if not b:isLegalUCI(uci) then return "illegal" end
    self.wrong = nil
    self.hint_level = 0
    local expected = self:expected()
    if uci ~= expected then
        -- Any checkmate is a solution too (Lichess does the same).
        b:applyUCI(uci)
        local mate = b.status == "checkmate"
        b:undoMove()
        if not mate then
            self.wrong = { fr = fr, fc = fc, tr = tr, tc = tc }
            self.failed = true
            return "wrong"
        end
        self:_push(uci)
        self.state = "solved"
        return "solved"
    end
    self:_push(uci)
    if #self.played >= #self.puzzle.moves or b.status == "checkmate" then
        self.state = "solved"
        return "solved"
    end
    self.state = "reply"
    return "correct"
end

-- Play the opponent's answer after a correct move.
function Game:playReply()
    if self.state ~= "reply" then return false end
    local uci = self.puzzle.moves[#self.played + 1]
    self.state = "play"
    if not uci then
        self.state = "solved"
        return true
    end
    return self:_push(uci)
end

-- Hint: level 1 names the piece to move, level 2 its target too. Returns
-- fr, fc, tr, tc, level (tr/tc nil at level 1).
function Game:hint()
    local uci = self:expected()
    if not uci then return nil end
    local fr, fc, tr, tc = ChessBoard.parseUCI(uci)
    self.hint_level = math.min(2, self.hint_level + 1)
    self.hints = self.hints + 1
    self.failed = true
    self.wrong = nil
    if self.hint_level == 1 then return fr, fc, nil, nil, 1 end
    return fr, fc, tr, tc, 2
end

-- Give up: step through the rest of the solution from where the player is.
function Game:showSolution()
    if self:isOver() then return false end
    if self.state == "reply" then self:playReply() end
    self.failed = true
    self.wrong = nil
    self.hint_level = 0
    self.state = "solution"
    self.sol_base = #self.played
    self.sol_step = 0
    return true
end

function Game:solutionLength()
    return #self.puzzle.moves - self.sol_base
end

-- dir = 1 forward, -1 back. Returns true when the board changed.
function Game:solutionStep(dir)
    if self.state ~= "solution" then return false end
    if dir > 0 then
        local uci = self.puzzle.moves[self.sol_base + self.sol_step + 1]
        if not uci or not self.board:applyUCI(uci) then return false end
        self.sol_step = self.sol_step + 1
        return true
    elseif self.sol_step > 0 then
        self.board:undoMove()
        self.sol_step = self.sol_step - 1
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Save / restore
-- ---------------------------------------------------------------------------

function Game:serialize()
    local p = self.puzzle
    if not p then return nil end
    local state = self.state == "reply" and "play" or self.state
    return {
        band = p.band, index = p.index, id = p.id,
        played = table.concat(self.played, ","),
        state = state, sol_step = self.sol_step,
        failed = self.failed, hints = self.hints, ratable = self.ratable,
        rated = self.rated, daily = self.daily, delta = self.delta,
    }
end

-- `p`: the puzzle the save names (looked up by the caller). Returns false
-- when the save does not fit it.
function Game:load(t, p)
    if type(t) ~= "table" or not p or p.id ~= t.id then return false end
    self:setPuzzle(p, t.daily, t.ratable)
    local moves = {}
    for m in tostring(t.played or ""):gmatch("[^,]+") do moves[#moves + 1] = m end
    if moves[1] ~= p.moves[1] then return false end
    for i = 2, #moves do
        if not self:_push(moves[i]) then return false end
    end
    self.failed  = t.failed and true or false
    self.hints   = tonumber(t.hints) or 0
    self.rated   = t.rated and true or false
    self.delta   = tonumber(t.delta)
    if t.state == "solved" then
        self.state = "solved"
    elseif t.state == "solution" then
        self.state = "solution"
        self.sol_base = #self.played
        for _ = 1, tonumber(t.sol_step) or 0 do self:solutionStep(1) end
    elseif self.board.turn ~= self.player then
        -- Saved between a right move and the reply: play the reply now.
        self.state = "reply"
        self:playReply()
    end
    return true
end

return Game
