-- The guided lessons (lessons.lua, moved here from Chess Course): the data,
-- playing one through Game (no opening move, unlike the puzzles), saving it,
-- and the screen's lesson progress.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path

local Board   = dofile(DIR .. "board.lua")
local Game    = dofile(DIR .. "game.lua")
local Puzzles = dofile(DIR .. "puzzles.lua")
Puzzles.data_dir = DIR

-- Play lesson `p` right through, as the player would. Returns the last result.
local function playThrough(g)
    local result
    while g.state == "play" do
        local fr, fc, tr, tc, promo = Board.parseUCI(g:expected())
        result = g:tryMove(fr, fc, tr, tc, promo)
        if result == "correct" then assert.is_true(g:playReply()) end
        if result ~= "correct" then break end
    end
    return result
end

describe("lessons data", function()
    it("has 58 lessons in the six categories, each with both languages", function()
        assert.are.equal(58, Puzzles.lessonCount())
        local total, ids = 0, {}
        for _, cat in ipairs(Puzzles.LESSON_CATS) do
            local list = Puzzles.lessonsIn(cat)
            assert.is_true(#list > 0, cat)
            total = total + #list
        end
        assert.are.equal(58, total)
        for i = 1, Puzzles.lessonCount() do
            local p = Puzzles.getLesson(i)
            local l = p.lesson
            assert.is_nil(ids[p.id], p.id)
            ids[p.id] = true
            for _, f in ipairs({ "title", "title_en", "desc", "desc_en", "hint", "hint_en" }) do
                assert.is_string(l[f], p.id .. " " .. f)
            end
            assert.is_true(#p.moves >= 1, p.id)
        end
    end)

    it("every lesson can be played through to the end", function()
        for i = 1, Puzzles.lessonCount() do
            local g = Game:new()
            g:setPuzzle(Puzzles.getLesson(i), nil, false)
            assert.are.equal(0, g:ply(), "lesson " .. i .. " starts with no move played")
            assert.are.equal("solved", playThrough(g), "lesson " .. i)
        end
    end)

    it("mate lessons end in checkmate", function()
        for _, cat in ipairs({ "mate1", "mate2", "mate3" }) do
            for _, i in ipairs(Puzzles.lessonsIn(cat)) do
                local g = Game:new()
                g:setPuzzle(Puzzles.getLesson(i), nil, false)
                playThrough(g)
                assert.are.equal("checkmate", g.board.status, "lesson " .. i)
            end
        end
    end)
end)

describe("a lesson in Game", function()
    it("lets the side to move play first and counts its moves", function()
        local i = Puzzles.lessonsIn("mate2")[1]
        local p = Puzzles.getLesson(i)
        local g = Game:new()
        g:setPuzzle(p, nil, false)
        local b = Board:new(); b:loadFEN(p.fen)
        assert.are.equal(b.turn, g.player)
        assert.are.equal(math.floor((#p.moves + 1) / 2), g:playerMoveCount())
        assert.are.equal(1, g:playerMoveIndex())
        assert.are.equal(p.moves[1], g:expected())
    end)

    it("accepts any checkmate, like the puzzles", function()
        -- Lesson 1: Ra8# is listed; the game takes any mating move.
        local g = Game:new()
        g:setPuzzle(Puzzles.getLesson(1), nil, false)
        assert.are.equal("wrong", g:tryMove(8, 1, 7, 1))   -- Ra2, no mate
        assert.are.equal("solved", g:tryMove(8, 1, 1, 1))  -- Ra8#
    end)

    it("is saved and restored in the middle of the solution", function()
        local i = Puzzles.lessonsIn("mate2")[1]
        local p = Puzzles.getLesson(i)
        local g = Game:new()
        g:setPuzzle(p, nil, false)
        local fr, fc, tr, tc = Board.parseUCI(g:expected())
        assert.are.equal("correct", g:tryMove(fr, fc, tr, tc))
        g:playReply()
        local saved = g:serialize()
        assert.are.equal("lessons", saved.band)
        local g2 = Game:new()
        assert.is_true(g2:load(saved, Puzzles.getLesson(saved.index)))
        assert.are.equal(g:ply(), g2:ply())
        assert.are.equal(g:expected(), g2:expected())
        assert.are.equal("solved", playThrough(g2))
    end)
end)

describe("lesson progress on the screen", function()
    local saved = {}

    -- Every other module is a stub: any field is another stub, and calling
    -- one returns its last argument, so Class:extend{} returns its table
    -- and _("x") returns "x".
    local function stub()
        return setmetatable({}, {
            __index = function(t, k) local s = stub(); rawset(t, k, s); return s end,
            __call  = function(_, a, b) if b ~= nil then return b end return a end,
        })
    end

    local function stubSearcher(name)
        return function() return stub() end, name
    end

    setup(function()
        saved.loaded = {}
        for k, v in pairs(package.loaded) do saved.loaded[k] = v end
        for k in pairs(saved.loaded) do
            if type(k) == "string" and k:sub(1, #DIR) == DIR then package.loaded[k] = nil end
        end
        for _, name in ipairs({ "device", "screen_base", "menu_helper", "i18n", "party",
                                "daily_seed", "grid_widget_base" }) do
            package.loaded[name] = stub()
        end
        package.loaded["ui/uimanager"] = setmetatable({}, { __index = function() return function() end end })
        local searchers = package.searchers or package.loaders
        searchers[#searchers + 1] = stubSearcher
    end)

    teardown(function()
        local searchers = package.searchers or package.loaders
        for i = #searchers, 1, -1 do
            if searchers[i] == stubSearcher then table.remove(searchers, i) end
        end
        for k in pairs(package.loaded) do
            if saved.loaded[k] == nil then package.loaded[k] = nil end
        end
        for k, v in pairs(saved.loaded) do package.loaded[k] = v end
    end)

    -- A screen whose plugin keeps its settings in a table; `course` stands
    -- for Chess Course's settings file.
    local function newScreen(settings, course)
        local Screen = dofile(DIR .. "screen.lua")
        local plugin = {
            getSetting  = function(_, k, d) if settings[k] == nil then return d end return settings[k] end,
            saveSetting = function(_, k, v) settings[k] = v end,
            saveState   = function(_, v) settings.state = v end,
            getLang     = function() return "en" end,
            readOtherSettings = function(_, id) return id == "chesscourse" and course or nil end,
        }
        return setmetatable({
            plugin = plugin, game = Game:new(),
            updateStatus = function() end, buildLayout = function() end,
            _refreshBoard = function() end,
        }, { __index = Screen })
    end

    it("starts where Chess Course was left, then where the player was", function()
        local settings = {}
        local scr = newScreen(settings, { state = { lesson_idx = 12 } })
        assert.are.equal(12, scr:lastLesson())
        settings.lesson = 30
        assert.are.equal(30, scr:lastLesson())
        assert.are.equal(1, newScreen({}, nil):lastLesson())
    end)

    it("marks a lesson done once solved, and moves on to the next", function()
        local settings = {}
        local scr = newScreen(settings)
        scr:openLesson(1)
        assert.are.equal(1, settings.lesson)
        scr:_playerMove(8, 1, 1, 1)   -- Ra8#
        assert.is_true(scr.game:isSolved())
        assert.is_true(scr:isLessonDone(1))
        assert.are.equal(1, scr:lessonsDoneCount())
        assert.are.equal("Next lesson", scr:getRoundOverButtons()[1].text)
        scr:onNextLesson()
        assert.are.equal(2, scr.game.puzzle.index)
        assert.are.equal(2, settings.lesson)
        assert.is_false(scr:isLessonDone(2))
    end)

    it("leaves the rating and the statistics alone", function()
        local settings = {}
        local scr = newScreen(settings)
        scr:openLesson(1)
        scr:_playerMove(8, 1, 7, 1)   -- wrong
        scr:_playerMove(8, 1, 1, 1)   -- Ra8#
        assert.is_nil(settings.rating)
        assert.is_nil(settings.rated_count)
        assert.is_nil(settings.failed_count)
    end)
end)
