-- Spec for the multiplayer match (party_match.lua): claims, wrong moves,
-- points, clock, rounds and save/restore, plus a match played on real
-- puzzles through Game.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path

package.loaded["i18n"] = function(s) return s end
package.loaded["ffi/util"] = { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end }

local Match   = dofile(DIR .. "party_match.lua")
local Game    = dofile(DIR .. "game.lua")
local Puzzles = dofile(DIR .. "puzzles.lua")
local Board   = dofile(DIR .. "board.lua")
Puzzles.data_dir = DIR

describe("Chess Puzzles match", function()
    it("scores by band and moves to find, minus hints", function()
        assert.are.equal(1, Match.basePoints("beginner", 1))
        assert.are.equal(5, Match.basePoints("expert", 1))
        assert.are.equal(4, Match.basePoints("medium", 2))
        local m = Match.new({ "A", "B" }, { band = "easy" })
        m:startPuzzle(7, 2)
        assert.are.equal(3, m.value)
        m:hint(); m:hint(); m:hint()
        assert.are.equal(1, m.value)
        assert.is_true(m:claim(2))
        assert.are.equal(1, m:solved())
        assert.are.same({ 0, 1 }, m.scores.points)
        assert.are.equal("solved", m.result)
        assert.are.equal(2, m.winner)
    end)

    it("a wrong move puts the player out; the others may still claim", function()
        local m = Match.new({ "A", "B", "C" }, { band = "hard" })
        m:startPuzzle(1, 1)
        assert.is_true(m:claim(1))
        assert.is_false(m:claim(2))          -- one attempt at a time
        assert.is_false(m:wrong())
        assert.is_true(m:isOut(1))
        assert.is_false(m:canClaim(1))
        assert.are.same({ 2, 3 }, m:remaining())
        assert.is_true(m:claim(3))
        assert.is_false(m:wrong())
        assert.is_true(m:claim(2))
        assert.is_true(m:wrong())            -- nobody left
        assert.are.equal("all_out", m.result)
        assert.is_true(m:isPuzzleOver())
        assert.are.same({ 0, 0, 0 }, m.scores.points)
        assert.are.equal(0, m:solved())
    end)

    it("runs the clock only between attempts", function()
        local m = Match.new({ "A", "B" }, { duration = 2 })
        m:startPuzzle(1, 1)
        m:claim(1)
        assert.is_false(m:tick())
        assert.are.equal(2, m.time_left)
        m:wrong()
        assert.is_false(m:tick())
        assert.is_true(m:tick())
        assert.are.equal("time_up", m.result)
        assert.is_false(m:claim(2))
        local free = Match.new({ "A", "B" }, { duration = 0 })
        free:startPuzzle(1, 1)
        assert.is_false(free:tick())
        assert.is_false(free:isPuzzleOver())
    end)

    it("counts rounds, ends after N puzzles, never deals one twice", function()
        local m = Match.new({ "A", "B" }, { rounds = 2 })
        m:startPuzzle(4, 1)
        m:giveUp()
        assert.are.equal("given_up", m.result)
        assert.is_false(m:isOver())
        m:startPuzzle(9, 1)
        assert.are.equal(2, m:round())
        assert.is_nil(m.result)
        assert.is_true(m:wasUsed(4) and m:wasUsed(9))
        assert.is_false(m:wasUsed(5))
        m:claim(1); m:solved()
        assert.is_true(m:isOver())
    end)

    it("saves and restores mid-puzzle and finished", function()
        local m = Match.new({ "Alice", "Bob", "Chloé" }, { rounds = 3, duration = 60, band = "medium" })
        m:startPuzzle(12, 2)
        m:claim(2); m:wrong(); m:hint(); m:tick(); m:claim(3)
        local r = Match.restore(m:serialize())
        assert.are.same(m.scores, r.scores)
        assert.are.equal("medium", r.band)
        assert.are.equal(3, r.value)
        assert.are.equal(59, r.time_left)
        assert.are.equal(3, r.player)
        assert.is_true(r:isOut(2))
        assert.is_true(r:wasUsed(12))
        r:solved()
        local r2 = Match.restore(r:serialize())
        assert.are.equal("solved", r2.result)
        assert.are.equal(3, r2.winner)
        assert.is_nil(r2.player)
        assert.are.same({ 0, 0, 3 }, r2.scores.points)
        assert.is_nil(Match.restore({}))
        assert.is_nil(Match.restore({ scores = { names = { "A" }, points = { 0 }, round = 1 },
            index = 1, band = "nope" }))
    end)

    it("plays a match on real puzzles through the game", function()
        math.randomseed(11)
        local m = Match.new({ "A", "B" }, { rounds = 3, band = "beginner", duration = 0 })
        local g = Game:new()
        for round = 1, 3 do
            local band, index = Puzzles.pick{ band = m.band,
                is_seen = function(b, i) return b == m.band and m:wasUsed(i) end }
            local p = Puzzles.get(band, index)
            g:setPuzzle(p, nil, false)
            m:startPuzzle(index, g:playerMoveCount())
            -- A plays a wrong (legal) move, is out; B plays the solution.
            m:claim(1)
            local wrong
            for _i, mv in ipairs(g.board:getLegalMoves()) do
                local copy = Game:new(); copy:setPuzzle(p, nil, false)
                if copy:tryMove(mv.fr, mv.fc, mv.tr, mv.tc, mv.promo_piece) == "wrong" then
                    wrong = mv
                    break
                end
            end
            if wrong then
                assert.are.equal("wrong", g:tryMove(wrong.fr, wrong.fc, wrong.tr, wrong.tc, wrong.promo_piece))
                assert.is_false(m:wrong())
                g:setPuzzle(p, nil, false)
            end
            m:claim(2)
            local res
            repeat
                local exp = g:expected()
                local fr, fc, tr, tc, promo = Board.parseUCI(exp)
                res = g:tryMove(fr, fc, tr, tc, promo)
                if res == "correct" then g:playReply() end
            until res == "solved"
            assert.is_true(m:solved() > 0)
            assert.are.equal(round, m:round())
        end
        assert.is_true(m:isOver())
        assert.are.equal(0, m.scores.points[1])
        assert.is_true(m.scores.points[2] >= 3)
        assert.are.equal(3, #m.used)
    end)
end)
