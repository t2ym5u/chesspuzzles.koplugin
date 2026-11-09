local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path

local function load(name) return dofile(DIR .. name .. ".lua") end

local Board   = load("board")
local Game    = load("game")
local Puzzles = load("puzzles")
local Rating  = load("rating")
Puzzles.data_dir = DIR

local function sq(s)   -- "e4" -> r, c
    return 9 - tonumber(s:sub(2, 2)), s:byte(1) - 96
end

local function at(b, s)  -- piece on square "e4"
    local r, c = sq(s)
    return b.sq[r][c]
end

local function legalUCIs(b)
    local t = {}
    for _, m in ipairs(b:getLegalMoves()) do
        t[Board.toUCI(m.fr, m.fc, m.tr, m.tc, m.promo_piece)] = true
    end
    return t
end

describe("board move legality", function()
    it("parses and formats UCI", function()
        local fr, fc, tr, tc, p = Board.parseUCI("e7e8n")
        assert.are.same({ 2, 5, 1, 5, "n" }, { fr, fc, tr, tc, p })
        assert.are.equal("e7e8n", Board.toUCI(2, 5, 1, 5, "n"))
        assert.are.equal("g1f3", Board.toUCI(8, 7, 6, 6))
        assert.is_nil(Board.parseUCI("e9e4"))
    end)

    it("castles both ways when the path is free and safe", function()
        local b = Board:new()
        b:loadFEN("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        local l = legalUCIs(b)
        assert.is_true(l["e1g1"])
        assert.is_true(l["e1c1"])
        assert.is_true(b:applyUCI("e1g1"))
        assert.are.equal(Board.W_ROOK, b.sq[8][6])
        assert.are.equal(Board.W_KING, b.sq[8][7])
        assert.are.equal(Board.EMPTY, b.sq[8][8])
        assert.is_true(b:applyUCI("e8c8"))
        assert.are.equal(Board.B_ROOK, b.sq[1][4])
        assert.are.equal(Board.B_KING, b.sq[1][3])
    end)

    it("refuses castling through check, out of check, or without the right", function()
        local b = Board:new()
        -- Black rook on f8 covers f1: no king-side castling; queen-side fine.
        b:loadFEN("5rk1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        local l = legalUCIs(b)
        assert.is_nil(l["e1g1"])
        assert.is_true(l["e1c1"])
        -- In check: no castling at all.
        b:loadFEN("4r1k1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        l = legalUCIs(b)
        assert.is_nil(l["e1g1"])
        assert.is_nil(l["e1c1"])
        -- No right in the FEN.
        b:loadFEN("6k1/8/8/8/8/8/8/R3K2R w - - 0 1")
        assert.is_false(b:applyUCI("e1g1"))
        -- Moving the rook loses the right.
        b:loadFEN("6k1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        assert.is_true(b:applyUCI("h1h2"))
        assert.is_true(b:applyUCI("g8g7"))
        assert.is_true(b:applyUCI("h2h1"))
        assert.is_true(b:applyUCI("g7g8"))
        assert.is_false(b:applyUCI("e1g1"))
        assert.is_true(b:isLegalUCI("e1c1"))
    end)

    it("takes en passant only right after the double step", function()
        local b = Board:new()
        b:loadFEN("4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1")
        assert.is_true(b:applyUCI("d7d5"))
        assert.is_true(b:isLegalUCI("e5d6"))
        assert.is_true(b:applyUCI("e5d6"))
        assert.are.equal(Board.EMPTY, at(b, "d5"))
        assert.are.equal(Board.W_PAWN, at(b, "d6"))
        -- From a FEN's en passant field, and gone one move later.
        b:loadFEN("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        assert.is_true(b:isLegalUCI("e5d6"))
        assert.is_true(b:applyUCI("e1e2"))
        assert.is_true(b:applyUCI("e8e7"))
        assert.is_false(b:isLegalUCI("e5d6"))
    end)

    it("promotes to the chosen piece", function()
        for p, v in pairs({ q = Board.W_QUEEN, r = Board.W_ROOK, b = Board.W_BISHOP, n = Board.W_KNIGHT }) do
            local b = Board:new()
            b:loadFEN("1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1")
            assert.is_true(b:isPromotionMove(2, 1, 1, 1))
            assert.is_true(b:applyUCI("a7a8" .. p))
            assert.are.equal(v, at(b, "a8"))
            assert.are.equal("a7a8" .. p, b:lastMoveUCI())
        end
        local b = Board:new()
        b:loadFEN("1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1")
        assert.is_true(b:applyUCI("a7b8n"))     -- capture-promotion
        assert.are.equal(Board.W_KNIGHT, at(b, "b8"))
        b:loadFEN("4k3/8/8/8/8/8/p7/4K3 b - - 0 1")
        assert.is_true(b:applyUCI("a2a1r"))
        assert.are.equal(Board.B_ROOK, at(b, "a1"))
    end)

    it("never leaves the own king in check", function()
        local b = Board:new()
        -- The e2 knight is pinned by the e8 rook.
        b:loadFEN("4r1k1/8/8/8/8/8/4N3/4K3 w - - 0 1")
        assert.is_false(b:isLegalUCI("e2c3"))
        assert.is_false(b:applyUCI("e1e2"))
        assert.is_true(b:isLegalUCI("e1d1"))
        assert.is_false(b:applyUCI("e2e4"))     -- not a knight move at all
    end)
end)

describe("shipped puzzles", function()
    it("replay legally, every move of every puzzle", function()
        local total, bad, mates = 0, {}, 0
        local specials = { castle_ks = 0, castle_qs = 0, ep = 0, promo = 0 }
        for _, band in ipairs(Puzzles.BANDS) do
            local n = Puzzles.count(band)
            assert.is_true(n >= 1000, band)
            for i = 1, n do
                local p = Puzzles.get(band, i)
                total = total + 1
                local b = Board:new()
                b:loadFEN(p.fen)
                local ok = #p.moves % 2 == 0
                for _, m in ipairs(p.moves) do
                    if not ok then break end
                    ok = b:applyUCI(m)
                    if ok and b.last_move.special then
                        local s = b.last_move.special
                        specials[s] = specials[s] + 1
                    end
                end
                if ok and p.themes:find("m", 1, true) then
                    ok = b.status == "checkmate"
                    mates = mates + 1
                end
                if not ok then bad[#bad + 1] = band .. ":" .. p.id end
            end
        end
        assert.are.same({}, bad)
        assert.are.equal(10000, total)
        assert.is_true(mates > 1000)
        -- The data exercises the special moves too.
        assert.is_true(specials.promo > 0)
        assert.is_true(specials.castle_ks + specials.castle_qs > 0)
        assert.is_true(specials.ep > 0)
        Puzzles.unload()
    end)

    it("play through the game to 'solved' (sample)", function()
        for _, band in ipairs(Puzzles.BANDS) do
            for i = 1, Puzzles.count(band), 97 do
                local p = Puzzles.get(band, i)
                local g = Game:new()
                g:setPuzzle(p, nil, true)
                assert.are.equal(p.moves[1], g.board:lastMoveUCI())
                while g.state == "play" do
                    assert.are.equal(g.player, g.board.turn)
                    local fr, fc, tr, tc, pr = Board.parseUCI(g:expected())
                    local r = g:tryMove(fr, fc, tr, tc, pr)
                    assert.is_true(r == "correct" or r == "solved", p.id .. " " .. r)
                    if r == "correct" then assert.is_true(g:playReply()) end
                end
                assert.is_true(g:isSolved(), p.id)
                assert.is_false(g.failed)
            end
        end
        Puzzles.unload()
    end)

    it("loads a band only when needed, and release() drops them", function()
        local P = load("puzzles")
        P.data_dir = DIR
        assert.are.same({}, P.loadedBands())
        assert.is_true(P.isBand("hard"))
        assert.are.same({}, P.loadedBands())
        local p = P.get("easy", 1)
        assert.is_truthy(p)
        assert.are.same({ "easy" }, P.loadedBands())
        P.release()
        assert.are.same({}, P.loadedBands())
        -- Reloaded, the same puzzle comes back.
        assert.are.same(p, P.get("easy", 1))
        P.release()
    end)
end)

describe("game", function()
    -- Black's c-pawn move sets it up; both Ra8# and Rb8# mate.
    local MATE = { id = "test1", band = "easy", index = 1, rating = 1200, themes = "1m",
        fen = "7k/2p3pp/8/8/8/8/8/RR4K1 b - - 0 1", moves = { "c7c6", "a1a8" } }
    -- A two-move line: 1...a6 2.Qxf7+ Kd8 3.Qf8#.
    local LONG = { id = "test2", band = "easy", index = 2, rating = 1300, themes = "2m",
        fen = "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 1",
        moves = { "g8f6", "h5f7" } }

    it("plays the opponent's move first and gives the player the other side", function()
        local g = Game:new()
        g:setPuzzle(MATE, nil, true)
        assert.are.equal("white", g.player)
        assert.are.equal("white", g.board.turn)
        assert.are.equal("c7c6", g.board:lastMoveUCI())
        assert.are.equal("a1a8", g:expected())
    end)

    it("accepts the listed mate", function()
        local g = Game:new()
        g:setPuzzle(MATE, nil, true)
        assert.are.equal("solved", g:tryMove(8, 1, 1, 1))
        assert.is_false(g.failed)
    end)

    it("accepts an alternative checkmate", function()
        local g = Game:new()
        g:setPuzzle(MATE, nil, true)
        assert.are.equal("solved", g:tryMove(8, 2, 1, 2))   -- Rb8#
        assert.is_true(g:isSolved())
        assert.is_false(g.failed)
        assert.are.equal("b1b8", g.board:lastMoveUCI())
        assert.are.equal("checkmate", g.board.status)
    end)

    it("marks a wrong move, keeps the board and lets the player retry", function()
        local g = Game:new()
        g:setPuzzle(MATE, nil, true)
        assert.are.equal("wrong", g:tryMove(8, 2, 2, 2))    -- Rb7, no mate
        assert.are.same({ fr = 8, fc = 2, tr = 2, tc = 2 }, g.wrong)
        assert.is_true(g.failed)
        assert.are.equal(Board.W_ROOK, g.board.sq[8][2])
        assert.are.equal("white", g.board.turn)
        assert.are.equal("illegal", g:tryMove(8, 2, 1, 1))  -- not a rook move
        assert.are.equal("solved", g:tryMove(8, 1, 1, 1))
        assert.is_nil(g.wrong)
        assert.is_true(g.failed)
    end)

    it("gives a two-level hint for the expected move", function()
        local g = Game:new()
        g:setPuzzle(LONG, nil, true)
        local fr, fc, tr, tc, level = g:hint()
        assert.are.same({ 4, 8, nil, nil, 1 }, { fr, fc, tr, tc, level })
        fr, fc, tr, tc, level = g:hint()
        assert.are.same({ 4, 8, 2, 6, 2 }, { fr, fc, tr, tc, level })
        assert.is_true(g.failed)
    end)

    it("steps through the solution forwards and back", function()
        local p = Puzzles.get("hard", 5)
        local g = Game:new()
        g:setPuzzle(p, nil, true)
        assert.is_true(g:showSolution())
        assert.is_true(g:isShowingSolution())
        assert.are.equal(#p.moves - 1, g:solutionLength())
        assert.is_false(g:solutionStep(-1))
        for _ = 1, g:solutionLength() do assert.is_true(g:solutionStep(1)) end
        assert.is_false(g:solutionStep(1))
        assert.are.equal(p.moves[#p.moves], g.board:lastMoveUCI())
        assert.is_true(g:solutionStep(-1))
        assert.are.equal(p.moves[#p.moves - 1], g.board:lastMoveUCI())
    end)

    it("saves and restores mid-puzzle and in solution mode", function()
        local p
        for i = 1, Puzzles.count("medium") do
            p = Puzzles.get("medium", i)
            if #p.moves >= 6 then break end
        end
        local g = Game:new()
        g:setPuzzle(p, "2026-11-02", true)
        local fr, fc, tr, tc, pr = Board.parseUCI(p.moves[2])
        assert.are.equal("correct", g:tryMove(fr, fc, tr, tc, pr))
        -- Saved before the reply: restoring plays it.
        local saved = g:serialize()
        local g2 = Game:new()
        assert.is_true(g2:load(saved, Puzzles.get("medium", p.index)))
        assert.are.equal("play", g2.state)
        assert.are.equal(p.moves[3], g2.board:lastMoveUCI())
        assert.are.equal(p.moves[4], g2:expected())
        assert.are.equal("2026-11-02", g2.daily)
        g2:showSolution()
        g2:solutionStep(1)
        local g3 = Game:new()
        assert.is_true(g3:load(g2:serialize(), Puzzles.get("medium", p.index)))
        assert.is_true(g3:isShowingSolution())
        assert.are.equal(1, g3.sol_step)
        assert.are.equal(p.moves[4], g3.board:lastMoveUCI())
        -- A save for another puzzle is refused.
        assert.is_false(Game:new():load(saved, Puzzles.get("medium", p.index + 1)))
    end)
end)

describe("rating", function()
    it("starts at 1200 and moves by half K against an equal puzzle", function()
        assert.are.equal(1200, Rating.START)
        local r, d = Rating.update(1200, 1200, true, 0)
        assert.are.equal(1224, r)
        assert.are.equal(24, d)
        r, d = Rating.update(1200, 1200, false, 0)
        assert.are.equal(1176, r)
        assert.are.equal(-24, d)
    end)

    it("rewards beating a harder puzzle more, and settles with experience", function()
        local _, hard = Rating.update(1200, 1600, true, 0)
        local _, easy = Rating.update(1200, 800, true, 0)
        assert.is_true(hard > easy)
        local _, late = Rating.update(1200, 1200, true, 200)
        assert.is_true(late < 24 and late >= 8)
        local _, lose_easy = Rating.update(1200, 800, false, 0)
        local _, lose_hard = Rating.update(1200, 1600, false, 0)
        assert.is_true(lose_easy < lose_hard)
    end)

    it("stays within bounds", function()
        assert.are.equal(Rating.MIN, (Rating.update(Rating.MIN, 600, false, 0)))
        assert.are.equal(Rating.MAX, (Rating.update(Rating.MAX, 3500, true, 0)))
    end)
end)

describe("puzzle picking", function()
    it("honours the theme filter", function()
        for _ = 1, 10 do
            local band, i = Puzzles.pick{ band = "easy", theme = "mate1" }
            assert.is_true(Puzzles.hasTheme(band, i, "mate1"))
            local p = Puzzles.get(band, i)
            assert.are.equal(2, #p.moves)
        end
        -- Barely any mate-in-1 at Expert: falls back to a neighbouring band.
        local seen_all = function(b, k) return b == "expert" end
        local band = Puzzles.pick{ band = "expert", theme = "mate1", is_seen = seen_all }
        assert.are.equal("hard", band)
    end)

    it("replays when everything matching has been seen", function()
        local band, i, fresh = Puzzles.pick{ band = "beginner", is_seen = function() return true end }
        assert.is_truthy(band and i)
        assert.is_false(fresh)
    end)


end)
