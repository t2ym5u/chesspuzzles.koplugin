-- Difficulty guarantees of the puzzle bank: every band holds puzzles of its
-- documented rating range only, the ranges are ordered and contiguous, the
-- bands get harder on average (rating, solution length, fewer mates in one),
-- and picking honours the band or the adaptive target.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path

local Puzzles = dofile(DIR .. "puzzles.lua")
Puzzles.data_dir = DIR

-- Per band: count, mean rating, mean plies, share of mate-in-one puzzles.
local function bandStats(band)
    local n, rating, plies, mate1 = Puzzles.count(band), 0, 0, 0
    for i = 1, n do
        local p = Puzzles.get(band, i)
        rating = rating + p.rating
        plies = plies + #p.moves
        if p.themes:find(Puzzles.THEME_CODE.mate1, 1, true) then mate1 = mate1 + 1 end
    end
    return { n = n, rating = rating / n, plies = plies / n, mate1 = mate1 / n }
end

describe("Chess puzzles difficulty bands", function()
    teardown(function() Puzzles.unload() end)

    it("rating ranges are ordered and contiguous", function()
        local prev_hi = 0
        for _, band in ipairs(Puzzles.BANDS) do
            local r = Puzzles.RANGES[band]
            assert.are.equal(prev_hi, r[1], band)
            assert.is_true(r[2] > r[1], band)
            prev_hi = r[2]
        end
    end)

    it("every puzzle sits in its band's range, sorted by rating", function()
        local bad = {}
        for _, band in ipairs(Puzzles.BANDS) do
            local lo, hi = Puzzles.RANGES[band][1], Puzzles.RANGES[band][2]
            local prev = -1
            for i = 1, Puzzles.count(band) do
                local r = Puzzles.rating(band, i)
                if r < lo or r >= hi or r < prev then bad[#bad + 1] = band .. ":" .. i end
                prev = r
            end
        end
        assert.are.same({}, bad)
    end)

    it("the bands get harder on average", function()
        local prev
        for _, band in ipairs(Puzzles.BANDS) do
            local s = bandStats(band)
            assert.is_true(s.n >= 1000, band)
            if prev then
                assert.is_true(s.rating > prev.rating, band .. " mean rating")
                assert.is_true(s.plies > prev.plies, band .. " mean solution length")
                assert.is_true(s.mate1 <= prev.mate1, band .. " share of mates in one")
            end
            prev = s
        end
    end)

    it("maps ratings to bands", function()
        assert.are.equal("beginner", Puzzles.bandFor(400))
        assert.are.equal("easy", Puzzles.bandFor(1000))
        assert.are.equal("medium", Puzzles.bandFor(1799))
        assert.are.equal("expert", Puzzles.bandFor(2900))
        for _, band in ipairs(Puzzles.BANDS) do
            local r = Puzzles.RANGES[band]
            assert.are.equal(band, Puzzles.bandFor(r[1]))
            assert.are.equal(band, Puzzles.bandFor(math.min(r[2], 3999) - 1))
        end
    end)
end)

describe("Chess puzzles picking by difficulty", function()
    local function seq() return 1 end
    teardown(function() Puzzles.unload() end)

    it("adaptive picks near the target rating", function()
        for _, target in ipairs({ 700, 1200, 1650, 2000, 2400 }) do
            local band, i, fresh = Puzzles.pick{ band = "adaptive", target = target, random = math.random }
            assert.is_true(fresh)
            assert.is_true(math.abs(Puzzles.rating(band, i) - target) <= 50, target)
        end
    end)

    it("fixed band stays in the band and skips seen puzzles", function()
        local seen = {}
        for _ = 1, 20 do
            local band, i = Puzzles.pick{ band = "hard", random = seq,
                is_seen = function(b, k) return seen[b .. k] end }
            assert.are.equal("hard", band)
            assert.is_nil(seen[band .. i])
            seen[band .. i] = true
        end
    end)

    it("maps ratings to bands", function()
        assert.are.equal("beginner", Puzzles.bandFor(400))
        assert.are.equal("easy", Puzzles.bandFor(1000))
        assert.are.equal("medium", Puzzles.bandFor(1799))
        assert.are.equal("expert", Puzzles.bandFor(2900))
    end)
    it("a fixed band picks only from that band, for every band", function()
        for _, band in ipairs(Puzzles.BANDS) do
            math.randomseed(3)
            for _ = 1, 10 do
                local b, i = Puzzles.pick{ band = band }
                assert.are.equal(band, b)
                local r = Puzzles.rating(b, i)
                assert.is_true(r >= Puzzles.RANGES[band][1] and r < Puzzles.RANGES[band][2])
            end
        end
    end)
end)
